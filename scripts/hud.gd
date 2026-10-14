class_name Hud
extends CanvasLayer

## 界面：开始菜单 → 局内 HUD（资源/计时/大本营血量/建造+升级/小兵切换/摇杆/攻击/预览/提示）→ 结算。

var game: GameManager

# 局内控件
var res_label: Label
var timer_label: Label
var base_hp_label: Label
var esc_label: Label
var toast_label: Label
var toast_timer: float = 0.0

var build_panel: VBoxContainer
var build_toggle: Button
var barracks_btn: Button
var barracks_btn_target: Building = null

var start_menu: Control
var result_panel: Control
var match_root: Control

var joystick: JoystickControl
var mouse_world: Vector2 = Vector2.ZERO  # 鼠标/手指当前的世界坐标（放置虚影跟随）

func setup(g: GameManager) -> void:
	game = g

# ---------- 开始菜单 ----------
func show_start_menu() -> void:
	start_menu = Control.new()
	start_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(start_menu)

	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.08, 0.12, 0.16, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_menu.add_child(bg)

	var title: Label = Label.new()
	title.text = "我要当国王"
	title.add_theme_font_size_override("font_size", 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 120)
	title.size = Vector2(720, 80)
	title.anchors_preset = Control.PRESET_CENTER_TOP
	start_menu.add_child(title)

	var btn1: Button = _make_menu_button("开始单人")
	btn1.position = Vector2(260, 300)
	btn1.size = Vector2(200, 60)
	btn1.pressed.connect(func() -> void:
		start_menu.queue_free()
		game.start_match(false)
	)
	start_menu.add_child(btn1)

	var btn2: Button = _make_menu_button("教程")
	btn2.position = Vector2(260, 380)
	btn2.size = Vector2(200, 60)
	btn2.pressed.connect(func() -> void:
		start_menu.queue_free()
		game.start_match(true)
	)
	start_menu.add_child(btn2)

# ---------- 局内 HUD ----------
func show_match_hud() -> void:
	match_root = Control.new()
	match_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(match_root)

	res_label = Label.new()
	res_label.text = "木0 石0 铁0"
	res_label.add_theme_font_size_override("font_size", 22)
	res_label.position = Vector2(16, 12)
	res_label.size = Vector2(280, 30)
	res_label.add_theme_color_override("font_color", Color.WHITE)
	match_root.add_child(res_label)

	base_hp_label = Label.new()
	base_hp_label.text = "大本营：-"
	base_hp_label.add_theme_font_size_override("font_size", 20)
	base_hp_label.position = Vector2(16, 44)
	base_hp_label.size = Vector2(280, 26)
	base_hp_label.add_theme_color_override("font_color", Color.WHITE)
	match_root.add_child(base_hp_label)

	timer_label = Label.new()
	timer_label.text = "0:00"
	timer_label.add_theme_font_size_override("font_size", 24)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.position = Vector2(280, 10)
	timer_label.size = Vector2(160, 30)
	match_root.add_child(timer_label)

	esc_label = Label.new()
	esc_label.text = ""
	esc_label.add_theme_font_size_override("font_size", 16)
	esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	esc_label.position = Vector2(280, 42)
	esc_label.size = Vector2(160, 24)
	esc_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	match_root.add_child(esc_label)

	# 建造按钮（二级菜单入口，右下）
	build_toggle = _make_button("建造 ▸")
	build_toggle.position = Vector2(1070, 448)
	build_toggle.size = Vector2(130, 62)
	build_toggle.add_theme_font_size_override("font_size", 22)
	build_toggle.pressed.connect(_toggle_build_panel)
	match_root.add_child(build_toggle)

	# 建造/升级选项面板（默认隐藏，点开建造才展开）
	var bg: Panel = Panel.new()
	bg.position = Vector2(756, 206)
	bg.size = Vector2(300, 336)
	bg.visible = false
	match_root.add_child(bg)
	build_panel = VBoxContainer.new()
	build_panel.visible = false
	build_panel.position = Vector2(764, 216)
	build_panel.add_theme_constant_override("separation", 6)
	build_panel.custom_minimum_size = Vector2(280, 0)
	match_root.add_child(build_panel)

	_build_btn(build_panel, "建家(5木5石)", Callable(self, "_start_placing").bind(GameManager.TYPE_BASE))
	_build_btn(build_panel, "围墙(石2)", Callable(self, "_start_placing").bind(GameManager.TYPE_WALL))
	_build_btn(build_panel, "防御塔(木4石3)", Callable(self, "_start_placing").bind(GameManager.TYPE_TOWER))
	_build_btn(build_panel, "兵营(木8石8)", Callable(self, "_start_placing").bind(GameManager.TYPE_BARRACKS))
	_build_btn(build_panel, "升级兵营(12铁)", Callable(game, "try_upgrade_barracks").bind(GameManager.TEAM_PLAYER))
	_build_btn(build_panel, "拆除", Callable(self, "_start_demolish"))

	# 兵营旁交互按钮（默认隐藏，靠近某兵营时出现）
	barracks_btn = _make_button("驻守")
	barracks_btn.visible = false
	barracks_btn.pressed.connect(_on_barracks_btn)
	match_root.add_child(barracks_btn)

	# 攻击按钮（右下，可按住连打）
	var atk: Button = _make_button("攻击")
	atk.position = Vector2(1066, 536)
	atk.size = Vector2(140, 120)
	atk.add_theme_font_size_override("font_size", 28)
	atk.button_down.connect(func() -> void:
		if is_instance_valid(game.player):
			game.player.external_attack = true
	)
	atk.button_up.connect(func() -> void:
		if is_instance_valid(game.player):
			game.player.external_attack = false
	)
	atk.pressed.connect(func() -> void:
		if is_instance_valid(game.player):
			game.player.attack()
	)
	match_root.add_child(atk)

	# 动态浮动摇杆（左半屏，触摸/鼠标左侧任意位置出现）
	joystick = JoystickControl.new()
	match_root.add_child(joystick)

	# 提示
	toast_label = Label.new()
	toast_label.text = ""
	toast_label.add_theme_font_size_override("font_size", 20)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.position = Vector2(120, 300)
	toast_label.size = Vector2(480, 40)
	toast_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	match_root.add_child(toast_label)

