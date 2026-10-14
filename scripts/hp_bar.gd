class_name HpBar
extends Node2D

## 通用头顶血条：附加到有生命的实体（建筑/小兵/玩家/AI/野怪）。
## - 默认受伤后显示几秒自动隐藏；大本营 always_show 常显。
## - 建造/升级中显示建造进度条（读表，含剩余秒数）。

var max_hp: float = 1.0
var cur_hp: float = 1.0
var build_max: float = 0.0
var build_cur: float = 0.0
var always_show: bool = false
var offset_y: float = -18.0
var bar_width: float = 36.0
var bar_height: float = 5.0
var show_timer: float = 0.0

func _process(delta: float) -> void:
	if always_show:
		visible = true
		return
	if build_max > 0.0 and build_cur >= 0.0 and build_cur < build_max:
		visible = true
		return
	if show_timer > 0.0:
		show_timer -= delta
		visible = true
		return
	visible = false

func set_hp(cur: float, max: float, show: bool = true) -> void:
	cur_hp = cur
	max_hp = max if max > 0.0 else 1.0
	if show:
		show_timer = 4.0
		visible = true  # 受击/复活立即显示，避免一帧延迟
	queue_redraw()

func set_progress(cur: float, max: float) -> void:
	build_cur = cur
	build_max = max
	queue_redraw()

func _draw() -> void:
	# 建造/升级进度条（蓝色读条 + 剩余秒数）
	if build_max > 0.0 and build_cur >= 0.0 and build_cur < build_max:
		var frac: float = clampf(build_cur / build_max, 0.0, 1.0)
		var yp: float = offset_y - bar_height - 2.0
		draw_rect(Rect2(-bar_width * 0.5, yp, bar_width, bar_height), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(-bar_width * 0.5, yp, bar_width * frac, bar_height), Color(0.35, 0.75, 1.0, 0.9))
		var remain: float = maxf(build_max - build_cur, 0.0)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(-bar_width * 0.5, yp - 4.0), "%d" % int(ceil(remain)), HORIZONTAL_ALIGNMENT_LEFT, bar_width, 12, Color(1, 1, 1, 0.9))
	# 血量条（大本营常显；其余受伤后显示 3 秒自动隐藏）
	if always_show or show_timer > 0.0:
		var frac2: float = clampf(cur_hp / max_hp, 0.0, 1.0)
		draw_rect(Rect2(-bar_width * 0.5, offset_y, bar_width, bar_height), Color(0, 0, 0, 0.6))
		var col: Color = Color(0.3, 0.9, 0.35) if frac2 > 0.35 else Color(0.95, 0.35, 0.3)
		draw_rect(Rect2(-bar_width * 0.5, offset_y, bar_width * frac2, bar_height), col)
