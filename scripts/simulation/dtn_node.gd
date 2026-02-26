extends Node2D
class_name DtnNode

## Single DTN node: Ingress, Storage, Egress. Queries Router for link state.

@export var node_id: int = 0

var _storage: Dictionary = {}  # dest -> Array
var _egress_queue: Array = []
var _in_flight: Array = []  # { "bundle": DtnBundle, "remaining_bits": int, "dest": int }
var _delivered_count: int = 0
var _ingress_count: int = 0  # total bundles received (including delivered)
var _egress_sent_count: int = 0
var _storage_dropped_count: int = 0  # dropped due to storage full

var router: DtnRouter
var max_storage_bytes: int = 1048576  # HDTN storage capacity
var sim_time_ms: int = 0
var transmission_algorithm_id: int = TransmissionAlgorithms.Algorithm.FIFO
var _rng: RandomNumberGenerator

# Link state cache (as source): dest -> bool
var _link_up: Dictionary = {}
var _link_order_round_robin: int = 0
var _dest_round_robin: int = 0


func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	_update_ui()


func set_router(r: DtnRouter) -> void:
	router = r
	if r:
		max_storage_bytes = r.storage_capacity_bytes


func set_sim_time(ms: int) -> void:
	var prev_ms := sim_time_ms
	sim_time_ms = ms
	if router:
		_update_link_state()
		for dest in _storage.keys():
			if _link_up.get(dest, false):
				var list: Array = _storage[dest]
				var ordered := TransmissionAlgorithms.order_storage_to_egress(list, transmission_algorithm_id)
				for b in ordered:
					_egress_queue.append(b)
				_storage.erase(dest)
	_update_ui()


func _update_link_state() -> void:
	if not router:
		return
	_link_up.clear()
	for c in router.get_all_contacts():
		if c["source"] == node_id:
			var up: bool = sim_time_ms >= c["startTime"] and sim_time_ms < c["endTime"]
			_link_up[c["dest"]] = up


func receive_bundle(bundle: DtnBundle) -> void:
	_ingress_count += 1
	if bundle.dest == node_id:
		_delivered_count += 1
		_update_ui()
		return
	var link_available := _link_up.get(bundle.dest, false)
	if link_available:
		_egress_queue.append(bundle)
	else:
		var bundle_bytes := (bundle.size_bits + 7) / 8
		var used := get_storage_used_bytes()
		if used + bundle_bytes > max_storage_bytes:
			var drop := TransmissionAlgorithms.choose_drop_from_storage(_storage, bundle, used, max_storage_bytes, bundle_bytes, transmission_algorithm_id, _rng)
			if drop == "reject":
				_storage_dropped_count += 1
				_update_ui()
				return
			if drop is Array and drop.size() >= 2:
				var dkey = drop[0]
				var idx: int = drop[1]
				if _storage.has(dkey) and _storage[dkey].size() > idx:
					_storage[dkey].remove_at(idx)
					_storage_dropped_count += 1
			# If we dropped something, retry space (might need to drop more for RED/FairShare)
			while get_storage_used_bytes() + bundle_bytes > max_storage_bytes:
				used = get_storage_used_bytes()
				drop = TransmissionAlgorithms.choose_drop_from_storage(_storage, bundle, used, max_storage_bytes, bundle_bytes, transmission_algorithm_id, _rng)
				if drop == "reject":
					_storage_dropped_count += 1
					_update_ui()
					return
				if drop is Array and drop.size() >= 2:
					var dkey = drop[0]
					var i: int = drop[1]
					if _storage.has(dkey) and _storage[dkey].size() > i:
						_storage[dkey].remove_at(i)
						_storage_dropped_count += 1
		if not _storage.has(bundle.dest):
			_storage[bundle.dest] = []
		_storage[bundle.dest].append(bundle)
	_update_ui()


## Called by SimController each frame. Returns completed transfers: [[dest_id, DtnBundle], ...]
func step_egress(delta: float) -> Array:
	if not router:
		return []
	var completed: Array = []
	var link_dests: Array = []
	for d in _link_up.keys():
		if _link_up[d]:
			link_dests.append(d)
	var ordered_dests := TransmissionAlgorithms.order_links_for_egress(link_dests, router, node_id, sim_time_ms, transmission_algorithm_id, _rng)
	if ordered_dests.is_empty():
		ordered_dests = link_dests
	# Round-robin link: rotate start index
	if transmission_algorithm_id == TransmissionAlgorithms.Algorithm.ROUND_ROBIN_LINK and ordered_dests.size() > 0:
		_link_order_round_robin = _link_order_round_robin % ordered_dests.size()
		var rot: Array = []
		for i in range(ordered_dests.size()):
			rot.append(ordered_dests[(i + _link_order_round_robin) % ordered_dests.size()])
		ordered_dests = rot
	# 1) Dequeue from egress_queue into in_flight (rate limited per dest)
	for dest in ordered_dests:
		var rate := router.get_rate_bits_per_sec(node_id, dest)
		var bits_this_step := int(rate * delta)
		while bits_this_step > 0 and _egress_queue.size() > 0:
			var idx := TransmissionAlgorithms.pick_bundle_index_for_dest(_egress_queue, dest, transmission_algorithm_id, _rng)
			if idx < 0:
				break
			var bundle: DtnBundle = _egress_queue[idx]
			_egress_queue.remove_at(idx)
			if bits_this_step >= bundle.size_bits:
				bits_this_step -= bundle.size_bits
				_egress_sent_count += 1
				completed.append([dest, bundle])
			else:
				_in_flight.append({
					"bundle": bundle,
					"remaining_bits": bundle.size_bits - bits_this_step,
					"dest": dest
				})
				bits_this_step = 0
				break
	if transmission_algorithm_id == TransmissionAlgorithms.Algorithm.ROUND_ROBIN_LINK and ordered_dests.size() > 0:
		_link_order_round_robin += 1
	# 2) Advance in_flight by rate*delta per dest
	var still_flying: Array = []
	for entry in _in_flight:
		var dest_id: int = entry["dest"]
		var rate := router.get_rate_bits_per_sec(node_id, dest_id)
		var bits := int(rate * delta)
		entry["remaining_bits"] -= bits
		if entry["remaining_bits"] <= 0:
			_egress_sent_count += 1
			completed.append([dest_id, entry["bundle"]])
		else:
			still_flying.append(entry)
	_in_flight = still_flying
	_update_ui()
	return completed


func get_storage_count() -> int:
	var n := 0
	for list in _storage.values():
		n += list.size()
	return n


func get_storage_used_bytes() -> int:
	var total := 0
	for list in _storage.values():
		for b in list:
			total += (b.size_bits + 7) / 8
	return total


func get_ingress_count() -> int:
	return _ingress_count


func get_egress_sent_count() -> int:
	return _egress_sent_count


func get_storage_dropped_count() -> int:
	return _storage_dropped_count


func get_egress_queue_count() -> int:
	return _egress_queue.size()


func get_in_flight_count() -> int:
	return _in_flight.size()


func get_delivered_count() -> int:
	return _delivered_count


func _update_ui() -> void:
	if has_node("Label"):
		$Label.text = "Node %d" % node_id
	if has_node("StatsLabel"):
		$StatsLabel.text = "S:%d E:%d F:%d D:%d" % [get_storage_count(), get_egress_queue_count(), get_in_flight_count(), get_delivered_count()]
	if has_node("StorageBar"):
		var pct := 0.0
		if max_storage_bytes > 0:
			pct = clampf(float(get_storage_used_bytes()) / float(max_storage_bytes), 0.0, 1.0)
		$StorageBar.value = pct * 100.0
