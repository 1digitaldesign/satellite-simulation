extends Node
class_name SimController

## Drives sim time, contact plan, router; creates nodes and links; spawns bundles and delivers completed transfers.

const CONTACT_PLAN_PATH := "res://data/contact_plan.json"
const DEFAULT_BUNDLE_SIZE_BITS := 512
const PACKET_SPEED_PIXELS_PER_SEC: float = 120.0  # game physics: packet propagation speed

@export var sim_speed: float = 1.0  # 1.0 = 1 real sec = 1 sim sec
@export var use_physics_packets: bool = true  # packets move as physics bodies along links
@export var current_algorithm_id: int = 0  # TransmissionAlgorithms.Algorithm (0=FIFO, 1=LIFO, ... 29)
@export var auto_spawn_bundles: bool = true
@export var spawn_interval_ms: int = 500
@export var spawn_source: int = 102
@export var spawn_dest: int = 1

var sim_time_ms: int = 0
var paused: bool = false
var router: DtnRouter
var nodes: Dictionary = {}  # node_id -> DtnNode
var links: Array = []  # { "source": int, "dest": int, "line": Line2D }
var node_container: Node2D
var link_container: Node2D
var packet_container: Node2D
var total_delivered: int = 0
var _next_spawn_ms: int = 0

var dtn_node_scene: PackedScene
var packet_body_scene: PackedScene
var link_up_color := Color(0.2, 0.9, 0.3)
var link_down_color := Color(0.35, 0.35, 0.4)
var _contact_timeline_contacts: Array = []  # Control nodes for each contact bar
var _telemetry_labels: Dictionary = {}  # node_id -> Label
var _timeline_max_ms: int = 1


func _ready() -> void:
	router = DtnRouter.new()
	if not router.load_contact_plan(CONTACT_PLAN_PATH):
		push_error("SimController: failed to load contact plan")
		return
	dtn_node_scene = load("res://scenes/simulation/dtn_node.tscn") as PackedScene
	if not dtn_node_scene:
		push_error("SimController: could not load dtn_node.tscn")
		return
	packet_body_scene = load("res://scenes/simulation/packet_body.tscn") as PackedScene
	if not packet_body_scene:
		use_physics_packets = false
	_setup_containers()
	_create_nodes()
	_create_links()
	_update_link_colors()
	_setup_ui()
	_build_contact_timeline()
	_build_telemetry_panel()
	if auto_spawn_bundles:
		_next_spawn_ms = 0


func _setup_containers() -> void:
	node_container = get_node_or_null("NodeContainer")
	if not node_container:
		node_container = Node2D.new()
		node_container.name = "NodeContainer"
		add_child(node_container)
	link_container = get_node_or_null("LinkContainer")
	if not link_container:
		link_container = Node2D.new()
		link_container.name = "LinkContainer"
		add_child(link_container)
		if link_container.get_index() > node_container.get_index():
			move_child(link_container, 0)
	var view_size := get_viewport().get_visible_rect().size
	var center := view_size / 2.0
	node_container.position = center
	link_container.position = center
	packet_container = get_node_or_null("PacketContainer")
	if not packet_container:
		packet_container = Node2D.new()
		packet_container.name = "PacketContainer"
		add_child(packet_container)
	packet_container.position = center
	packet_container.z_index = 1


func _create_nodes() -> void:
	var ids: Array = router.get_unique_node_ids()
	var n := ids.size()
	var radius := 200.0
	for i in range(n):
		var node_id: int = ids[i]
		var angle := TAU * float(i) / float(n) - TAU / 4.0
		var pos := Vector2(radius * cos(angle), radius * sin(angle))
		var node_inst: DtnNode = dtn_node_scene.instantiate() as DtnNode
		if not node_inst:
			continue
		node_inst.node_id = node_id
		node_inst.position = pos
		node_inst.set_router(router)
		node_inst.transmission_algorithm_id = current_algorithm_id
		node_container.add_child(node_inst)
		nodes[node_id] = node_inst
		node_inst.set_sim_time(sim_time_ms)


func _create_links() -> void:
	for c in router.get_all_contacts():
		var src: int = c["source"]
		var dst: int = c["dest"]
		if not nodes.has(src) or not nodes.has(dst):
			continue
		var line := Line2D.new()
		line.width = 2.0
		line.add_point(nodes[src].position)
		line.add_point(nodes[dst].position)
		link_container.add_child(line)
		links.append({"source": src, "dest": dst, "line": line})
	link_container.z_index = -1


