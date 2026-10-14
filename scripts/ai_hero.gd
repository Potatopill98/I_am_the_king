class_name AiHero
extends CharacterBody2D

## AI 敌人（完全镜像）：和玩家一样采集→建家→围墙+防御塔→升级→兵营→出兵→拆家。
## 用 try_build/try_upgrade 等同一套游戏逻辑，公平镜像。

var game: GameManager
var team: int = 1
var speed: float = 300.0
var hp: float = 30.0
var max_hp: float = 30.0
var knockback: Vector2 = Vector2.ZERO

var home_pos: Vector2 = Vector2(2000.0, 800.0)
var sword_damage: float = 3.0
var sword_cooldown: float = 0.0
var gather_target: ResourceNode = null
var gather_timer: float = 0.0
var push_phase: bool = false
var build_retry_timer: float = 0.0  # 建造失败（资源不够/没空地）后的重试冷却，避免每帧抖动
var hpbar: HpBar = null

func setup(g: GameManager, t: int, pos: Vector2, home: Vector2) -> void:
	game = g
	team = t
	global_position = pos
	home_pos = home
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(30.0, 30.0)
	shape.shape = rect
	add_child(shape)
	# 阵营1：mask=大本营(1)+敌队0(2)+野怪(16)+我方墙(32)，不撞自己墙/资源
	collision_layer = 4
	collision_mask = 51
	add_to_group("hero")
	add_to_group("team1")
	var bar: HpBar = HpBar.new()
	bar.offset_y = -18.0
	bar.bar_width = 40.0
	bar.always_show = true  # 敌方英雄血条常显，方便玩家看清敌方血量
	bar.set_hp(hp, max_hp, false)
	add_child(bar)
	hpbar = bar

func _draw() -> void:
	draw_rect(Rect2(-15.0, -15.0, 30.0, 30.0), Color(0.85, 0.3, 0.3))
	# 敌方头顶标「坏」
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(-24.0, -22.0), "坏", HORIZONTAL_ALIGNMENT_CENTER, 48.0, 16.0, Color(1.0, 0.85, 0.85))

func _physics_process(delta: float) -> void:
	if game == null or game.game_over:
		return
	sword_cooldown = maxf(sword_cooldown - delta, 0.0)
	build_retry_timer = maxf(build_retry_timer - delta, 0.0)
	_decide(delta)
	move_and_slide()
	if knockback.length() > 0.5:
		global_position += knockback * delta
		knockback = knockback.move_toward(Vector2.ZERO, 700.0 * delta)

func _apply_knockback(dir: Vector2, strength: float) -> void:
	knockback = dir.normalized() * strength

func _decide(delta: float) -> void:
	var base: Building = game.enemy_base
	if base == null or not is_instance_valid(base):
		# 还没建家：够资源就回家建，否则采集
		if game.wood_ai >= GameManager.COST_BASE_W and game.stone_ai >= GameManager.COST_BASE_S:
			_move_to(home_pos)
			if global_position.distance_to(home_pos) < 90.0:
				game.try_build(team, GameManager.TYPE_BASE)
		else:
			_gather(delta)
		return

	if not base.is_finished:
		_move_to(base.global_position)
		return

	# 已建家
	var tower_done: int = game.count_buildings(team, GameManager.TYPE_TOWER)   # 已完工
	var wall_done: int = game.count_buildings(team, GameManager.TYPE_WALL)
	var barracks_done: int = game.count_buildings(team, GameManager.TYPE_BARRACKS)
	var tower_total: int = _count_type(GameManager.TYPE_TOWER)                  # 含建造中
	var wall_total: int = _count_type(GameManager.TYPE_WALL)
	var barracks_total: int = _count_type(GameManager.TYPE_BARRACKS)
	var near_base: bool = global_position.distance_to(base.global_position) < 200.0
	# 建造失败（没空地）后的冷却：先采集几秒再试，避免空转
	if build_retry_timer > 0.0:
		_gather(delta)
		return

	# 确定当前要建的目标：塔 → 墙 → 兵营（一级大本营即可，升级机制搁置）
	var goal: String = ""
	if tower_total == 0:
		goal = GameManager.TYPE_TOWER
	elif wall_done < 4 and wall_total < 4:
		goal = GameManager.TYPE_WALL
	elif barracks_total < 2:
		if tower_done >= 1 and wall_done >= 4:
			goal = GameManager.TYPE_BARRACKS
		elif tower_total > tower_done or wall_total > wall_done:
			_move_to(base.global_position)
			return
	if goal != "":
		var need_w: int = game.cost_wood(goal)
		var need_s: int = game.cost_stone(goal)
		if game.wood_ai >= need_w and game.stone_ai >= need_s:
			if near_base:
				if not game.try_build(team, goal):
					build_retry_timer = 5.0  # 没空地：采几秒再试
					_gather(delta)
			else:
				_move_to(base.global_position)
		else:
			# 资源不够：持续采集，攒够才回基地建，不再来回空转
			_gather(delta)
		return
	# 攒铁升级兵营 → 全体变骑兵
	if barracks_done >= 1 and game.iron_ai >= GameManager.COST_UP_BARRACKS_IRON:
		if near_base:
			game.try_upgrade_barracks(team)
		else:
			_move_to(base.global_position)
		return
	# 进攻阶段：带兵压向玩家大本营
	if barracks_done >= 1:
		_push()
		return
	_gather(delta)

