class_name MeleeFX
extends Node2D

## 近战挥砍特效：一条面向攻击方向的弧形，快速淡出（让攻击看得见）。

var life: float = 0.16
var total: float = 0.16
var dir: Vector2 = Vector2.RIGHT

func setup(direction: Vector2) -> void:
	dir = direction.normalized()

func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
	queue_redraw()

func _draw() -> void:
	if life <= 0.0:
		return
	var t: float = clampf(life / total, 0.0, 1.0)
	var angle: float = dir.angle()
	draw_arc(Vector2.ZERO, 34.0, angle - 1.0, angle + 1.0, 18, Color(1.0, 0.92, 0.55, t), 5.0)
	draw_arc(Vector2.ZERO, 26.0, angle - 0.8, angle + 0.8, 14, Color(1.0, 0.98, 0.8, t * 0.6), 3.0)
