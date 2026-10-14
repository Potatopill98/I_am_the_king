class_name GameManager
extends Node2D

## 总控：世界、队伍、资源、领地、建造（判定+吸附+预览）、出兵、野怪、胜负与 8 分钟加速、界面切换。

const WORLD_W: float = 4800.0
const WORLD_H: float = 3200.0

const TEAM_PLAYER: int = 0
const TEAM_AI: int = 1

const TYPE_BASE: String = "base"
const TYPE_WALL: String = "wall"
const TYPE_TOWER: String = "tower"
const TYPE_BARRACKS: String = "barracks"

# 资源类型（与 ResourceNode 内的常量一致；本地定义避免跨类编译期依赖）
const RES_WOOD: int = 0
const RES_STONE: int = 1
const RES_IRON: int = 2

# ---- 成本 ----
const COST_BASE_W: int = 5
const COST_BASE_S: int = 5
const COST_WALL_S: int = 2
const COST_TOWER_W: int = 4
const COST_TOWER_S: int = 3
const COST_BARRACKS_W: int = 8
const COST_BARRACKS_S: int = 8
const COST_UP_BASE_W: int = 15
const COST_UP_BASE_S: int = 12
const COST_UP_BARRACKS_IRON: int = 12

# ---- 建造/升级耗时（秒）----
const TIME_BUILD_BASE: float = 10.0
const TIME_WALL: float = 2.0
const TIME_TOWER: float = 5.0
const TIME_BARRACKS: float = 5.0
const TIME_UP_BASE: float = 10.0
const TIME_UP_BARRACKS: float = 10.0

# ---- 放置/拆除 ----
const PLACE_RANGE: float = 140.0  # 玩家身边放置半径（约4.5个身位）
const TIME_DEMOLISH_WALL: float = 1.0
const TIME_DEMOLISH_OTHER: float = 3.0

# ---- 血量 ----
const UNFINISHED_HP: float = 10.0
const HP_BASE: float = 80.0
const HP_BARRACKS: float = 30.0
const HP_TOWER: float = 30.0
const HP_WALL: float = 20.0

# ---- 领地 / 节奏 ----
const TERRITORY_BASE_RADIUS: float = 120.0
const TERRITORY_PER_BUILD: float = 40.0
const TERRITORY_PER_BASE_LEVEL: float = 60.0
const MATCH_TIME_LIMIT: float = 480.0
const ESCALATE_INTERVAL: float = 60.0
const ESCALATE_BONUS: float = 0.15

var rng: RandomNumberGenerator = RandomNumberGenerator.new()

var world: GameWorld
var player: Player
var ai_hero: AiHero
var hud: Hud
var preview: BuildPreview

# 放置/拆除模式（玩家端）
var placing_type: String = ""  # 非空=正在放置该类型建筑
var demolish_mode: bool = false

var player_base: Building = null
var enemy_base: Building = null
var player_spawn_point: Vector2 = Vector2(700.0, 600.0)
var ai_home_point: Vector2 = Vector2(4100.0, 2600.0)

var wood_player: int = 0
var stone_player: int = 0
var iron_player: int = 0
var wood_ai: int = 0
var stone_ai: int = 0
var iron_ai: int = 0

var match_started: bool = false
var game_over: bool = false
var active_gather: ResourceNode = null  # 玩家当前在砍的资源（附近小兵会帮打）
var match_time: float = 0.0
var escalate_stage: int = 0
var escalate_multiplier: float = 1.0
var tutorial: bool = false

func _ready() -> void:
	_setup_input_actions()
	rng.randomize()
	world = GameWorld.new()
	world.name = "World"
	world.setup(WORLD_W, WORLD_H)
	add_child(world)
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(self)
	hud.show_start_menu()

# 【开发用】P 键 = 开发者上帝模式：+500 木/石/铁。最终发布时须删除本函数。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
		if match_started:
			credit(TEAM_PLAYER, RES_WOOD, 500)
			credit(TEAM_PLAYER, RES_STONE, 500)
			credit(TEAM_PLAYER, RES_IRON, 500)
			toast(TEAM_PLAYER, "开发者模式：+500 木/石/铁")

