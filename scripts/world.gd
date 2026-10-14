class_name GameWorld
extends Node2D

## 2D 自由地图背景：绿色草地 + 边界框。占位美术。

var world_size: Vector2 = Vector2(2400.0, 1600.0)

func setup(world_w: float, world_h: float) -> void:
	world_size = Vector2(world_w, world_h)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, world_size), Color(0.24, 0.46, 0.20))
	draw_rect(Rect2(0.0, 0.0, world_size.x, 24.0), Color(0.22, 0.44, 0.18))
	draw_rect(Rect2(Vector2.ZERO, world_size), Color(0.05, 0.08, 0.05), false, 8.0)