func _count_type(type: String) -> int:
	# 统计某类建筑总数（含建造中），避免建造期间重复建同类建筑
	var n: int = 0
	for node in get_tree().get_nodes_in_group("building"):
		var b: Building = node as Building
		if b != null and b.team == team and b.btype == type:
			n += 1
	return n

func _gather(delta: float) -> void:
	if gather_target == null or not is_instance_valid(gather_target):
		gather_target = _nearest_mineable()
	if gather_target == null:
		velocity = Vector2.ZERO
		return
	var d: float = global_position.distance_to(gather_target.global_position)
	if d > 46.0:
		_move_to(gather_target.global_position)
	else:
		velocity = Vector2.ZERO
		gather_timer += delta
		if gather_timer >= 0.6 and sword_cooldown <= 0.0:
			gather_timer = 0.0
			sword_cooldown = 0.6
			gather_target.take_damage(sword_damage, team)

func _nearest_mineable() -> ResourceNode:
	var best: ResourceNode = null
	var best_dist: float = 100000.0
	for node in get_tree().get_nodes_in_group("resource_node"):
		var r: ResourceNode = node as ResourceNode
		if r != null:
			if r.node_type == 2 and not game.can_mine_iron(team):
				continue
			var d: float = global_position.distance_to(node.global_position)
			if d < best_dist:
				best_dist = d
				best = r
	return best

func _push() -> void:
	# 让本方所有兵营进入跟随模式（重生的兵也保持跟随）
	for node in get_tree().get_nodes_in_group("building"):
		var b: Building = node as Building
		if b != null and b.btype == GameManager.TYPE_BARRACKS and b.team == team and b.is_finished:
			b.minion_mode = 1
	for node in get_tree().get_nodes_in_group("minion"):
		var m: Minion = node as Minion
		if m != null and m.team == team and m.mode != 1:
			m.mode = 1
	var target: Node2D = game.player_base
	if is_instance_valid(target):
		_move_to(target.global_position)
	else:
		velocity = Vector2.ZERO

func _move_to(pos: Vector2) -> void:
	var to: Vector2 = pos - global_position
	if to.length() > 6.0:
		velocity = to.normalized() * speed
	else:
		velocity = Vector2.ZERO

func take_damage(amount: float, attacker_team: int) -> void:
	hp -= amount
	if hpbar != null:
		hpbar.set_hp(hp, max_hp)
	if hp <= 0.0:
		hp = max_hp
		if hpbar != null:
			hpbar.set_hp(hp, max_hp)  # 复活后刷新血条
		if is_instance_valid(game.enemy_base):
			global_position = game.enemy_base.global_position + Vector2(0.0, 90.0)
		else:
			global_position = home_pos