func _process(delta: float) -> void:
	if hud != null:
		hud.update_ui(delta)
	if match_started and not game_over:
		match_time += delta
		# 8 分钟后：每 1 分钟全体小兵伤害 +15%，加速收尾（不硬性比血量，以拆家定胜负）
		if match_time >= MATCH_TIME_LIMIT:
			var stage: int = int((match_time - MATCH_TIME_LIMIT) / ESCALATE_INTERVAL) + 1
			if stage > escalate_stage:
				escalate_stage = stage
				escalate_multiplier = 1.0 + ESCALATE_BONUS * float(stage)

# ---------- 输入 ----------
func _setup_input_actions() -> void:
	var actions: Dictionary = {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"attack": [KEY_SPACE],
		"restart": [KEY_R],
	}
	for action in actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var keys: Array = actions[action]
			for key in keys:
				var ev: InputEventKey = InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
	if not InputMap.has_action("attack_mouse"):
		InputMap.add_action("attack_mouse")
		var me: InputEventMouseButton = InputEventMouseButton.new()
		me.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack_mouse", me)

# ---------- 开局 ----------
func start_match(is_tutorial: bool) -> void:
	if match_started:
		return
	match_started = true
	tutorial = is_tutorial
	_spawn_resources()
	_spawn_wild()
	_spawn_entities()
	preview = BuildPreview.new()
	preview.name = "Preview"
	preview.setup(self)
	preview.visible = false
	add_child(preview)
	hud.show_match_hud()
	if tutorial:
		hud.show_toast("教程：走近树/矿，按攻击键采集；攒够 5木5石 就能建大本营")

func _spawn_entities() -> void:
	player = Player.new()
	player.name = "Player"
	player.setup(self, TEAM_PLAYER, player_spawn_point)
	add_child(player)
	ai_hero = AiHero.new()
	ai_hero.name = "AiHero"
	ai_hero.setup(self, TEAM_AI, ai_home_point, ai_home_point)
	add_child(ai_hero)
	var cam: Camera2D = Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)

func _spawn_resources() -> void:
	var wood_positions: Array = _make_points(70, 400.0, 4400.0, 400.0, 2800.0)
	for pos in wood_positions:
		_add_resource(RES_WOOD, pos)
	var stone_positions: Array = _make_points(50, 500.0, 4300.0, 400.0, 2800.0)
	for pos in stone_positions:
		_add_resource(RES_STONE, pos)
	var iron_positions: Array = _make_points(20, 900.0, 3900.0, 500.0, 2700.0)
	for pos in iron_positions:
		_add_resource(RES_IRON, pos)

func _make_points(count: int, min_x: float, max_x: float, min_y: float, max_y: float) -> Array:
	var pts: Array = []
	for i in range(count):
		pts.append(Vector2(rng.randf_range(min_x, max_x), rng.randf_range(min_y, max_y)))
	return pts

func _add_resource(type: int, pos: Vector2) -> void:
	var n: ResourceNode = ResourceNode.new()
	n.setup(self, type, pos)
	n.harvested.connect(_on_resource_harvested)
	add_child(n)

func _on_resource_harvested(team: int, type: int, amount: int) -> void:
	credit(team, type, amount)

func _spawn_wild() -> void:
	# 弱怪群（2~3 只）：地图变大，分散到 6 处中立区域
	var weak_centers: Array = [
		Vector2(1200.0, 1000.0), Vector2(3600.0, 900.0), Vector2(2400.0, 2400.0),
		Vector2(700.0, 2400.0), Vector2(4300.0, 1600.0), Vector2(2000.0, 500.0)
	]
	for c in weak_centers:
		var n: int = rng.randi_range(2, 3)
		for i in range(n):
			var m: WildMonster = WildMonster.new()
			m.setup(self, false, c + Vector2(rng.randf_range(-50.0, 50.0), rng.randf_range(-50.0, 50.0)), c)
			add_child(m)
	# 强怪群（4~5 只）：分散 4 处
	var strong_centers: Array = [
		Vector2(1400.0, 2000.0), Vector2(3300.0, 1300.0),
		Vector2(900.0, 1300.0), Vector2(3900.0, 2800.0)
	]
	for c in strong_centers:
		var n: int = rng.randi_range(4, 5)
		for i in range(n):
			var m: WildMonster = WildMonster.new()
			m.setup(self, true, c + Vector2(rng.randf_range(-60.0, 60.0), rng.randf_range(-60.0, 60.0)), c)
			add_child(m)

