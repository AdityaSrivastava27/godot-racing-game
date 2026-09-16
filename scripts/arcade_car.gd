class_name ArcadeCar
extends CharacterBody3D

## Shared arcade driving: authored forward speed + blended heading.

@export var max_speed: float = 34.0
@export var max_reverse_speed: float = 10.0
@export var acceleration: float = 24.0
@export var brake_force: float = 38.0
@export var reverse_acceleration: float = 16.0
@export var coast_friction: float = 7.0
@export var turn_speed: float = 1.9
@export var grip: float = 9.0
@export var gravity: float = 24.0
@export var visual_lean: float = 0.18

var controls_enabled: bool = false
var signed_speed: float = 0.0
var _wheel_spin: float = 0.0

@onready var _visuals: Node3D = $Visuals
@onready var _wheel_fl: Node3D = $Visuals/WheelFL
@onready var _wheel_fr: Node3D = $Visuals/WheelFR
@onready var _wheel_rl: Node3D = $Visuals/WheelRL
@onready var _wheel_rr: Node3D = $Visuals/WheelRR

const _WHEEL_RADIUS := 0.32


func _ready() -> void:
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	collision_layer = 2
	collision_mask = 1 | 2


func _physics_process(delta: float) -> void:
	var axes := Vector2.ZERO
	if controls_enabled:
		axes = _get_drive_axes()

	_apply_speed(axes.y, delta)
	_apply_steering(axes.x, delta)
	_apply_arcade_velocity(delta)
	move_and_slide()
	_update_visuals(axes.x, axes.y, delta)


## Returns (steer, throttle) in [-1, 1]. Steer: -1 left, +1 right. Throttle: -1 brake/reverse, +1 accelerate.
func _get_drive_axes() -> Vector2:
	return Vector2.ZERO


func get_speed_kph() -> float:
	return absf(signed_speed) * 3.6


func set_body_color(color: Color) -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = color
	body_mat.metallic = 0.35
	body_mat.roughness = 0.38
	for path in ["Visuals/Body", "Visuals/Nose"]:
		var mesh := get_node_or_null(path) as MeshInstance3D
		if mesh:
			mesh.material_override = body_mat


func _apply_speed(throttle: float, delta: float) -> void:
	if throttle > 0.0:
		signed_speed += acceleration * throttle * delta
	elif throttle < 0.0:
		if signed_speed > 0.4:
			signed_speed += brake_force * throttle * delta
		else:
			signed_speed += reverse_acceleration * throttle * delta
	else:
		signed_speed = move_toward(signed_speed, 0.0, coast_friction * delta)

	signed_speed = clampf(signed_speed, -max_reverse_speed, max_speed)


func _apply_steering(steer: float, delta: float) -> void:
	if is_zero_approx(steer) or absf(signed_speed) < 0.35:
		return

	var speed_ratio := clampf(absf(signed_speed) / max_speed, 0.0, 1.0)
	var steer_scale := lerpf(1.35, 0.62, speed_ratio)
	var yaw := steer * turn_speed * steer_scale * signf(signed_speed) * delta
	rotate_y(-yaw)


func _apply_arcade_velocity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var forward := -global_transform.basis.z
	var desired := forward * signed_speed
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var blend := clampf(grip * delta, 0.0, 1.0)
	planar = planar.lerp(desired, blend)
	velocity.x = planar.x
	velocity.z = planar.z


func _update_visuals(steer: float, throttle: float, delta: float) -> void:
	var speed_ratio := clampf(absf(signed_speed) / max_speed, 0.0, 1.0)
	var lean := -steer * visual_lean * speed_ratio
	var squat := -throttle * 0.05
	_visuals.rotation.z = lerp_angle(_visuals.rotation.z, lean, 1.0 - exp(-10.0 * delta))
	_visuals.rotation.x = lerp_angle(_visuals.rotation.x, squat, 1.0 - exp(-8.0 * delta))

	_wheel_spin += (signed_speed / _WHEEL_RADIUS) * delta
	var steer_yaw := -steer * 0.45
	_wheel_fl.rotation = Vector3(_wheel_spin, steer_yaw, 0.0)
	_wheel_fr.rotation = Vector3(_wheel_spin, steer_yaw, 0.0)
	_wheel_rl.rotation = Vector3(_wheel_spin, 0.0, 0.0)
	_wheel_rr.rotation = Vector3(_wheel_spin, 0.0, 0.0)
