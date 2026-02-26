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

# Link state cache (as source): dest -> bool
var _link_up: Dictionary = {}


func _ready() -> void:
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
				while list.size() > 0:
					_egress_queue.append(list.pop_back())
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
		if get_storage_used_bytes() + bundle_bytes > max_storage_bytes:
			_storage_dropped_count += 1
			_update_ui()
			return
		if not _storage.has(bundle.dest):
			_storage[bundle.dest] = []
		_storage[bundle.dest].append(bundle)
	_update_ui()


## Called by SimController each frame. Returns completed transfers: [[dest_id, DtnBundle], ...]
func step_egress(delta: float) -> Array:
	if not router:
		return []
	var completed: Array = []
	# 1) Dequeue from egress_queue into in_flight (rate limited per dest)
	for dest in _link_up.keys():
		if not _link_up[dest]:
			continue
		var rate := router.get_rate_bits_per_sec(node_id, dest)
		var bits_this_step := int(rate * delta)
		while bits_this_step > 0 and _egress_queue.size() > 0:
			var idx := -1
			for i in range(_egress_queue.size()):
				if _egress_queue[i].dest == dest:
					idx = i
					break
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