# ---------- 领地 ----------
func count_buildings(team: int, type: String) -> int:
	var team_name: String = "team%d" % team
	var count: int = 0
	for node in get_tree().get_nodes_in_group("building"):
		if node.is_in_group(team_name):
			var b: Building = node as Building
			if b != null and b.is_finished and b.btype == type:
				count += 1
	return count

func count_finished_buildings(team: int) -> int:
	var team_name: String = "team%d" % team
	var count: int = 0
	for node in get_tree().get_nodes_in_group("building"):
		if node.is_in_group(team_name):
			var b: Building = node as Building
			if b != null and b.is_finished:
				count += 1
	return count

func territory_radius(team: int) -> float:
	var base: Building = player_base if team == TEAM_PLAYER else enemy_base
	var radius: float = TERRITORY_BASE_RADIUS + float(count_finished_buildings(team)) * TERRITORY_PER_BUILD
	if base != null and is_instance_valid(base) and base.level >= 2:
		radius += TERRITORY_PER_BASE_LEVEL
	return radius

func can_mine_iron(team: int) -> bool:
	# 大本营升级机制搁置：一级即可采铁（配合小兵帮挖，效率更高）
	return true

func on_building_finished(b: Building) -> void:
	if b.btype == TYPE_BASE:
		if b.team == TEAM_PLAYER:
			player_base = b
		else:
			enemy_base = b

# ---------- 建造 ----------
func try_build(team: int, type: String) -> bool:
	# 大本营：每名玩家只能建 1 座
	if type == TYPE_BASE:
		var existing: Building = player_base if team == TEAM_PLAYER else enemy_base
		if existing != null and is_instance_valid(existing):
			toast(team, "已有大本营，不能重复建造")
			return false
	# 兵营前置：一级大本营 + 4 块城墙 + 1 座防御塔（大本营升级机制已搁置）
	if type == TYPE_BARRACKS:
		if count_buildings(team, TYPE_WALL) < 4 or count_buildings(team, TYPE_TOWER) < 1:
			toast(team, "需先建 4 块城墙和 1 座防御塔才能建兵营")
			return false
	var from: Vector2 = player.global_position if team == TEAM_PLAYER else ai_hero.global_position
	var spot: Vector2 = find_valid_spot(team, type, from)
	if spot == Vector2.INF:
		toast(team, "这里建不了（不在领地 / 没有空地）")
		return false
	var w: int = cost_wood(type)
	var s: int = cost_stone(type)
	if not can_afford(team, w, s, 0):
		toast(team, "资源不够")
		return false
	spend(team, w, s, 0)
	var b: Building = Building.new()
	b.name = "Building_%s_%d" % [type, rng.randi()]
	b.setup(self, team, type, spot)
	if type == TYPE_BASE:
		if team == TEAM_PLAYER:
			player_base = b
		else:
			enemy_base = b
	add_child(b)
	toast(team, "开始建造：" + display_name(type))
	return true

