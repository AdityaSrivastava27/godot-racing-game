class_name AiCar
extends ArcadeCar

## Track-following opponent with stable center-line recovery
## and stronger anticipation for the sharp ends of the oval.

@export var look_ahead: float = 14.0
@export var lane_offset: float = 0.0
@export var corner_brake: float = 0.72
@export var steer_gain: float = 2.2
@export var recovery_strength: float = 2.8

var track: OvalTrack
var _progress: float = 0.0


func setup(p_track: OvalTrack, p_lane: float, p_max_speed: float, body_color: Color) -> void:
	track = p_track
	lane_offset = p_lane
	max_speed = p_max_speed
	set_body_color(body_color)
	_progress = track.estimate_progress(global_position)


func _get_drive_axes() -> Vector2:
	if track == null:
		return Vector2.ZERO

	_progress = track.estimate_progress(global_position)

	var center := track.get_track_point(_progress, 0.0)
	var normal := track.get_normal(_progress)

	var lateral_position := (global_position - center).dot(normal)
	var lateral_error := lane_offset - lateral_position

	var recovery := clampf(
		lateral_error * recovery_strength,
		-0.8,
		0.8
	)

	# The top and bottom of the ellipse have tighter curvature.
	# Look further ahead there so the car starts turning earlier.
	var look_distance := look_ahead

	var curve_factor := absf(sin(_progress))

	if curve_factor > 0.7:
		look_distance = 19.0
	elif curve_factor > 0.4:
		look_distance = 16.0
	else:
		look_distance = look_ahead

	# Still give the car enough look-ahead while recovering its lane.
	if absf(lateral_error) > 1.5:
		look_distance = maxf(look_distance, 11.0)

	var look_t := _progress + look_distance / track.average_radius()
	var target := track.get_track_point(look_t, lane_offset)

	target.y = global_position.y

	var to_target := target - global_position
	to_target.y = 0.0

	if to_target.length_squared() < 0.001:
		return Vector2(0.0, 1.0)

	to_target = to_target.normalized()

	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var right := forward.cross(Vector3.UP)

	var angle := atan2(
		right.dot(to_target),
		forward.dot(to_target)
	)

	var steer := clampf(
		angle * steer_gain + recovery,
		-1.0,
		1.0
	)

	var throttle := 1.0

	var turn_amount := absf(steer)

	# Start slowing slightly earlier for the sharper sections.
	if turn_amount > 0.45:
		throttle = lerpf(
			1.0,
			corner_brake,
			clampf(
				(turn_amount - 0.45) / 0.55,
				0.0,
				1.0
			)
		)

	# Avoid getting stuck behind another car.
	var blocker := _front_blocker_distance()

	if blocker < 6.0:
		throttle = minf(
			throttle,
			lerpf(0.35, 1.0, blocker / 6.0)
		)

	return Vector2(steer, throttle)


func _front_blocker_distance() -> float:
	var space := get_world_3d().direct_space_state

	if space == null:
		return 999.0

	var origin := global_position + Vector3.UP * 0.6
	var forward := -global_transform.basis.z

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + forward * 10.0
	)

	query.collide_with_areas = false
	query.collision_mask = 2
	query.exclude = [get_rid()]

	var hit := space.intersect_ray(query)

	if hit.is_empty():
		return 999.0

	return origin.distance_to(hit.position)
