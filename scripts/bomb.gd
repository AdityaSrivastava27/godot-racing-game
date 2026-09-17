class_name TrackBomb
extends Area3D

## Mine left on the road. Detonates on the first car that touches it.

@export var lifetime: float = 7.0
@export var dropper_safe_radius: float = 3.4

var _dropper: Node3D
var _dropper_clear: bool = false
var _spent: bool = false
var _age: float = 0.0

@onready var _light: OmniLight3D = $Light
@onready var _visuals: Node3D = $Visuals


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func setup(dropper: Node3D) -> void:
	_dropper = dropper


func _physics_process(delta: float) -> void:
	_age += delta
	_update_dropper_clear()

	var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(_age * 8.0))
	_light.light_energy = pulse * 2.4
	_visuals.position.y = 0.02 * sin(_age * 6.0)

	if _age >= lifetime:
		queue_free()


func _update_dropper_clear() -> void:
	if _dropper_clear:
		return

	if _dropper == null or not is_instance_valid(_dropper):
		_dropper_clear = true
		return

	var offset := _dropper.global_position - global_position
	offset.y = 0.0

	if offset.length() > dropper_safe_radius:
		_dropper_clear = true


func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return

	if body == _dropper and not _dropper_clear:
		return

	if body is ArcadeCar:
		call_deferred("_detonate", body as ArcadeCar)


func _on_body_exited(body: Node3D) -> void:
	if body == _dropper:
		_dropper_clear = true


func _detonate(trigger: ArcadeCar) -> void:
	if _spent:
		return

	_spent = true

	var hit: Array[ArcadeCar] = []

	if trigger != null:
		hit.append(trigger)

	# Collect overlapping cars while monitoring is still enabled.
	for body in get_overlapping_bodies():
		var car := body as ArcadeCar

		if car != null and not hit.has(car):
			if car == _dropper and not _dropper_clear:
				continue

			hit.append(car)

	# Disable monitoring only after collecting the overlapping bodies.
	monitoring = false

	for car in hit:
		car.apply_bomb_hit(global_position)

	queue_free()