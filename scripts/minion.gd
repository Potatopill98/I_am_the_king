class_name Minion
extends CharacterBody2D

## 小兵：低阶剑士/弓手 + 高阶骑兵。驻守（围兵营）或跟随（跟主角）两种模式。
## 有敌人就打敌人；没敌人时：跟随→走向主角，驻守→在兵营附近游走。
## 8 分钟后伤害递增（game.escalate_multiplier）。

var game: GameManager
var team: int = 0
var unit_type: String = "swordman"
var source_barracks: Building = null

var hp: float = 12.0
var max_hp: float = 12.0
var damage: float = 2.0
var move_speed: float = 220.0
var is_melee: bool = true
var attack_range: float = 30.0
var attack_interval: float = 1.0
var attack_timer: float = 0.0

var mode: int = 0  # 0 驻守 1 跟随
var enemy_target: Node2D = null
var wander_timer: float = 0.0
var wander_offset: Vector2 = Vector2.ZERO
var hpbar: HpBar = null
var knockback: Vector2 = Vector2.ZERO
var agro_range: float = 240.0  # 警戒范围：敌方单位/建筑进入此范围才索敌
var agro_range_wild: float = 160.0  # 对中立野怪的警戒范围（更小，不追太远）
var ring_r: float = 80.0  # 跟随主角时的环绕半径
var ring_dir: Vector2 = Vector2.RIGHT

func setup(g: GameManager, t: int, pos: Vector2, type: String, src: Building) -> void:
	game = g
	team = t
	unit_type = type
	source_barracks = src
	global_position = pos
	_apply_stats()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(22.0, 22.0)
	shape.shape = rect
	add_child(shape)
	# 碰撞层：同队不碰撞，敌我互撞；我方兵不撞自己墙，挡敌方墙；野怪/大本营互撞
	if team == 0:
		collision_layer = 2
		collision_mask = 85
	else:
		collision_layer = 4
		collision_mask = 51
	ring_r = randf_range(60.0, 100.0)
	ring_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	add_to_group("minion")
	add_to_group("team0" if team == 0 else "team1")
	var bar: HpBar = HpBar.new()
	bar.offset_y = -16.0
	bar.bar_width = 30.0
	bar.always_show = (team == 1)  # 敌方小兵血条常显，方便玩家看清
	bar.set_hp(hp, max_hp, false)
	add_child(bar)
	hpbar = bar

func _apply_stats() -> void:
	if unit_type == "archer":
		hp = 8.0
		max_hp = 8.0
		damage = 2.0
		move_speed = 200.0
		is_melee = false
		attack_range = 180.0
		attack_interval = 1.2
	elif unit_type == "cavalry":
		hp = 25.0
		max_hp = 25.0
		damage = 4.0
		move_speed = 320.0
		is_melee = true
		attack_range = 32.0
		attack_interval = 0.8
	else:
		hp = 12.0
		max_hp = 12.0
		damage = 2.0
		move_speed = 220.0
		is_melee = true
		attack_range = 30.0
		attack_interval = 1.0

func _draw() -> void:
	var col: Color = Color(0.2, 0.72, 0.8) if team == 0 else Color(0.92, 0.46, 0.24)
	if unit_type == "cavalry":
		col = Color(0.15, 0.5, 0.6) if team == 0 else Color(0.85, 0.35, 0.18)
	draw_rect(Rect2(-11.0, -11.0, 22.0, 22.0), col)

func _physics_process(delta: float) -> void:
	if game == null or game.game_over:
		return
	attack_timer = maxf(attack_timer - delta, 0.0)
	var enemy: Node2D = _find_enemy()
	if enemy != null:
		enemy_target = enemy
		_combat(delta, enemy)
	elif not _gather_help(delta):
		enemy_target = null
		_move_to_goal(delta)
	if knockback.length() > 0.5:
		global_position += knockback * delta
		knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)

func _apply_knockback(dir: Vector2, strength: float) -> void:
	knockback = dir.normalized() * strength