# ---------- 点选放置（玩家端） ----------
func place_at(team: int, type: String, pos: Vector2) -> bool:
	# 大本营：每名玩家只能建 1 座
	if type == TYPE_BASE:
		var existing: Building = player_base if team == TEAM_PLAYER else enemy_base
		if existing != null and is_instance_valid(existing):
			toast(team, "已有大本营，不能重复建造")
			return false
	# 兵营前置：4 块城墙 + 1 座防御塔
	if type == TYPE_BARRACKS:
		if count_buildings(team, TYPE_WALL) < 4 or count_buildings(team, TYPE_TOWER) < 1:
			toast(team, "需先建 4 块城墙和 1 座防御塔才能建兵营")
			return false
	if not can_place_at(team, type, pos):
		toast(team, "这里建不了（超出放置范围 / 没有空地）")
		return false
	var w: int = cost_wood(type)
	var s: int = cost_stone(type)
	if not can_afford(team, w, s, 0):
		toast(team, "资源不够")
		return false
	spend(team, w, s, 0)
	var b: Building = Building.new()
	b.name = "Building_%s_%d" % [type, rng.randi()]
	b.setup(self, team, type, pos)
	if type == TYPE_BASE:
		if team == TEAM_PLAYER:
			player_base = b
		else:
			enemy_base = b
	add_child(b)
	toast(team, "开始建造：" + display_name(type))
	cancel_placement()
	return true

func can_place_at(team: int, type: String, pos: Vector2) -> bool:
	# 世界边界
	if pos.x < 60.0 or pos.x > WORLD_W - 60.0 or pos.y < 60.0 or pos.y > WORLD_H - 60.0:
		return false
	# 玩家放置范围：必须在玩家身边小圈内
	var from: Vector2 = player.global_position if team == TEAM_PLAYER else ai_hero.global_position
	if pos.distance_to(from) > PLACE_RANGE:
		return false
	# 大本营：与另一家保持距离
	if type == TYPE_BASE:
		var other: Building = enemy_base if team == TEAM_PLAYER else player_base
		if other != null and is_instance_valid(other):
			if pos.distance_to(other.global_position) < 500.0:
				return false
	# 空地检查（不与建筑/资源重叠）
	if not is_space_clear(pos, block_radius_for(type)):
		return false
	return true

# ---------- 拆除 ----------
func start_demolish(team: int, b: Building) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	if b.team != team:
		toast(team, "不能拆除敌方建筑")
		return false
	if b.btype == TYPE_BASE:
		toast(team, "大本营不能拆除")
		return false
	if b.demolishing:
		return false
	# 拆除也需要在玩家身边放置范围内
	var from: Vector2 = player.global_position if team == TEAM_PLAYER else ai_hero.global_position
	if b.global_position.distance_to(from) > PLACE_RANGE:
		toast(team, "离得太远，无法拆除")
		return false
	b.demolishing = true
	b.demolish_timer = 0.0
	b.demolish_total = TIME_DEMOLISH_WALL if b.btype == TYPE_WALL else TIME_DEMOLISH_OTHER
	toast(team, "开始拆除：" + display_name(b.btype))
	return true

func cancel_placement() -> void:
	placing_type = ""
	demolish_mode = false
	if preview != null and is_instance_valid(preview):
		preview.visible = false

func refund_resources(team: int, type: String) -> void:
	var w: int = cost_wood(type)
	var s: int = cost_stone(type)
	if team == TEAM_PLAYER:
		wood_player += w
		stone_player += s
	else:
		wood_ai += w
		stone_ai += s

func cost_wood(type: String) -> int:
	match type:
		TYPE_BASE: return COST_BASE_W
		TYPE_TOWER: return COST_TOWER_W
		TYPE_BARRACKS: return COST_BARRACKS_W
		_: return 0

func cost_stone(type: String) -> int:
	match type:
		TYPE_BASE: return COST_BASE_S
		TYPE_WALL: return COST_WALL_S
		TYPE_TOWER: return COST_TOWER_S
		TYPE_BARRACKS: return COST_BARRACKS_S
		_: return 0

func display_name(type: String) -> String:
	match type:
		TYPE_BASE: return "大本营"
		TYPE_WALL: return "围墙"
		TYPE_TOWER: return "防御塔"
		TYPE_BARRACKS: return "兵营"
	return type

