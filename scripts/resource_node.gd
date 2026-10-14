class_name ResourceNode
extends StaticBody2D

## 可采集资源：木材 / 石头 / 铁矿。都有血量，被攻击采集；带兵一起打更快。
## 采空后约 1 分钟原位刷新。铁需大本营升级后才能采。

signal harvested(team: int, type: int, amount: int)

const TYPE_WOOD: int = 0
const TYPE_STONE: int = 1
const TYPE_IRON: int = 2

var game: Node = null
var node_type: int = 0
var hp: float = 9.0
var max_hp: float = 9.0
var yield_amount: int = 1
var hint_timer: float = 0.0

func _process(delta: float) -> void:
	if hint_timer > 0.0:
		hint_timer -= delta

func setup(g: Node, type: int, pos: Vector2) -> void:
	game = g
	node_type = type
	global_position = pos
	if type == TYPE_WOOD:
		hp = 9.0
		max_hp = 9.0
		yield_amount = randi_range(1, 3)
	elif type == TYPE_STONE:
		hp = 9.0
		max_hp = 9.0
		yield_amount = randi_range(1, 3)
	else:
		hp = 45.0
		max_hp = 45.0
		yield_amount = 1
	# 资源不加碰撞体：不阻挡玩家/敌人/小兵，但可被砍（挖取靠距离判定）
	collision_layer = 0
	collision_mask = 0
	add_to_group("resource_node")

func _draw() -> void:
	if node_type == TYPE_WOOD:
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, -18.0), Vector2(17.0, 12.0), Vector2(-17.0, 12.0)
		]), Color(0.13, 0.55, 0.18))
		draw_rect(Rect2(-4.0, 8.0, 8.0, 14.0), Color(0.45, 0.30, 0.12))
	elif node_type == TYPE_STONE:
		draw_circle(Vector2.ZERO, 17.0, Color(0.55, 0.50, 0.44))
		draw_circle(Vector2(5.0, -6.0), 6.0, Color(0.75, 0.70, 0.64))
	else:
		draw_circle(Vector2.ZERO, 17.0, Color(0.42, 0.42, 0.48))
		draw_circle(Vector2(4.0, -5.0), 6.0, Color(0.62, 0.62, 0.7))

func take_damage(amount: float, team: int) -> void:
	if node_type == TYPE_IRON and not game.can_mine_iron(team):
		if hint_timer <= 0.0:
			hint_timer = 2.0
			game.toast(team, "需升级大本营到2级才能采铁")
		return
	hp -= amount
	if hp <= 0.0:
		harvested.emit(team, node_type, yield_amount)
		var last_pos: Vector2 = global_position
		queue_free()
		if game != null:
			game.schedule_resource_respawn(node_type, last_pos)