func _combat(delta: float, enemy: Node2D) -> void:
	# 建筑体型大：近战够到建筑边缘即可攻击（避免被大本营碰撞卡住打不到）
	var reach: float = attack_range
	if enemy is Building:
		reach += (enemy as Building).block_radius()
	var dist: float = global_position.distance_to(enemy.global_position)
	if dist <= reach:
		velocity = Vector2.ZERO
		if attack_timer <= 0.0:
			attack_timer = attack_interval
			if enemy.has_method("take_damage"):
				enemy.call("take_damage", damage * game.escalate_multiplier, team)
				# 近战兵轻微击退，远程(弓手)更轻
				if enemy.has_method("_apply_knockback"):
					var kb: float = 140.0 if is_melee else 60.0
					enemy.call("_apply_knockback", (enemy.global_position - global_position).normalized(), kb)
	else:
		var to: Vector2 = (enemy.global_position - global_position).normalized()
		velocity = to * move_speed
	move_and_slide()

## 帮打资源：玩家主动在砍的资源（game.active_gather），小兵在 300 内会来帮忙打。
## 返回 true 表示正在帮打（占用本帧）。
func _gather_help(delta: float) -> bool:
	var res: ResourceNode = null
	if game != null and game.active_gather != null and is_instance_valid(game.active_gather):
		res = game.active_gather
	if res == null:
		return false
	if global_position.distance_to(res.global_position) > 300.0:
		return false
	var dist: float = global_position.distance_to(res.global_position)
	if dist <= attack_range:
		velocity = Vector2.ZERO
		if attack_timer <= 0.0:
			attack_timer = attack_interval
			res.take_damage(damage * game.escalate_multiplier, team)
	else:
		var to: Vector2 = (res.global_position - global_position).normalized()
		velocity = to * move_speed
	move_and_slide()
	return true

func _move_to_goal(delta: float) -> void:
	if mode == 1:
		_follow_hero()
		return
	# 驻守：在兵营附近游走
	if source_barracks != null and is_instance_valid(source_barracks):
		_update_wander(delta)
		_move_toward(source_barracks.global_position + wander_offset)
	else:
		velocity = Vector2.ZERO
		move_and_slide()

func _follow_hero() -> void:
	var hero: Node2D = game.player if team == 0 else game.ai_hero
	if not is_instance_valid(hero):
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# 环绕目标：主角 + 自己分配的环半径/方向，保持一定距离不贴脸
	var target: Vector2 = hero.global_position + ring_dir * ring_r
	_move_toward(target, move_speed * 0.9)

func _move_toward(goal: Vector2, spd: float = -1.0) -> void:
	var to: Vector2 = goal - global_position
	if to.length() > 8.0:
		velocity = to.normalized() * (spd if spd > 0.0 else move_speed)
	else:
		velocity = Vector2.ZERO
	move_and_slide()

func _update_wander(delta: float) -> void:
	wander_timer += delta
	if wander_timer > 2.0:
		wander_timer = 0.0
		wander_offset = Vector2(randf_range(-70.0, 70.0), randf_range(-70.0, 70.0))

func _find_enemy() -> Node2D:
	var enemy_name: String = "team%d" % (1 - team)
	var best: Node2D = null
	var best_dist: float = agro_range
	for node in get_tree().get_nodes_in_group(enemy_name):
		if not node.has_method("take_damage"):
			continue
		if node is Building:
			var b: Building = node as Building
			if not is_melee and b.btype == GameManager.TYPE_WALL:
				continue  # 远程越过围墙
		var d: float = global_position.distance_to(node.global_position)
		if d <= best_dist:
			best_dist = d
			best = node as Node2D
	# 中立野怪：对所有阵营敌对，用更小的警戒范围（160）
	for node in get_tree().get_nodes_in_group("wild"):
		if not node.has_method("take_damage"):
			continue
		var dw: float = global_position.distance_to(node.global_position)
		if dw <= agro_range_wild and dw < best_dist:
			best_dist = dw
			best = node as Node2D
	return best

func take_damage(amount: float, attacker_team: int) -> void:
	hp -= amount
	if hpbar != null:
		hpbar.set_hp(hp, max_hp)
	if hp <= 0.0:
		queue_free()

func convert_to_cavalry() -> void:
	if unit_type == "cavalry":
		return
	unit_type = "cavalry"
	_apply_stats()
	if hpbar != null:
		hpbar.set_hp(hp, max_hp)
	queue_redraw()
