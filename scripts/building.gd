class_name Building
extends StaticBody2D

## 建筑共用类：大本营/兵营/防御塔/围墙。
## 建造期间＝未完工（占位无效，统一 10 血），可被打断（掉材料）；完工后才生效。

signal destroyed(team: int, type: String)

var game: GameManager
var team: int = 0
var btype: String = ""
var is_finished: bool = false
var build_time: float = 1.0
var build_timer: float = 0.0
var hp: float = 10.0
var max_hp: float = 10.0
var level: int = 1
var destroyed_flag: bool = false
var is_upgrading: bool = false
var pending_level: int = 1
var convert_on_finish: bool = false
var hpbar: HpBar = null

# 拆除状态
var demolishing: bool = false
var demolish_timer: float = 0.0
var demolish_total: float = 0.0

# 兵营配置
var unit_type: String = "swordman"
var fill_timer: float = 0.0
var replenish_timer: float = 0.0
var reached_cap: bool = false
var minion_mode: int = 0  # 兵营级：本营兵的模式 0 驻守 1 跟随

# 防御塔
var attack_timer: float = 0.0

func setup(g: GameManager, t: int, type: String, pos: Vector2) -> void:
	game = g
	team = t
	btype = type
	global_position = pos
	build_time = _build_time_for(type)
	hp = GameManager.UNFINISHED_HP
	max_hp = GameManager.UNFINISHED_HP
	_build_collision()
	_add_hpbar()
	add_to_group("building")
	add_to_group("team0" if team == 0 else "team1")

func _add_hpbar() -> void:
	var bar: HpBar = HpBar.new()
	if btype == GameManager.TYPE_BASE:
		bar.offset_y = -46.0
		bar.bar_width = 56.0
		bar.always_show = true
	elif btype == GameManager.TYPE_BARRACKS:
		bar.offset_y = -26.0
		bar.bar_width = 40.0
	elif btype == GameManager.TYPE_TOWER:
		bar.offset_y = -22.0
		bar.bar_width = 40.0
	else:
		bar.offset_y = -20.0
		bar.bar_width = 34.0
	bar.set_hp(hp, max_hp, false)
	add_child(bar)
	hpbar = bar

func _build_time_for(type: String) -> float:
	match type:
		GameManager.TYPE_BASE: return GameManager.TIME_BUILD_BASE
		GameManager.TYPE_WALL: return GameManager.TIME_WALL
		GameManager.TYPE_TOWER: return GameManager.TIME_TOWER
		GameManager.TYPE_BARRACKS: return GameManager.TIME_BARRACKS
	return 1.0

func _build_collision() -> void:
	# 只有大本营和围墙有碰撞体；塔/兵营无碰撞体，单位可穿行（攻击仍按距离判定）
	if btype != GameManager.TYPE_BASE and btype != GameManager.TYPE_WALL:
		return
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = block_size()
	shape.shape = rect
	add_child(shape)
	collision_mask = 0
	# 大本营通用障碍(双方都挡)；围墙分阵营：只挡敌方单位，自己人能穿
	if btype == GameManager.TYPE_BASE:
		collision_layer = 1
	else:
		collision_layer = 32 if team == 0 else 64

func block_size() -> Vector2:
	match btype:
		"base": return Vector2(70.0, 70.0)
		"barracks": return Vector2(46.0, 46.0)
		"tower": return Vector2(40.0, 40.0)
		"wall": return Vector2(32.0, 32.0)
	return Vector2(40.0, 40.0)

func block_radius() -> float:
	return block_size().x * 0.5