func can_place(team: int, type: String, pos: Vector2) -> bool:
	if pos.x < 60.0 or pos.x > WORLD_W - 60.0 or pos.y < 60.0 or pos.y > WORLD_H - 60.0:
		return false
	if type == TYPE_BASE:
		# 建家：空地 + 与另一家保持距离（两家领地不能挨一起）
		var other: Building = enemy_base if team == TEAM_PLAYER else player_base
		if other != null and is_instance_valid(other):
			if pos.distance_to(other.global_position) < 500.0:
				return false
	else:
		var base: Building = player_base if team == TEAM_PLAYER else enemy_base
		if base == null or not is_instance_valid(base):
			return false
		if pos.distance_to(base.global_position) > territory_radius(team):
			return false
	if not is_space_clear(pos, block_radius_for(type)):
		return false
	return true

func block_radius_for(type: String) -> float:
	match type:
		TYPE_BASE: return 45.0
		TYPE_WALL: return 20.0
		TYPE_BARRACKS: return 28.0
		TYPE_TOWER: return 26.0
	return 26.0

func preview_ok(team: int, pos: Vector2) -> bool:
	var base: Building = player_base if team == TEAM_PLAYER else enemy_base
	if base == null or not is_instance_valid(base):
		return is_space_clear(pos, 26.0)
	if pos.distance_to(base.global_position) > territory_radius(team):
		return false
	return is_space_clear(pos, 26.0)

func is_space_clear(pos: Vector2, radius: float) -> bool:
	for node in get_tree().get_nodes_in_group("building"):
		var b: Building = node as Building
		if b != null and pos.distance_to(b.global_position) < radius + b.block_radius():
			return false
	for node in get_tree().get_nodes_in_group("resource_node"):
		if pos.distance_to(node.global_position) < radius + 22.0:
			return false
	return true

func find_valid_spot(team: int, type: String, from: Vector2) -> Vector2:
	if can_place(team, type, from):
		return from
	var step: float = 48.0
	for ring in range(1, 6):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if abs(dx) != ring and abs(dy) != ring:
					continue
				var cand: Vector2 = from + Vector2(float(dx) * step, float(dy) * step)
				if can_place(team, type, cand):
					return cand
	return Vector2.INF

func try_upgrade_base(team: int) -> bool:
	var base: Building = player_base if team == TEAM_PLAYER else enemy_base
	if base == null or not is_instance_valid(base):
		return false
	if not base.is_finished:
		return false
	if base.level >= 2:
		return false
	if count_buildings(team, TYPE_TOWER) < 1 or count_buildings(team, TYPE_WALL) < 1:
		toast(team, "升级大本营需先建好防御塔和围墙")
		return false
	if not can_afford(team, COST_UP_BASE_W, COST_UP_BASE_S, 0):
		toast(team, "升级大本营资源不够（15木 12石）")
		return false
	spend(team, COST_UP_BASE_W, COST_UP_BASE_S, 0)
	base.begin_upgrade(TIME_UP_BASE, 2, false)
	toast(team, "大本营升级中（10秒）")
	return true

func try_upgrade_barracks(team: int) -> bool:
	# 大本营升级已搁置，兵营升级只需 12 铁
	if not can_afford(team, 0, 0, COST_UP_BARRACKS_IRON):
		toast(team, "升级兵营需 12 铁")
		return false
	# 先找可升级的兵营（已完工、等级<2），找不到不扣铁
	var team_name: String = "team%d" % team
	var targets: Array = []
	for node in get_tree().get_nodes_in_group("building"):
		if node.is_in_group(team_name):
			var b: Building = node as Building
			if b != null and b.is_finished and b.btype == TYPE_BARRACKS and b.level < 2:
				targets.append(b)
	if targets.is_empty():
		toast(team, "没有可升级的兵营（需已完工且未升级）")
		return false
	# 确认有可升级目标后再扣铁
	spend(team, 0, 0, COST_UP_BARRACKS_IRON)
	for b in targets:
		b.begin_upgrade(TIME_UP_BARRACKS, 2, true)
	toast(team, "兵营升级中（10秒）→ 全体变骑兵")
	return true

# ---------- 资源 ----------
func wood_of(team: int) -> int:
	return wood_player if team == TEAM_PLAYER else wood_ai

func can_afford(team: int, w: int, s: int, i: int) -> bool:
	return wood_of(team) >= w and _stone_of(team) >= s and _iron_of(team) >= i

