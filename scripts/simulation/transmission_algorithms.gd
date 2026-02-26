extends RefCounted
class_name TransmissionAlgorithms

## Registry and behavior for 30 transmission algorithms (scheduling, routing, drop policy).
## Used by DtnNode for physics-based packet transfer simulation.

enum Algorithm {
	# 1–10: Queue scheduling (which bundle to send next)
	FIFO,
	LIFO,
	PRIORITY_DEST,
	SHORTEST_JOB_FIRST,
	LONGEST_JOB_FIRST,
	ROUND_ROBIN_DEST,
	EARLIEST_DEADLINE_FIRST,
	LARGEST_BUNDLE_FIRST,
	SMALLEST_BUNDLE_FIRST,
	WEIGHTED_FAIR_QUEUING,
	# 11–18: Routing / link selection (which link to use when multiple up)
	CONTACT_PLAN_ONLY,
	EARLIEST_CONTACT,
	LONGEST_CONTACT,
	MAX_RATE,
	RANDOM_LINK,
	ROUND_ROBIN_LINK,
	MIN_DELAY,
	SHORTEST_PATH_HOPS,
	# 19–22: Retransmission (ARQ)
	NO_ARQ,
	GO_BACK_N,
	SELECTIVE_REPEAT,
	STOP_AND_WAIT,
	# 23–30: Drop / congestion policy (when storage full)
	DROP_NEW,
	DROP_OLDEST,
	DROP_NEWEST,
	RANDOM_DROP,
	RED_LIKE,
	PRIORITY_DROP_LOW,
	FAIR_SHARE_DROP,
	DROP_TAIL,
}

const ALGORITHM_COUNT: int = 30

static var _names: Array = []


static func _static_init() -> void:
	if _names.size() > 0:
		return
	_names = [
		"1.FIFO",
		"2.LIFO",
		"3.Priority (dest)",
		"4.Shortest Job First",
		"5.Longest Job First",
		"6.Round Robin (dest)",
		"7.Earliest Deadline First",
		"8.Largest Bundle First",
		"9.Smallest Bundle First",
		"10.Weighted Fair Queuing",
		"11.Contact Plan Only",
		"12.Earliest Contact",
		"13.Longest Contact",
		"14.Max Rate",
		"15.Random Link",
		"16.Round Robin Link",
		"17.Min Delay",
		"18.Shortest Path (hops)",
		"19.No ARQ",
		"20.Go-Back-N",
		"21.Selective Repeat",
		"22.Stop-and-Wait",
		"23.Drop New",
		"24.Drop Oldest",
		"25.Drop Newest",
		"26.Random Drop",
		"27.RED-like",
		"28.Priority Drop (low)",
		"29.Fair Share Drop",
		"30.Drop Tail",
	]


static func get_algorithm_name(id: int) -> String:
	_static_init()
	if id >= 0 and id < _names.size():
		return _names[id]
	return "Unknown"


static func get_all_names() -> Array:
	_static_init()
	var out: Array = []
	for i in range(_names.size()):
		out.append(_names[i])
	return out


## Returns index into egress_queue of the bundle to send next for this dest, or -1.
static func pick_bundle_index_for_dest(egress_queue: Array, dest: int, algorithm_id: int, _rng: RandomNumberGenerator) -> int:
	var candidates: Array = []
	for i in range(egress_queue.size()):
		if egress_queue[i].dest == dest:
			candidates.append({"i": i, "b": egress_queue[i]})
	if candidates.is_empty():
		return -1
	if candidates.size() == 1:
		return candidates[0]["i"]
	# Sort by algorithm
	match algorithm_id:
		Algorithm.FIFO:
			return candidates[0]["i"]
		Algorithm.LIFO:
			return candidates[candidates.size() - 1]["i"]
		Algorithm.PRIORITY_DEST:
			candidates.sort_custom(func(a, b): return a["b"].dest < b["b"].dest)
			return candidates[0]["i"]
		Algorithm.SHORTEST_JOB_FIRST:
			candidates.sort_custom(func(a, b): return a["b"].size_bits < b["b"].size_bits)
			return candidates[0]["i"]
		Algorithm.LONGEST_JOB_FIRST:
			candidates.sort_custom(func(a, b): return a["b"].size_bits > b["b"].size_bits)
			return candidates[0]["i"]
		Algorithm.EARLIEST_DEADLINE_FIRST:
			candidates.sort_custom(func(a, b): return a["b"].created_at_ms < b["b"].created_at_ms)
			return candidates[0]["i"]
		Algorithm.LARGEST_BUNDLE_FIRST:
			candidates.sort_custom(func(a, b): return a["b"].size_bits > b["b"].size_bits)
			return candidates[0]["i"]
		Algorithm.SMALLEST_BUNDLE_FIRST:
			candidates.sort_custom(func(a, b): return a["b"].size_bits < b["b"].size_bits)
			return candidates[0]["i"]
		Algorithm.ROUND_ROBIN_DEST, Algorithm.WEIGHTED_FAIR_QUEUING:
			return candidates[0]["i"]
		_:
			return candidates[0]["i"]