func _process(delta: float) -> void:
	if game == null:
		return
	if btype == GameManager.TYPE_BASE:
		queue_redraw()  # 大本营领地圈随建筑数变化，每帧重绘
	# 拆除优先：读条完成则返还资源并销毁
	if demolishing:
		demolish_timer += delta
		if hpbar != null:
			hpbar.set_progress(demolish_timer, demolish_total)
		if demolish_timer >= demolish_total:
			# 拆除兵营时，该兵营出的小兵也一起消失
			if btype == GameManager.TYPE_BARRACKS:
				for node in get_tree().get_nodes_in_group("minion"):
					var m: Minion = node as Minion
					if m != null and m.source_barracks == self:
						m.queue_free()
			game.refund_resources(team, btype)
			queue_free()
		return
	if not is_finished:
		build_timer += delta
		if hpbar != null:
			hpbar.set_progress(build_timer, build_time)
		if build_timer >= build_time:
			_finish_construction()
	elif not game.game_over:
		_update_finished(delta)

func _finish_construction() -> void:
	is_finished = true
	hp = GameManager.base_hp_for(btype)
	max_hp = GameManager.base_hp_for(btype)
	if hpbar != null:
		hpbar.set_progress(0.0, 0.0)
		hpbar.set_hp(hp, max_hp)
	if is_upgrading:
		level = pending_level
		if btype == GameManager.TYPE_BARRACKS and convert_on_finish:
			_convert_minions_to_cavalry()
			unit_type = "cavalry"  # 升级后后续出兵也都是骑兵
		is_upgrading = false
	queue_redraw()
	game.on_building_finished(self)

func begin_upgrade(time: float, new_level: int, convert: bool) -> void:
	if not is_finished:
		return
	is_finished = false
	is_upgrading = true
	pending_level = new_level
	convert_on_finish = convert
	build_time = time
	build_timer = 0.0
	hp = GameManager.UNFINISHED_HP
	max_hp = GameManager.UNFINISHED_HP
	if hpbar != null:
		hpbar.set_progress(0.0, time)
	queue_redraw()

func _convert_minions_to_cavalry() -> void:
	var team_name: String = "team%d" % team
	for node in get_tree().get_nodes_in_group("minion"):
		if node.is_in_group(team_name):
			var m: Minion = node as Minion
			if m != null and m.source_barracks == self:
				m.convert_to_cavalry()

func _update_finished(delta: float) -> void:
	if btype == GameManager.TYPE_BARRACKS:
		_update_barracks(delta)
	elif btype == GameManager.TYPE_TOWER:
		_update_tower(delta)

func _update_barracks(delta: float) -> void:
	var alive: int = count_alive_minions()
	if alive >= 3:
		reached_cap = true
		fill_timer = 0.0
		replenish_timer = 0.0
		return
	if not reached_cap:
		fill_timer += delta
		if fill_timer >= 3.0:
			fill_timer = 0.0
			game.spawn_minion(team, global_position + Vector2(0.0, 40.0), unit_type, self)
	else:
		replenish_timer += delta
		if replenish_timer >= 10.0:
			replenish_timer = 0.0
			game.spawn_minion(team, global_position + Vector2(0.0, 40.0), unit_type, self)

func count_alive_minions() -> int:
	var count: int = 0
	var team_name: String = "team%d" % team
	for node in get_tree().get_nodes_in_group("minion"):
		if node.is_in_group(team_name):
			var m: Minion = node as Minion
			if m != null and m.source_barracks == self:
				count += 1
	return count

func _update_tower(delta: float) -> void:
	attack_timer += delta
	if attack_timer < 0.8:
		return
	attack_timer = 0.0
	var target: Node2D = _nearest_enemy_unit(240.0)
	if target != null:
		var to: Vector2 = target.global_position - global_position
		var p: Projectile = Projectile.new()
		p.setup(game, team, global_position, to, 380.0, 2.0)
		game.add_child(p)

