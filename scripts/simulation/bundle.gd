class_name DtnBundle
extends RefCounted

## Logical bundle: source, destination, size, creation time. No BP encoding.

var source: int
var dest: int
var size_bits: int
var created_at_ms: int
var bundle_id: int

static var _next_id: int = 0


func _init(p_source: int, p_dest: int, p_size_bits: int, p_created_at_ms: int) -> void:
	source = p_source
	dest = p_dest
	size_bits = p_size_bits
	created_at_ms = p_created_at_ms
	bundle_id = _next_id
	_next_id += 1