func _build_btn(parent: Control, text: String, callback: Callable) -> void:
	var b: Button = _make_button(text)
	b.pressed.connect(callback)
	parent.add_child(b)

func _toggle_build_panel() -> void:
	if build_panel == null or build_toggle == null:
		return
	# 放置/拆除模式下，点建造按钮=取消（按钮文字由 update_ui 自动同步）
	if game.placing_type != "" or game.demolish_mode:
		game.cancel_placement()
		return
	build_panel.visible = not build_panel.visible

func _start_placing(type: String) -> void:
	game.placing_type = type
	game.demolish_mode = false
	if is_instance_valid(game.preview):
		game.preview.visible = true
		game.preview.set_build_type(type)
	build_panel.visible = false
	# 按钮文字"取消放置"由 update_ui 自动同步

func _start_demolish() -> void:
	game.demolish_mode = true
	game.placing_type = ""
	if is_instance_valid(game.preview):
		game.preview.visible = false
	build_panel.visible = false
	# 按钮文字"取消拆除"由 update_ui 自动同步

func _make_button(text: String) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 40)
	return b

func _make_menu_button(text: String) -> Button:
	var b: Button = _make_button(text)
	b.add_theme_font_size_override("font_size", 22)
	return b

# ---------- 放置/拆除输入 ----------
func _input(event: InputEvent) -> void:
	if game == null or match_root == null:
		return
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		mouse_world = _screen_to_world(mm.position)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			mouse_world = _screen_to_world(mb.position)
			_handle_click(mb.position)
	elif event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed:
			mouse_world = _screen_to_world(t.position)
			_handle_click(t.position)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event as InputEventScreenDrag
		mouse_world = _screen_to_world(d.position)

func _handle_click(screen_pos: Vector2) -> void:
	# 点到 UI 按钮则不处理（让按钮自己响应）
	if _is_on_ui_button(screen_pos):
		return
	if game.placing_type != "":
		game.place_at(GameManager.TEAM_PLAYER, game.placing_type, mouse_world)
	elif game.demolish_mode:
		var b: Building = _building_at(mouse_world)
		if b != null:
			game.start_demolish(GameManager.TEAM_PLAYER, b)
		else:
			game.toast(GameManager.TEAM_PLAYER, "这里没有可拆除的建筑")

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos

func _is_on_ui_button(pos: Vector2) -> bool:
	if build_toggle != null and build_toggle.visible and build_toggle.get_global_rect().has_point(pos):
		return true
	if barracks_btn != null and barracks_btn.visible and barracks_btn.get_global_rect().has_point(pos):
		return true
	# 攻击按钮区域（右下大按钮）
	if pos.x > 1060.0 and pos.y > 530.0:
		return true
	return false

func _building_at(world_pos: Vector2) -> Building:
	for node in get_tree().get_nodes_in_group("building"):
		var b: Building = node as Building
		if b != null and b.team == GameManager.TEAM_PLAYER:
			if world_pos.distance_to(b.global_position) < b.block_radius() + 10.0:
				return b
	return null

func _on_barracks_btn() -> void:
	# 切换最近兵营的模式（驻守↔跟随），只影响该兵营出的兵
	var b: Building = barracks_btn_target
	if b == null or not is_instance_valid(b) or b.btype != GameManager.TYPE_BARRACKS:
		return
	b.minion_mode = 1 if b.minion_mode == 0 else 0
	for node in get_tree().get_nodes_in_group("minion"):
		var m: Minion = node as Minion
		if m != null and m.source_barracks == b:
			m.mode = b.minion_mode
	barracks_btn.text = "跟随" if b.minion_mode == 1 else "驻守"

# ---------- 每帧更新 ----------
func update_ui(delta: float) -> void:
	if game == null:
		return
	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer <= 0.0:
			toast_label.text = ""
	if match_root == null:
		return
	res_label.text = "木%d 石%d 铁%d" % [game.wood_player, game.stone_player, game.iron_player]
	if game.player_base != null and is_instance_valid(game.player_base):
		base_hp_label.text = "大本营：%d/%d" % [int(game.player_base.hp), int(GameManager.HP_BASE)]
	else:
		base_hp_label.text = "大本营：未建"
	timer_label.text = "%d:%02d" % [int(game.match_time) / 60, int(game.match_time) % 60]
	if game.escalate_stage > 0:
		esc_label.text = "小兵强化 x%.2f" % game.escalate_multiplier
	# 放置模式：虚影跟随鼠标/手指，绿=可建 红=不可建；非放置模式隐藏
	if game.placing_type != "":
		if is_instance_valid(game.preview):
			game.preview.visible = true
			game.preview.global_position = mouse_world
			var ok: bool = game.can_place_at(GameManager.TEAM_PLAYER, game.placing_type, mouse_world)
			game.preview.set_color(Color(0.3, 0.9, 0.3, 0.4) if ok else Color(0.9, 0.3, 0.3, 0.4))
	elif is_instance_valid(game.preview):
		game.preview.visible = false
	# 同步建造按钮文字：放置/拆除模式显示"取消"，否则显示"建造"
	# （放置成功/取消后 game.placing_type 被清空，这里自动把按钮文字复原）
	if game.placing_type != "":
		build_toggle.text = "取消放置"
	elif game.demolish_mode:
		build_toggle.text = "取消拆除"
	elif build_panel.visible:
		build_toggle.text = "建造 ▾"
	else:
		build_toggle.text = "建造 ▸"
	_update_barracks_btn()

