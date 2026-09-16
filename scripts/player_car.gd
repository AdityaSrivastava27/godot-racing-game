class_name PlayerCar
extends ArcadeCar


const BOMB_SCENE := preload("res://scenes/bomb.tscn")


@export var bomb_drop_distance: float = 2.9
@export var bomb_cooldown: float = 2.8


var _bomb_cooldown: float = 0.0


func _ready() -> void:
	super._ready()


func _process(delta: float) -> void:
	_bomb_cooldown = maxf(_bomb_cooldown - delta, 0.0)


func _get_drive_axes() -> Vector2:
	if not controls_enabled:
		return Vector2.ZERO

	var throttle := Input.get_axis("brake", "accelerate")
	var steer := Input.get_axis("steer_left", "steer_right")

	return Vector2(steer, throttle)


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return

	if event.is_action_pressed("drop_bomb") and not event.is_echo():
		_try_drop_bomb()
		get_viewport().set_input_as_handled()


func _try_drop_bomb() -> void:
	if _bomb_cooldown > 0.0:
		return

	var parent := get_parent()

	if parent == null:
		return

	_bomb_cooldown = bomb_cooldown

	var bomb := BOMB_SCENE.instantiate() as TrackBomb

	parent.add_child(bomb)

	var behind := global_transform.basis.z

	bomb.global_position = global_position \
		+ behind * bomb_drop_distance \
		+ Vector3.UP * 0.06

	bomb.setup(self)
