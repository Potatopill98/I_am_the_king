class_name Projectile
extends Area2D

## 箭矢（主角弓 / 防御塔射出）：直线飞行，命中敌方单位/建筑造成伤害后消失。

var game: GameManager
var team: int = 0
var dir: Vector2 = Vector2.RIGHT
var speed: float = 380.0
var damage: float = 3.0
var life: float = 1.8
var hit_once: bool = false

func setup(g: GameManager, t: int, pos: Vector2, direction: Vector2, spd: float, dmg: float) -> void:
	game = g
	team = t
	global_position = pos
	dir = direction.normalized()
	speed = spd
	damage = dmg
	var shape: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 6.0
	shape.shape = circle
	add_child(shape)
	# 箭掩码须覆盖能命中的层：大本营(1)+敌方单位+野怪(16)+敌方墙
	if t == 0:
		collision_mask = 85  # 1|4|16|64
	else:
		collision_mask = 51  # 1|2|16|32
	body_entered.connect(_on_body_entered)
	add_to_group("projectile")

func _draw() -> void:
	draw_rect(Rect2(-8.0, -1.0, 16.0, 2.0), Color(0.9, 0.85, 0.5))

func _physics_process(delta: float) -> void:
	if game != null and game.game_over:
		queue_free()
		return
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	position += dir * speed * delta

func _on_body_entered(body: Node) -> void:
	if hit_once:
		return
	var enemy_team_name: String = "team%d" % (1 - team)
	var is_wild: bool = body.is_in_group("wild")
	if (body.is_in_group(enemy_team_name) or is_wild) and body.has_method("take_damage"):
		body.call("take_damage", damage, team)
		# 远程轻轻微击退
		if body.has_method("_apply_knockback"):
			var kb: float = 60.0
			body.call("_apply_knockback", (body.global_position - global_position).normalized(), kb)
		hit_once = true
		queue_free()
