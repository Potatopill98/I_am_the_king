class_name ResourceDrop
extends Area2D

## 掉在地上的材料：建筑被打断时掉落，主角/AI 走过可捡起。

var game: GameManager
var res_type: int = 0
var amount: int = 1
var life: float = 30.0
var collected: bool = false

func setup(g: GameManager, type: int, amt: int, pos: Vector2) -> void:
	game = g
	res_type = type
	amount = amt
	global_position = pos
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	add_child(shape)
	# 掩码覆盖玩家层(2)与AI层(4)，踩上去才触发拾取
	collision_mask = 6
	body_entered.connect(_on_body_entered)
	add_to_group("drop")

func _draw() -> void:
	var col: Color = Color(0.6, 0.42, 0.2)
	if res_type == 1:
		col = Color(0.6, 0.6, 0.6)
	elif res_type == 2:
		col = Color(0.55, 0.55, 0.72)
	draw_circle(Vector2.ZERO, 8.0, col)

func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if collected:
		return
	if body is Player:
		collected = true
		game.credit(GameManager.TEAM_PLAYER, res_type, amount)
		queue_free()
	elif body is AiHero:
		collected = true
		game.credit(GameManager.TEAM_AI, res_type, amount)
		queue_free()
