extends Node
class_name SimController

## Drives sim time, contact plan, router; creates nodes and links; spawns bundles and delivers completed transfers.

const CONTACT_PLAN_PATH := "res://data/contact_plan.json"
const DEFAULT_BUNDLE_SIZE_BITS := 512

@export var sim_speed: float = 1.0  # 1.0 = 1 real sec = 1 sim sec
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
var total_delivered: int = 0
var _next_spawn_ms: int = 0

var dtn_node_scene: PackedScene
var link_up_color := Color(0.2, 0.9, 0.3)
var link_down_color := Color(0.35, 0.35, 0.4)


func _ready() -> void:
	router = DtnRouter.new()
	if not router.load_contact_plan(CONTACT_PLAN_PATH):
		push_error("SimController: failed to load contact plan")
		return
	dtn_node_scene = load("res://scenes/simulation/dtn_node.tscn") as PackedScene
	if not dtn_node_scene:
		push_error("SimController: could not load dtn_node.tscn")
		return
	_setup_containers()
	_create_nodes()
	_create_links()
	_update_link_colors()
	_setup_ui()
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

	# Step egress and deliver completed bundles
	var delta_sec := delta * sim_speed
	for node_id in nodes.keys():
		var node: DtnNode = nodes[node_id]
		var completed: Array = node.step_egress(delta_sec)
		for pair in completed:
			var dest_id: int = pair[0]
			var bundle: DtnBundle = pair[1]
			if nodes.has(dest_id):
				nodes[dest_id].receive_bundle(bundle)
				if bundle.dest == dest_id:
					total_delivered += 1


func _spawn_bundle(source_id: int, dest_id: int) -> void:
	if not nodes.has(source_id):
		return
	var bundle := DtnBundle.new(source_id, dest_id, DEFAULT_BUNDLE_SIZE_BITS, sim_time_ms)
	nodes[source_id].receive_bundle(bundle)


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


func _update_ui_labels() -> void:
	var time_label := get_node_or_null("UI/TopBar/TimeLabel") as Label
	if time_label:
		time_label.text = "Time: %d s" % (sim_time_ms / 1000)
	var stats_label := get_node_or_null("UI/TopBar/StatsLabel") as Label
	if stats_label:
		stats_label.text = "Storage: %d  In flight: %d  Delivered: %d" % [
			get_total_storage_count(),
			get_total_in_flight_count(),
			total_delivered
		]
