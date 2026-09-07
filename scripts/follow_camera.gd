class_name FollowCamera
extends Camera3D

## Single chase camera. Stays behind the car and looks a short way down the road.

@export var target: Node3D
@export var follow_distance: float = 7.8
@export var follow_height: float = 3.4
@export var look_ahead: float = 7.5
@export var position_lerp: float = 7.0
@export var look_lerp: float = 11.0

var _look_point: Vector3


func snap_to_target() -> void:
	if target == null:
		return
	global_position = _desired_position()
	_look_point = _desired_look()
	look_at(_look_point)


func _physics_process(delta: float) -> void:
	if target == null:
		return

	var pos_t := 1.0 - exp(-position_lerp * delta)
	var look_t := 1.0 - exp(-look_lerp * delta)
	global_position = global_position.lerp(_desired_position(), pos_t)
	_look_point = _look_point.lerp(_desired_look(), look_t)
	if not _look_point.is_equal_approx(global_position):
		look_at(_look_point)


func _desired_position() -> Vector3:
	var back := target.global_transform.basis.z
	return target.global_position + back * follow_distance + Vector3.UP * follow_height


func _desired_look() -> Vector3:
	var forward := -target.global_transform.basis.z
	return target.global_position + forward * look_ahead + Vector3.UP * 0.7
