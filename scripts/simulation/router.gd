class_name DtnRouter
extends RefCounted

## Router: evaluates contact plan and reports link up/down per (source, dest).
## Matches NASA HDTN: if startTime <= t < endTime then link is available.

var _contacts: Array = []


func load_contact_plan(json_path: String) -> bool:
	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		push_error("Router: could not open contact plan: " + json_path)
		return false
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("Router: invalid JSON in contact plan")
		return false
	var data = json.get_data()
	if not data is Dictionary or not "contacts" in data:
		push_error("Router: contact plan must have 'contacts' array")
		return false
	_contacts.clear()
	for c in data["contacts"]:
		if c is Dictionary and "source" in c and "dest" in c and "startTime" in c and "endTime" in c:
			_contacts.append({
				"source": int(c["source"]),
				"dest": int(c["dest"]),
				"startTime": int(c["startTime"]),
				"endTime": int(c["endTime"]),
				"rateBitsPerSec": int(c.get("rateBitsPerSec", 1000000)),
				"contact": int(c.get("contact", -1))
			})
	return true


func get_link_state(source: int, dest: int, sim_time_ms: int) -> bool:
	for c in _contacts:
		if c["source"] == source and c["dest"] == dest:
			return sim_time_ms >= c["startTime"] and sim_time_ms < c["endTime"]
	return false


func get_contact_for_link(source: int, dest: int) -> Dictionary:
	for c in _contacts:
		if c["source"] == source and c["dest"] == dest:
			return c
	return {}


func get_rate_bits_per_sec(source: int, dest: int) -> int:
	var c := get_contact_for_link(source, dest)
	return int(c.get("rateBitsPerSec", 1000000))


func get_contacts_at_time(sim_time_ms: int) -> Array:
	var out: Array = []
	for c in _contacts:
		if sim_time_ms >= c["startTime"] and sim_time_ms < c["endTime"]:
			out.append(c)
	return out


func get_all_contacts() -> Array:
	return _contacts.duplicate()


func get_unique_node_ids() -> Array:
	var ids: Array = []
	for c in _contacts:
		var s: int = c["source"]
		var d: int = c["dest"]
		if ids.find(s) == -1:
			ids.append(s)
		if ids.find(d) == -1:
			ids.append(d)
	ids.sort()
	return ids