## Returns ordered list of destination node IDs to serve (which link to drain first).
static func order_links_for_egress(link_up_dests: Array, router: DtnRouter, source_node_id: int, sim_time_ms: int, algorithm_id: int, _rng: RandomNumberGenerator) -> Array:
	if link_up_dests.is_empty():
		return []
	var dests: Array = link_up_dests.duplicate()
	match algorithm_id:
		Algorithm.CONTACT_PLAN_ONLY, Algorithm.NO_ARQ, Algorithm.GO_BACK_N, Algorithm.SELECTIVE_REPEAT, Algorithm.STOP_AND_WAIT:
			return dests
		Algorithm.EARLIEST_CONTACT:
			dests.sort_custom(func(a, b) -> bool:
				var ca := router.get_contact_for_link(source_node_id, a)
				var cb := router.get_contact_for_link(source_node_id, b)
				return ca.get("startTime", 0) < cb.get("startTime", 0)
			)
			return dests
		Algorithm.LONGEST_CONTACT:
			dests.sort_custom(func(a, b) -> bool:
				var ca := router.get_contact_for_link(source_node_id, a)
				var cb := router.get_contact_for_link(source_node_id, b)
				var rem_a := ca.get("endTime", 0) - sim_time_ms
				var rem_b := cb.get("endTime", 0) - sim_time_ms
				return rem_a > rem_b
			)
			return dests
		Algorithm.MAX_RATE:
			dests.sort_custom(func(a, b) -> bool:
				var ra := router.get_rate_bits_per_sec(source_node_id, a)
				var rb := router.get_rate_bits_per_sec(source_node_id, b)
				return ra > rb
			)
			return dests
		Algorithm.MIN_DELAY:
			dests.sort_custom(func(a, b) -> bool:
				var ca := router.get_contact_for_link(source_node_id, a)
				var cb := router.get_contact_for_link(source_node_id, b)
				return ca.get("startTime", 0) < cb.get("startTime", 0)
			)
			return dests
		Algorithm.RANDOM_LINK:
			for i in range(dests.size() - 1, 0, -1):
				var j := _rng.randi() % (i + 1)
				var t := dests[i]
				dests[i] = dests[j]
				dests[j] = t
			return dests
		Algorithm.ROUND_ROBIN_LINK:
			pass
		Algorithm.SHORTEST_PATH_HOPS:
			pass
		_:
			pass
	return dests


## When storage would exceed capacity: return [dest_key, list_index] to drop, or null to drop/reject the new bundle.
static func choose_drop_from_storage(storage: Dictionary, new_bundle: DtnBundle, used_bytes: int, max_bytes: int, new_bundle_bytes: int, algorithm_id: int, _rng: RandomNumberGenerator) -> Variant:
	if used_bytes + new_bundle_bytes <= max_bytes:
		return null
	match algorithm_id:
		Algorithm.DROP_NEW, Algorithm.DROP_TAIL, Algorithm.NO_ARQ, Algorithm.GO_BACK_N, Algorithm.SELECTIVE_REPEAT, Algorithm.STOP_AND_WAIT:
			return "reject"
		Algorithm.DROP_OLDEST:
			var oldest_key: int = -1
			var oldest_idx: int = 0
			var oldest_time: int = 0x7FFFFFFF
			for k in storage.keys():
				var list: Array = storage[k]
				for i in range(list.size()):
					if list[i].created_at_ms < oldest_time:
						oldest_time = list[i].created_at_ms
						oldest_key = k
						oldest_idx = i
			if oldest_key >= 0:
				return [oldest_key, oldest_idx]
			return "reject"
		Algorithm.DROP_NEWEST:
			var newest_key: int = -1
			var newest_time: int = -1
			for k in storage.keys():
				var list: Array = storage[k]
				for i in range(list.size()):
					if list[i].created_at_ms > newest_time:
						newest_time = list[i].created_at_ms
						newest_key = k
			if newest_key >= 0:
				var list: Array = storage[newest_key]
				for i in range(list.size()):
					if list[i].created_at_ms == newest_time:
						return [newest_key, i]
			return "reject"
		Algorithm.RANDOM_DROP:
			var all: Array = []
			for k in storage.keys():
				var list: Array = storage[k]
				for i in range(list.size()):
					all.append([k, i])
			if all.is_empty():
				return "reject"
			return all[_rng.randi() % all.size()]
		Algorithm.RED_LIKE:
			var fill := float(used_bytes) / float(max_bytes)
			if _rng.randf() < fill * 0.5:
				var all: Array = []
				for k in storage.keys():
					for i in range(storage[k].size()):
						all.append([k, i])
				if all.is_empty():
					return "reject"
				return all[_rng.randi() % all.size()]
			return "reject"
		Algorithm.PRIORITY_DROP_LOW:
			var low_key: int = -1
			var low_dest: int = 0x7FFFFFFF
			for k in storage.keys():
				var list: Array = storage[k]
				if list.size() > 0 and k < low_dest:
					low_dest = k
					low_key = k
			if low_key >= 0:
				return [low_key, 0]
			return "reject"
		Algorithm.FAIR_SHARE_DROP:
			for k in storage.keys():
				var list: Array = storage[k]
				if list.size() > 0:
					return [k, list.size() - 1]
			return "reject"
		_:
			return "reject"


## Order to move bundles from storage to egress when link comes up (order to append to egress).
static func order_storage_to_egress(storage_list: Array, algorithm_id: int) -> Array:
	var lst: Array = storage_list.duplicate()
	match algorithm_id:
		Algorithm.LIFO:
			lst.reverse()
			return lst
		Algorithm.SHORTEST_JOB_FIRST:
			lst.sort_custom(func(a, b): return a.size_bits < b.size_bits)
			return lst
		Algorithm.LONGEST_JOB_FIRST:
			lst.sort_custom(func(a, b): return a.size_bits > b.size_bits)
			return lst
		Algorithm.EARLIEST_DEADLINE_FIRST, Algorithm.FIFO:
			lst.sort_custom(func(a, b): return a.created_at_ms < b.created_at_ms)
			return lst
		Algorithm.SMALLEST_BUNDLE_FIRST:
			lst.sort_custom(func(a, b): return a.size_bits < b.size_bits)
			return lst
		Algorithm.LARGEST_BUNDLE_FIRST:
			lst.sort_custom(func(a, b): return a.size_bits > b.size_bits)
			return lst
		_:
			return lst