func _nearest_enemy_unit(range_: float) -> Node2D:
	var enemy_name: String = "team%d" % (1 - team)
	var best: Node2D = null
	var best_dist: float = range_
	for node in get_tree().get_nodes_in_group(enemy_name):
		if not node.has_method("take_damage"):
			continue
		if node is Building:
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d <= best_dist:
			best_dist = d
			best = node as Node2D
	# 中立野怪：防御塔也会打
	for node in get_tree().get_nodes_in_group("wild"):
		if not node.has_method("take_damage"):
			continue
		var dw: float = global_position.distance_to(node.global_position)
		if dw <= best_dist:
			best_dist = dw
			best = node as Node2D
	return best

func upgrade() -> bool:
	if not is_finished:
		return false
	level += 1
	queue_redraw()
	return true

func take_damage(amount: float, attacker_team: int) -> void:
	if destroyed_flag:
		return
	hp -= amount
	if hpbar != null:
		hpbar.set_hp(hp, max_hp)
	if hp <= 0.0:
		destroyed_flag = true
		if not is_finished:
			game.on_building_interrupted(self)
		else:
			game.on_building_destroyed(self)
		queue_free()

func _draw() -> void:
	if btype == GameManager.TYPE_BASE:
		var col: Color = Color(0.2, 0.55, 0.92) if team == 0 else Color(0.9, 0.3, 0.3)
		_draw_sq(35.0, col)
		draw_rect(Rect2(-9.0, -44.0, 6.0, 24.0), Color(0.42, 0.26, 0.10))
		draw_rect(Rect2(-9.0, -44.0, 22.0, 8.0), col)
	elif btype == GameManager.TYPE_BARRACKS:
		_draw_sq(23.0, Color(0.2, 0.66, 0.45) if team == 0 else Color(0.8, 0.42, 0.22))
	elif btype == GameManager.TYPE_TOWER:
		_draw_sq(20.0, Color(0.45, 0.5, 0.75) if team == 0 else Color(0.7, 0.4, 0.6))
	elif btype == GameManager.TYPE_WALL:
		_draw_sq(16.0, Color(0.62, 0.5, 0.34))
	# 大本营领地范围圈（浅色虚线）：每建一个建筑，领地半径扩大
	if btype == GameManager.TYPE_BASE and game != null:
		var tr: float = game.territory_radius(team)
		_draw_dashed_circle(Vector2.ZERO, tr, Color(0.4, 0.9, 0.5, 0.3), 2.0, 0.22, 0.18)
	# 头顶类型字：大本营「大」、塔「塔」、兵营「兵」
	var label: String = ""
	if btype == GameManager.TYPE_BASE:
		label = "大"
	elif btype == GameManager.TYPE_TOWER:
		label = "塔"
	elif btype == GameManager.TYPE_BARRACKS:
		label = "兵"
	if label != "":
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(-24.0, 8.0), label, HORIZONTAL_ALIGNMENT_CENTER, 48.0, 18.0, Color.WHITE)
	# 范围虚线（完工后）：塔=射程240，兵营=200，浅色不刺眼
	if is_finished:
		if btype == GameManager.TYPE_TOWER:
			_draw_dashed_circle(Vector2.ZERO, 240.0, Color(0.7, 0.8, 1.0, 0.35), 2.0, 0.2, 0.16)
		elif btype == GameManager.TYPE_BARRACKS:
			_draw_dashed_circle(Vector2.ZERO, 200.0, Color(0.7, 1.0, 0.8, 0.35), 2.0, 0.2, 0.16)

func _draw_dashed_circle(pos: Vector2, r: float, col: Color, width: float, dash: float, gap: float) -> void:
	var a: float = 0.0
	while a < TAU:
		var a1: float = minf(a + dash, TAU)
		var p0: Vector2 = pos + Vector2(cos(a), sin(a)) * r
		var p1: Vector2 = pos + Vector2(cos(a1), sin(a1)) * r
		draw_line(p0, p1, col, width)
		a += dash + gap

func _draw_sq(half: float, col: Color) -> void:
	if not is_finished:
		col = col.lerp(Color(0.9, 0.9, 0.9), 0.6)
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), col)
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), Color(0, 0, 0, 0.5), false, 2.0)