# ---------- 兵营旁交互按钮 ----------
func _update_barracks_btn() -> void:
	if barracks_btn == null:
		return
	if not is_instance_valid(game.player):
		barracks_btn.visible = false
		barracks_btn_target = null
		return
	# 找玩家最近的已完工己方兵营
	var nearest: Building = null
	var nearest_dist: float = 140.0
	for node in get_tree().get_nodes_in_group("building"):
		var b: Building = node as Building
		if b != null and b.btype == GameManager.TYPE_BARRACKS and b.team == GameManager.TEAM_PLAYER and b.is_finished:
			var d: float = game.player.global_position.distance_to(b.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = b
	if nearest == null:
		barracks_btn.visible = false
		barracks_btn_target = null
		return
	barracks_btn_target = nearest
	barracks_btn.text = "跟随" if nearest.minion_mode == 1 else "驻守"
	# 定位到兵营屏幕上方的位置
	var cam: Camera2D = get_viewport().get_camera_2d()
	var screen: Vector2 = get_viewport().get_canvas_transform() * nearest.global_position
	barracks_btn.position = Vector2(screen.x - 50.0, screen.y - 120.0)
	barracks_btn.size = Vector2(100, 44)
	barracks_btn.visible = true

func show_toast(msg: String) -> void:
	if toast_label == null:
		return
	toast_label.text = msg
	toast_timer = 2.5

# ---------- 结算 ----------
func show_result(winner: int, msg: String) -> void:
	result_panel = Control.new()
	result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(result_panel)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.1, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(bg)

	var res: Label = Label.new()
	if winner == GameManager.TEAM_PLAYER:
		res.text = "胜利！"
		res.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	else:
		res.text = "失败"
		res.add_theme_color_override("font_color", Color(0.95, 0.4, 0.4))
	res.add_theme_font_size_override("font_size", 56)
	res.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	res.position = Vector2(0, 200)
	res.size = Vector2(720, 70)
	result_panel.add_child(res)

	var detail: Label = Label.new()
	detail.text = msg
	detail.add_theme_font_size_override("font_size", 22)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.position = Vector2(0, 290)
	detail.size = Vector2(720, 40)
	result_panel.add_child(detail)

	var again: Button = _make_button("再来一局")
	again.position = Vector2(260, 380)
	again.size = Vector2(200, 60)
	again.pressed.connect(func() -> void:
		game.restart()
	)
	result_panel.add_child(again)

# ---------- 虚拟摇杆 ----------
class JoystickControl extends Control:
	## 动态浮动摇杆：在屏幕左半任意位置按下即生成摇杆（底座+摇杆头跟随），
	## 松手消失。用 _input 全局监听，不拦截右侧按钮点击。

	var player: Player = null
	var radius: float = 70.0
	var active: bool = false
	var touch_index: int = -1
	var base_pos: Vector2 = Vector2.ZERO
	var knob_pos: Vector2 = Vector2.ZERO
	var mouse_active: bool = false

	func _ready() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		player = _get_player()

	func _get_player() -> Player:
		var gm: GameManager = get_tree().current_scene as GameManager
		if gm != null:
			return gm.player
		return null

	func _input(event: InputEvent) -> void:
		player = _get_player()
		if event is InputEventScreenTouch:
			var t: InputEventScreenTouch = event as InputEventScreenTouch
			if t.pressed:
				if _is_left_zone(t.position) and touch_index == -1:
					touch_index = t.index
					active = true
					base_pos = t.position
					knob_pos = t.position
					_apply()
			else:
				if t.index == touch_index:
					touch_index = -1
					active = false
					_clear_move()
		elif event is InputEventScreenDrag:
			var d: InputEventScreenDrag = event as InputEventScreenDrag
			if active and d.index == touch_index:
				knob_pos = d.position
				_apply()
		elif event is InputEventMouseButton:
			var mb: InputEventMouseButton = event as InputEventMouseButton
			if mb.pressed:
				if _is_left_zone(mb.position) and not mouse_active:
					mouse_active = true
					base_pos = mb.position
					knob_pos = mb.position
					_apply()
			else:
				if mouse_active:
					mouse_active = false
					_clear_move()
		elif event is InputEventMouseMotion:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			if mouse_active:
				knob_pos = mm.position
				_apply()

	func _is_left_zone(pos: Vector2) -> bool:
		var vp: Vector2 = get_viewport().get_visible_rect().size
		return pos.x < vp.x * 0.5

	func _apply() -> void:
		if player == null:
			return
		var offset: Vector2 = knob_pos - base_pos
		if offset.length() > radius:
			offset = offset.normalized() * radius
		player.external_move = offset / radius
		queue_redraw()

	func _clear_move() -> void:
		if player != null:
			player.external_move = Vector2.ZERO
		queue_redraw()

	func _draw() -> void:
		if not active and not mouse_active:
			return
		draw_circle(base_pos, radius, Color(1.0, 1.0, 1.0, 0.14))
		draw_arc(base_pos, radius, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.5), 2.0)
		draw_circle(knob_pos, 26.0, Color(1.0, 1.0, 1.0, 0.45))