func _update_link_colors() -> void:
	for link in links:
		var up: bool = router.get_link_state(link["source"], link["dest"], sim_time_ms)
		link["line"].default_color = link_up_color if up else link_down_color


func _setup_ui() -> void:
	var pause_btn := get_node_or_null("UI/TopBar/PauseButton") as Button
	if pause_btn:
		pause_btn.pressed.connect(_on_pause_pressed)
	var s1 := get_node_or_null("UI/TopBar/Speed1") as Button
	if s1:
		s1.pressed.connect(_on_speed_1x)
	var s2 := get_node_or_null("UI/TopBar/Speed2") as Button
	if s2:
		s2.pressed.connect(_on_speed_2x)
	var s10 := get_node_or_null("UI/TopBar/Speed10") as Button
	if s10:
		s10.pressed.connect(_on_speed_10x)
	var alg_btn := get_node_or_null("UI/AlgorithmBar/AlgorithmOption") as OptionButton
	if alg_btn:
		for i in range(TransmissionAlgorithms.ALGORITHM_COUNT):
			alg_btn.add_item(TransmissionAlgorithms.get_algorithm_name(i), i)
		alg_btn.select(current_algorithm_id)
		alg_btn.item_selected.connect(_on_algorithm_selected)


func _on_pause_pressed() -> void:
	paused = !paused
	var pause_btn := get_node_or_null("UI/TopBar/PauseButton") as Button
	if pause_btn:
		pause_btn.text = "Resume" if paused else "Pause"


func _on_speed_1x() -> void:
	set_speed(1.0)


func _on_speed_2x() -> void:
	set_speed(2.0)


func _on_speed_10x() -> void:
	set_speed(10.0)


func _on_algorithm_selected(index: int) -> void:
	current_algorithm_id = index
	_apply_algorithm()


func _apply_algorithm() -> void:
	for node in nodes.values():
		(node as DtnNode).transmission_algorithm_id = current_algorithm_id


func _process(delta: float) -> void:
	_update_ui_labels()
	if not router or paused:
		return
	var step_ms := int(delta * sim_speed * 1000.0)
	sim_time_ms += step_ms

	# Spawn bundles
	if auto_spawn_bundles and sim_time_ms >= _next_spawn_ms:
		_spawn_bundle(spawn_source, spawn_dest)
		_next_spawn_ms = sim_time_ms + spawn_interval_ms

	# Update link state and release storage -> egress
	for node in nodes.values():
		(node as DtnNode).set_sim_time(sim_time_ms)
	_update_link_colors()

	# Step egress and deliver completed bundles (or spawn physics packets)
	var delta_sec := delta * sim_speed
	for node_id in nodes.keys():
		var node: DtnNode = nodes[node_id]
		var completed: Array = node.step_egress(delta_sec)
		for pair in completed:
			var dest_id: int = pair[0]
			var bundle: DtnBundle = pair[1]
			if use_physics_packets and packet_body_scene and packet_container and nodes.has(bundle.source) and nodes.has(dest_id):
				_spawn_packet_body(node_id, dest_id, bundle)
			elif nodes.has(dest_id):
				_deliver_bundle(dest_id, bundle)


func _spawn_packet_body(source_node_id: int, dest_node_id: int, bundle: DtnBundle) -> void:
	var src_node: DtnNode = nodes[source_node_id]
	var dst_node: DtnNode = nodes[dest_node_id]
	var start_pos: Vector2 = src_node.position
	var target_pos: Vector2 = dst_node.position
	var speed: float = PACKET_SPEED_PIXELS_PER_SEC * sim_speed
	var body: PacketBody = packet_body_scene.instantiate() as PacketBody
	if not body:
		_deliver_bundle(dest_node_id, bundle)
		return
	body.setup(start_pos, target_pos, bundle, dest_node_id, speed)
	body.arrived.connect(func(dest_id: int, b: DtnBundle) -> void:
		_deliver_bundle(dest_id, b)
		body.queue_free()
	)
	packet_container.add_child(body)


func _deliver_bundle(dest_node_id: int, bundle: DtnBundle) -> void:
	if nodes.has(dest_node_id):
		nodes[dest_node_id].receive_bundle(bundle)
		if bundle.dest == dest_node_id:
			total_delivered += 1


func inject_bundle(source_id: int, dest_id: int, size_bits: int := DEFAULT_BUNDLE_SIZE_BITS) -> void:
	if not nodes.has(source_id):
		return
	var bundle := DtnBundle.new(source_id, dest_id, size_bits, sim_time_ms)
	nodes[source_id].receive_bundle(bundle)


