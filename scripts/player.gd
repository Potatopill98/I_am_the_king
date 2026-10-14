class_name Player
extends CharacterBody2D

## 玩家主角：挥剑（近战/采集）+ 弓箭（远程）。一个攻击键自动索敌，近剑远弓。

var game: GameManager
var team: int = 0
var speed: float = 300.0
var facing: Vector2 = Vector2.RIGHT
var external_move: Vector2 = Vector2.ZERO
var external_attack: bool = false
var knockback: Vector2 = Vector2.ZERO

var hp: float = 30.0
var max_hp: float = 30.0
var hpbar: HpBar = null

var sword_cooldown: float = 0.0
var sword_interval: float = 0.6
var sword_damage: float = 3.0
var sword_reach: float = 70.0

var bow_cooldown: float = 0.0
var bow_interval: float = 1.0
var bow_damage: float = 3.0
var bow_range: float = 200.0

func setup(g: GameManager, t: int, pos: Vector2) -> void:
	game = g
	team = t
	global_position = pos
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(30.0, 30.0)
	shape.shape = rect
	add_child(shape)
	# 碰撞层：阵营0(2)；mask=大本营(1)+敌方单位(4)+野怪(16)+敌方墙(64)，不撞自己墙/资源/自己人
	collision_layer = 2
	collision_mask = 85
	add_to_group("hero")
	add_to_group("team0")
	var bar: HpBar = HpBar.new()
	bar.offset_y = -18.0
	bar.bar_width = 40.0
	bar.set_hp(hp, max_hp, false)
	add_child(bar)
	hpbar = bar

func _draw() -> void:
	draw_rect(Rect2(-15.0, -15.0, 30.0, 30.0), Color(0.15, 0.5, 0.9))
	draw_rect(Rect2(-15.0, -15.0, 30.0, 30.0), Color(0.03, 0.1, 0.25), false, 2.0)
	# 主角头顶标「我」
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(-24.0, -22.0), "我", HORIZONTAL_ALIGNMENT_CENTER, 48.0, 16.0, Color(0.9, 0.95, 1.0))

func _physics_process(delta: float) -> void:
	if game == null or game.game_over:
		return
	sword_cooldown = maxf(sword_cooldown - delta, 0.0)
	bow_cooldown = maxf(bow_cooldown - delta, 0.0)

	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	dir += external_move
	dir = dir.limit_length(1.0)
	if dir.length() > 0.05:
		facing = dir.normalized()
	velocity = dir * speed
	move_and_slide()
	_process_knockback(delta)

	if Input.is_action_just_pressed("attack"):
		attack()
	if external_attack:
		attack()
	if Input.is_action_just_pressed("restart"):
		game.restart()

func _apply_knockback(dir: Vector2, strength: float) -> void:
	knockback = dir.normalized() * strength

func _process_knockback(delta: float) -> void:
	if knockback.length() > 0.5:
		global_position += knockback * delta
		knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)

func attack() -> void:
	# 距离优先：把范围内敌人（敌方单位/建筑/野怪）与可采集资源放一起，谁近打谁
	var best_enemy: Node2D = _nearest_enemy_in_range(bow_range + 20.0)
	var best_res: ResourceNode = _nearest_resource_in_range(sword_reach)
	if best_enemy != null and (best_res == null or global_position.distance_to(best_enemy.global_position) <= global_position.distance_to(best_res.global_position)):
		game.active_gather = null  # 在打敌人/建筑，不再采集
		var dist: float = global_position.distance_to(best_enemy.global_position)
		# 近战/远程自动切换：剑范围内只用近战（冷却中也不射箭），剑外才用弓
		if dist <= sword_reach:
			if sword_cooldown <= 0.0:
				_do_sword(best_enemy)
			return
		if bow_cooldown <= 0.0:
			_shoot_arrow(best_enemy)
		return
	if best_res != null and sword_cooldown <= 0.0:
		sword_cooldown = sword_interval
		game.active_gather = best_res  # 通知附近小兵来帮打
		_spawn_slash(best_res.global_position)
		best_res.take_damage(sword_damage, team)

func _nearest_enemy_in_range(range_: float) -> Node2D:
	var enemy_name: String = "team%d" % (1 - team)
	var best: Node2D = null
	var best_dist: float = range_
	for node in get_tree().get_nodes_in_group(enemy_name):
		if not node.is_in_group("building") and not node.has_method("take_damage"):
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d <= best_dist:
			best_dist = d
			best = node as Node2D
	# 中立野怪（wild 组）对所有阵营敌对
	for node in get_tree().get_nodes_in_group("wild"):
		if not node.has_method("take_damage"):
			continue
		var dw: float = global_position.distance_to(node.global_position)
		if dw <= best_dist:
			best_dist = dw
			best = node as Node2D
	return best

func _nearest_resource_in_range(range_: float) -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = range_
	for node in get_tree().get_nodes_in_group("resource_node"):
		var r: ResourceNode = node as ResourceNode
		if r != null:
			var d: float = global_position.distance_to(node.global_position)
			if d <= best_dist:
				best_dist = d
				best = r
	return best

func _do_sword(target: Node2D) -> void:
	sword_cooldown = sword_interval
	_spawn_slash(target.global_position)
	if target.has_method("take_damage"):
		target.call("take_damage", sword_damage, team)
	# 近战轻微击退
	if target.has_method("_apply_knockback"):
		target.call("_apply_knockback", (target.global_position - global_position).normalized(), 140.0)

func _spawn_slash(toward: Vector2) -> void:
	var fx: MeleeFX = MeleeFX.new()
	fx.setup(toward - global_position)
	fx.global_position = global_position
	if game != null:
		game.add_child(fx)

func _shoot_arrow(target: Node2D) -> void:
	bow_cooldown = bow_interval
	var to: Vector2 = target.global_position - global_position
	if to.length() < 0.01:
		to = facing
	var p: Projectile = Projectile.new()
	p.setup(game, team, global_position, to, 380.0, bow_damage)
	game.add_child(p)

func take_damage(amount: float, attacker_team: int) -> void:
	hp -= amount
	if hpbar != null:
		hpbar.set_hp(hp, max_hp)
	if hp <= 0.0:
		hp = max_hp
		if hpbar != null:
			hpbar.set_hp(hp, max_hp)  # 复活后刷新血条
		# 小幅掉已采资源
		game.penalize_death(team)
		if is_instance_valid(game.player_base):
			global_position = game.player_base.global_position + Vector2(0.0, 90.0)
		else:
			global_position = game.player_spawn_point
