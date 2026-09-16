class_name AiCar
extends ArcadeCar

## Simple track-following opponent: steers toward a look-ahead point on the oval.

@export var look_ahead: float = 14.0
@export var lane_offset: float = 0.0
@export var corner_brake: float = 0.55
@export var steer_gain: float = 2.4

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
	var look_t := _progress + look_ahead / track.average_radius()
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
	var angle := atan2(right.dot(to_target), forward.dot(to_target))
	var steer := clampf(angle * steer_gain, -1.0, 1.0)

	var throttle := 1.0
	var turn_amount := absf(steer)
	if turn_amount > 0.25:
		throttle = lerpf(1.0, corner_brake, clampf((turn_amount - 0.25) / 0.75, 0.0, 1.0))

	# Ease off if packed against another car ahead.
	var blocker := _front_blocker_distance()
	if blocker < 8.0:
		throttle = minf(throttle, lerpf(0.15, 1.0, blocker / 8.0))
		steer += signf(lane_offset) * 0.25 * (1.0 - blocker / 8.0)
		steer = clampf(steer, -1.0, 1.0)

	return Vector2(steer, throttle)


func _front_blocker_distance() -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return 999.0

	var origin := global_position + Vector3.UP * 0.6
	var forward := -global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + forward * 10.0)
	query.collide_with_areas = false
	query.collision_mask = 2
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return 999.0
	return origin.distance_to(hit.position)
