class_name WildMonster
extends CharacterBody2D

## 中立野怪：弱怪（木/石武器，掉木石）、强怪（铁锤盾，掉铁）。
## 每只野怪以栖息地(center)为中心有一个可见的虚线警戒区域：
## - 玩家/AI/小兵走进该区域 → 野怪被激怒并追击；
## - 追击中若目标走出该区域 → 野怪放弃，自动返回栖息地；
## - 速度始终慢于玩家，方便走位。

var game: GameManager
var is_strong: bool = false
var hp: float = 6.0
var max_hp: float = 6.0
var damage: float = 1.0
var move_speed: float = 130.0
var attack_range: float = 42.0
var attack_interval: float = 1.0
var attack_timer: float = 0.0

var center: Vector2 = Vector2.ZERO
var roam_radius: float = 120.0
var zone_radius: float = 170.0
var aggro_target: Node2D = null
var hpbar: HpBar = null
var knockback: Vector2 = Vector2.ZERO

func setup(g: GameManager, strong: bool, pos: Vector2, area_center: Vector2) -> void:
	game = g
	is_strong = strong
	global_position = pos
	center = area_center
	if strong:
		hp = 45.0
		max_hp = 45.0
		damage = 3.0
		move_speed = 160.0
	else:
		hp = 9.0
		max_hp = 9.0
		damage = 1.0
		move_speed = 130.0
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(26.0, 26.0)
	shape.shape = rect
	add_child(shape)
	# 野怪：撞建筑(1)+双方单位(2,4)，不撞资源
	collision_layer = 16
	collision_mask = 7
	add_to_group("wild")
	var bar: HpBar = HpBar.new()
	bar.offset_y = -18.0
	bar.bar_width = 34.0
	bar.set_hp(hp, max_hp, false)
	add_child(bar)
	hpbar = bar

func _draw() -> void:
	var col: Color = Color(0.5, 0.4, 0.3) if not is_strong else Color(0.55, 0.35, 0.35)
	draw_circle(Vector2.ZERO, 12.0, col)
	draw_circle(Vector2(3.0, -3.0), 4.0, Color(0.1, 0.1, 0.1))
	# 警戒区域：固定在世界坐标的栖息地周围，虚线显示，可被玩家看见
	var zcol: Color = Color(0.6, 0.9, 0.35, 0.5) if not is_strong else Color(0.95, 0.5, 0.25, 0.55)
	_draw_dashed_circle(center - global_position, zone_radius, zcol, 2.0, 0.18, 0.14)
	# 头顶标「怪」
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(-20.0, -18.0), "怪", HORIZONTAL_ALIGNMENT_CENTER, 40.0, 14.0, Color(1.0, 0.95, 0.85))

func _draw_dashed_circle(pos: Vector2, r: float, col: Color, width: float, dash: float, gap: float) -> void:
	var a: float = 0.0
	while a < TAU:
		var a1: float = minf(a + dash, TAU)
		var p0: Vector2 = pos + Vector2(cos(a), sin(a)) * r
		var p1: Vector2 = pos + Vector2(cos(a1), sin(a1)) * r
		draw_line(p0, p1, col, width)
		a += dash + gap

func _physics_process(delta: float) -> void:
	if game == null or game.game_over:
		return
	queue_redraw()  # 虚线圈跟随栖息地，怪物移动时刷新
	attack_timer = maxf(attack_timer - delta, 0.0)
	if aggro_target == null or not is_instance_valid(aggro_target):
		aggro_target = _find_aggro()
	if aggro_target != null:
		# 目标已走出警戒区域 → 放弃追击，回栖息地
		if aggro_target.global_position.distance_to(center) > zone_radius:
			aggro_target = null
		else:
			var dist: float = global_position.distance_to(aggro_target.global_position)
			if dist <= attack_range:
				velocity = Vector2.ZERO
				if attack_timer <= 0.0:
					attack_timer = attack_interval
					if aggro_target.has_method("take_damage"):
						aggro_target.call("take_damage", damage, 2)
						if aggro_target.has_method("_apply_knockback"):
							aggro_target.call("_apply_knockback", (aggro_target.global_position - global_position).normalized(), 140.0)
			else:
				var to: Vector2 = (aggro_target.global_position - global_position).normalized()
				velocity = to * move_speed
	else:
		_roam(delta)
	move_and_slide()
	if knockback.length() > 0.5:
		global_position += knockback * delta
		knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)

func _apply_knockback(dir: Vector2, strength: float) -> void:
	knockback = dir.normalized() * strength

func _roam(delta: float) -> void:
	if global_position.distance_to(center) > roam_radius:
		var to: Vector2 = (center - global_position).normalized()
		velocity = to * move_speed
		return
	velocity = Vector2.ZERO

func _find_aggro() -> Node2D:
	var best: Node2D = null
	var best_dist: float = zone_radius
	for node in get_tree().get_nodes_in_group("team0"):
		if node.has_method("take_damage"):
			var d: float = node.global_position.distance_to(center)
			if d <= best_dist:
				best_dist = d
				best = node as Node2D
	for node in get_tree().get_nodes_in_group("team1"):
		if node.has_method("take_damage"):
			var d: float = node.global_position.distance_to(center)
			if d <= best_dist:
				best_dist = d
				best = node as Node2D
	return best

func take_damage(amount: float, attacker_team: int) -> void:
	hp -= amount
	aggro_target = null
	if hp <= 0.0:
		_drop()
		queue_free()

func _drop() -> void:
	var type: int = 0
	var amt: int = 1
	if is_strong:
		type = 2
		amt = 1
	else:
		if randf() < 0.5:
			type = 0
		else:
			type = 1
	game.spawn_drop(type, amt, global_position)
