extends CharacterBody2D
class_name PacketBody

## Physics-driven packet: moves from source toward destination at constant speed.
## When it reaches the destination, emits arrived(dest_node_id, bundle).

signal arrived(dest_node_id: int, bundle: DtnBundle)

var dest_node_id: int = 0
var bundle: DtnBundle
var _target: Vector2
var _speed: float = 100.0
var _arrived: bool = false


func setup(p_start: Vector2, p_target: Vector2, p_bundle: DtnBundle, p_dest_node_id: int, p_speed: float) -> void:
	position = p_start
	_target = p_target
	bundle = p_bundle
	dest_node_id = p_dest_node_id
	_speed = p_speed
	_arrived = false
	# Point toward target
	var d := _target - position
	if d.length() > 0.1:
		velocity = d.normalized() * _speed
	else:
		velocity = Vector2.ZERO
		_arrive()


func _physics_process(delta: float) -> void:
	if _arrived:
		return
	var d := _target - position
	var dist := d.length()
	if dist <= _speed * delta + 8.0:
		_arrive()
		return
	velocity = d.normalized() * _speed
	move_and_slide()


func _arrive() -> void:
	if _arrived:
		return
	_arrived = true
	arrived.emit(dest_node_id, bundle)