func _stone_of(team: int) -> int:
	return stone_player if team == TEAM_PLAYER else stone_ai

func _iron_of(team: int) -> int:
	return iron_player if team == TEAM_PLAYER else iron_ai

func spend(team: int, w: int, s: int, i: int) -> void:
	if team == TEAM_PLAYER:
		wood_player -= w
		stone_player -= s
		iron_player -= i
	else:
		wood_ai -= w
		stone_ai -= s
		iron_ai -= i

func credit(team: int, type: int, amount: int) -> void:
	if team == TEAM_PLAYER:
		if type == RES_WOOD:
			wood_player += amount
		elif type == RES_STONE:
			stone_player += amount
		else:
			iron_player += amount
	else:
		if type == RES_WOOD:
			wood_ai += amount
		elif type == RES_STONE:
			stone_ai += amount
		else:
			iron_ai += amount

func penalize_death(team: int) -> void:
	if team == TEAM_PLAYER:
		wood_player = maxi(wood_player - 1, 0)
		stone_player = maxi(stone_player - 1, 0)
	else:
		wood_ai = maxi(wood_ai - 1, 0)
		stone_ai = maxi(stone_ai - 1, 0)

func spawn_minion(team: int, pos: Vector2, type: String, src: Building) -> void:
	var m: Minion = Minion.new()
	m.name = "Minion_%d" % rng.randi()
	m.setup(self, team, pos, type, src)
	# 出兵沿用所属兵营的独立模式（驻守/跟随），不退回驻守
	if src != null:
		m.mode = src.minion_mode
	add_child(m)

func spawn_drop(type: int, amount: int, pos: Vector2) -> void:
	var d: ResourceDrop = ResourceDrop.new()
	d.setup(self, type, amount, pos)
	add_child(d)

func schedule_resource_respawn(node_type: int, pos: Vector2) -> void:
	var timer: SceneTreeTimer = get_tree().create_timer(60.0)
	timer.timeout.connect(func() -> void:
		if not game_over:
			_add_resource(node_type, pos)
	)

# ---------- 建筑被打断 / 摧毁 ----------
func on_building_interrupted(b: Building) -> void:
	# 掉一部分材料到地上（双方都能捡）
	var type: int = RES_WOOD
	var amt: int = 0
	if b.btype == TYPE_BASE:
		spawn_drop(RES_WOOD, 2, b.global_position + Vector2(-10.0, 0.0))
		spawn_drop(RES_STONE, 2, b.global_position + Vector2(10.0, 0.0))
	elif b.btype == TYPE_WALL:
		spawn_drop(RES_STONE, 1, b.global_position)
	elif b.btype == TYPE_TOWER:
		spawn_drop(RES_WOOD, 1, b.global_position + Vector2(-8.0, 0.0))
		spawn_drop(RES_STONE, 1, b.global_position + Vector2(8.0, 0.0))
	elif b.btype == TYPE_BARRACKS:
		spawn_drop(RES_WOOD, 2, b.global_position + Vector2(-10.0, 0.0))
		spawn_drop(RES_STONE, 2, b.global_position + Vector2(10.0, 0.0))

func on_building_destroyed(b: Building) -> void:
	if b.btype == TYPE_BASE:
		on_base_destroyed(b.team)
	else:
		on_building_interrupted(b)

func on_base_destroyed(team: int) -> void:
	if game_over:
		return
	game_over = true
	var winner: int = 1 - team
	hud.show_result(winner, "敌方大本营被摧毁！")

func restart() -> void:
	get_tree().reload_current_scene()

func toast(team: int, msg: String) -> void:
	# 提示只显示给对应阵营（单机＝玩家阵营0；AI 的提示不出现在玩家屏幕）
	if hud != null and team == TEAM_PLAYER:
		hud.show_toast(msg)

# ---------- 血量 ----------
static func base_hp_for(type: String) -> float:
	match type:
		TYPE_BASE: return HP_BASE
		TYPE_BARRACKS: return HP_BARRACKS
		TYPE_TOWER: return HP_TOWER
		TYPE_WALL: return HP_WALL
	return 20.0