func set_paused(p: bool) -> void:
	paused = p


func set_speed(speed: float) -> void:
	sim_speed = maxf(0.0, speed)


func get_total_storage_count() -> int:
	var n := 0
	for node in nodes.values():
		n += (node as DtnNode).get_storage_count()
	return n


func get_total_in_flight_count() -> int:
	var n := 0
	for node in nodes.values():
		n += (node as DtnNode).get_in_flight_count()
	return n


func _build_contact_timeline() -> void:
	var contacts_box := get_node_or_null("UI/ContactTimeline/VBox/Contacts") as VBoxContainer
	if not contacts_box or not router:
		return
	var all := router.get_all_contacts()
	_timeline_max_ms = 0
	for c in all:
		if c["endTime"] > _timeline_max_ms:
			_timeline_max_ms = c["endTime"]
	if _timeline_max_ms < 1:
		_timeline_max_ms = 1
	for c in all:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 18
		var lbl := Label.new()
		lbl.text = "%d → %d" % [c["source"], c["dest"]]
		lbl.custom_minimum_size.x = 56
		row.add_child(lbl)
		var bar := ProgressBar.new()
		bar.custom_minimum_size.x = 280
		bar.show_percentage = false
		bar.min_value = 0
		bar.max_value = 100
		bar.set_meta("start_pct", 100.0 * float(c["startTime"]) / float(_timeline_max_ms))
		bar.set_meta("end_pct", 100.0 * float(c["endTime"]) / float(_timeline_max_ms))
		row.add_child(bar)
		contacts_box.add_child(row)
		_contact_timeline_contacts.append(bar)


func _update_contact_timeline() -> void:
	var t := sim_time_ms
	var cursor_pct := 100.0 * float(t) / float(_timeline_max_ms) if _timeline_max_ms > 0 else 0.0
	for bar in _contact_timeline_contacts:
		if not bar is ProgressBar:
			continue
		var start_pct: float = bar.get_meta("start_pct", 0)
		var end_pct: float = bar.get_meta("end_pct", 100)
		bar.min_value = 0
		bar.max_value = 100
		bar.value = start_pct  # fill from 0 to start = empty segment; then we show fill from start to end
		# ProgressBar fills 0..value. We want segment [start_pct, end_pct] visible. Use value = end_pct, min = start_pct so fill is start->end
		bar.min_value = start_pct
		bar.max_value = end_pct
		bar.value = end_pct if cursor_pct >= start_pct and cursor_pct < end_pct else start_pct
		if cursor_pct >= start_pct and cursor_pct < end_pct:
			bar.modulate = link_up_color
		else:
			bar.modulate = Color(0.5, 0.5, 0.55)


func _build_telemetry_panel() -> void:
	var list := get_node_or_null("UI/TelemetryPanel/VBox/TelemetryScroll/TelemetryList") as VBoxContainer
	if not list or not router:
		return
	for node_id in nodes.keys():
		var lbl := Label.new()
		lbl.name = "Node%d" % node_id
		lbl.text = "Node %d: -" % node_id
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		list.add_child(lbl)
		_telemetry_labels[node_id] = lbl


func _update_telemetry() -> void:
	for node_id in _telemetry_labels:
		var lbl: Label = _telemetry_labels[node_id]
		if not lbl:
			continue
		if not nodes.has(node_id):
			continue
		var node: DtnNode = nodes[node_id]
		var cap_kb := node.max_storage_bytes / 1024
		var used_kb := node.get_storage_used_bytes() / 1024
		lbl.text = "N%d In:%d Eg:%d St:%d/%dKB D:%d Drp:%d" % [
			node_id,
			node.get_ingress_count(),
			node.get_egress_sent_count(),
			used_kb,
			cap_kb,
			node.get_delivered_count(),
			node.get_storage_dropped_count()
		]


func _update_ui_labels() -> void:
	var time_label := get_node_or_null("UI/TopBar/TimeLabel") as Label
	if time_label:
		time_label.text = "Time: %d s" % (sim_time_ms / 1000)
	var stats_label := get_node_or_null("UI/TopBar/StatsLabel") as Label
	if stats_label:
		var alg_name := TransmissionAlgorithms.get_algorithm_name(current_algorithm_id)
		stats_label.text = "[%s]  Storage: %d  In flight: %d  Delivered: %d" % [
			alg_name,
			get_total_storage_count(),
			get_total_in_flight_count(),
			total_delivered
		]
	_update_contact_timeline()
	_update_telemetry()
