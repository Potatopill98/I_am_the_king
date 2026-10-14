class_name BuildPreview
extends Node2D

## 建造预览：放置模式下跟随鼠标/手指，绿色=可建、红色=不可建。
## 同时绘制玩家身边的放置范围圈（虚线）。

var color: Color = Color(0.3, 0.9, 0.3, 0.4)
var build_type: String = ""
var half_size: float = 26.0
var game: GameManager = null

func setup(g: GameManager) -> void:
	game = g

func set_build_type(type: String) -> void:
	build_type = type
	match type:
		GameManager.TYPE_BASE: half_size = 35.0
		GameManager.TYPE_WALL: half_size = 16.0
		GameManager.TYPE_TOWER: half_size = 20.0
		GameManager.TYPE_BARRACKS: half_size = 23.0
		_: half_size = 26.0
	queue_redraw()

func _draw() -> void:
	# 建筑虚影
	draw_rect(Rect2(-half_size, -half_size, half_size * 2.0, half_size * 2.0), color)
	draw_rect(Rect2(-half_size, -half_size, half_size * 2.0, half_size * 2.0), Color(0, 0, 0, 0.5), false, 2.0)
	# 放置范围圈（以玩家为中心，虚线）
	if game != null and is_instance_valid(game.player):
		var center: Vector2 = game.player.global_position - global_position
		_draw_dashed_circle(center, GameManager.PLACE_RANGE, Color(0.4, 0.9, 0.5, 0.35), 2.0, 0.22, 0.18)

func _draw_dashed_circle(pos: Vector2, r: float, col: Color, width: float, dash: float, gap: float) -> void:
	var a: float = 0.0
	while a < TAU:
		var a1: float = minf(a + dash, TAU)
		var p0: Vector2 = pos + Vector2(cos(a), sin(a)) * r
		var p1: Vector2 = pos + Vector2(cos(a1), sin(a1)) * r
		draw_line(p0, p1, col, width)
		a += dash + gap

func set_color(new_color: Color) -> void:
	color = new_color
	queue_redraw()
