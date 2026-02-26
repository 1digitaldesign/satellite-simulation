extends Node2D
class_name BundleVisual

## Visual representation of a bundle in flight or in queue.

var bundle: DtnBundle
var progress: float = 0.0  # 0 = at source, 1 = at dest (for lerp along link)


func _draw() -> void:
	draw_circle(Vector2.ZERO, 4.0, Color(0.3, 0.9, 0.4))


func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()
