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
@export var impact_push: float = 1.05
@export var impact_restitution: float = 0.22
@export var knock_decay: float = 12.0
@export var spin_recovery: float = 2.8
## Heavier cars keep their line and shove the lighter one aside.
@export var impact_mass: float = 1.0
## Scales everything a collision does to this car: speed loss, spin and lost control.
@export var impact_stability: float = 1.0

var controls_enabled: bool = false
var signed_speed: float = 0.0
var _wheel_spin: float = 0.0
var _hit_lock: float = 0.0
var _knock: Vector3 = Vector3.ZERO
var _spin: float = 0.0
var _jolt: float = 0.0
var _impact_cooldown: float = 0.0

static var _pair_frame: int = -1
static var _resolved_pairs: Dictionary = {}

@onready var _visuals: Node3D = $Visuals
@onready var _wheel_fl: Node3D = $Visuals/WheelFL
@onready var _wheel_fr: Node3D = $Visuals/WheelFR
@onready var _wheel_rl: Node3D = $Visuals/WheelRL
@onready var _wheel_rr: Node3D = $Visuals/WheelRR

const _WHEEL_RADIUS := 0.32
## Contacts closing slower than this are panels rubbing, not a hit worth an impulse.
const _RUB_CLOSING := 1.2
const _RUB_SEPARATION := 2.8
const _RUB_RATE := 10.0
const _IMPACT_COOLDOWN := 0.14
const _MAX_IMPACT_SPEED := 16.0
const _MAX_KNOCK := 18.0
const _MAX_SPIN := 2.6
const _DEPENETRATE := 0.08


func _ready() -> void:
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(50.0)
	safe_margin = 0.06
	max_slides = 8
	collision_layer = 2
	collision_mask = 1 | 2


func _physics_process(delta: float) -> void:
	_impact_cooldown = maxf(_impact_cooldown - delta, 0.0)

	var axes := Vector2.ZERO
	if controls_enabled:
		axes = _get_drive_axes()
	if _hit_lock > 0.0:
		_hit_lock = maxf(_hit_lock - delta, 0.0)
		# Steering goes vague and the power cannot come straight back on.
		axes.x *= 0.35
		axes.y = minf(axes.y, 0.25)

	_apply_speed(axes.y, delta)
	_apply_steering(axes.x, delta)
	_apply_impact_spin(delta)
	_apply_arcade_velocity(delta)
	move_and_slide()
	_resolve_car_contacts(delta)
	_update_visuals(axes.x, axes.y, delta)


## Returns (steer, throttle) in [-1, 1]. Steer: -1 left, +1 right. Throttle: -1 brake/reverse, +1 accelerate.
func _get_drive_axes() -> Vector2:
	return Vector2.ZERO


func get_speed_kph() -> float:
	return absf(signed_speed) * 3.6


func apply_bomb_hit(from_position: Vector3) -> void:
	signed_speed *= 0.18

	var away := global_position - from_position
	away.y = 0.0

	if away.length_squared() < 0.001:
		away = global_transform.basis.z

	away = away.normalized()

	velocity.x += away.x * 12.0
	velocity.z += away.z * 12.0

	var forward := -global_transform.basis.z
	rotate_y(signf(forward.cross(away).y) * 0.65)

	_hit_lock = 0.75


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


## Impact spin bleeds off over time instead of snapping the heading, which keeps a hit readable.
func _apply_impact_spin(delta: float) -> void:
	if is_zero_approx(_spin):
		_spin = 0.0
		return
	rotate_y(_spin * delta)
	_spin = move_toward(_spin, 0.0, spin_recovery * delta)


func _apply_arcade_velocity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	var desired := _planar_forward() * signed_speed
	var planar := Vector3(velocity.x, 0.0, velocity.z) - Vector3(_knock.x, 0.0, _knock.z)
	var grip_scale := 0.5 if _hit_lock > 0.0 else 1.0
	var blend := clampf(grip * grip_scale * delta, 0.0, 1.0)
	planar = planar.lerp(desired, blend)
	var decay := knock_decay * (0.6 if _hit_lock > 0.0 else 1.0)
	_knock = _knock.move_toward(Vector3.ZERO, decay * delta)
	velocity.x = planar.x + _knock.x
	velocity.z = planar.z + _knock.z


func _resolve_car_contacts(delta: float) -> void:
	var frame := Engine.get_physics_frames()
	if _pair_frame != frame:
		_pair_frame = frame
		_resolved_pairs.clear()

	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var other := hit.get_collider() as ArcadeCar
		if other == null:
			continue

		var key := "%d_%d" % [mini(get_instance_id(), other.get_instance_id()), maxi(get_instance_id(), other.get_instance_id())]
		if _resolved_pairs.has(key):
			continue
		_resolved_pairs[key] = true
		_resolve_pair(other, hit, delta)


func _resolve_pair(other: ArcadeCar, hit: KinematicCollision3D, delta: float) -> void:
	var normal := _contact_normal(hit, other)
	if normal == Vector3.ZERO:
		return

	var relative_velocity := Vector3(
		velocity.x - other.velocity.x,
		0.0,
		velocity.z - other.velocity.z
	)

	var closing := -relative_velocity.dot(normal)

	if closing < _RUB_CLOSING:
		_ease_apart(normal, 0.5, delta)
		other._ease_apart(-normal, 0.5, delta)
		return

	if _impact_cooldown > 0.0 or other._impact_cooldown > 0.0:
		return

	_impact_cooldown = _IMPACT_COOLDOWN
	other._impact_cooldown = _IMPACT_COOLDOWN

	var self_forward := _planar_forward()
	var other_forward := other._planar_forward()

	var self_into_other := maxf(-self_forward.dot(normal), 0.0)
	var other_into_self := maxf(other_forward.dot(normal), 0.0)

	var total_impact := closing * impact_push

	if self_into_other >= other_into_self:
		# This car is doing most of the hitting.
		_receive_impact(
			normal,
			closing,
			0.35,
			self_into_other,
			hit.get_position(),
			false
		)

		other._receive_impact(
			-normal,
			closing,
			0.65,
			self_into_other,
			hit.get_position(),
			true
		)

		velocity -= normal * total_impact * 0.25
		other.velocity += normal * total_impact * 1.5

		other.signed_speed = clampf(
		other.signed_speed + closing * 0.35,
		-other.max_reverse_speed,
		other.max_speed
		)
	else:
		# The other car is doing most of the hitting.
		other._receive_impact(
			-normal,
			closing,
			0.35,
			other_into_self,
			hit.get_position(),
			false
		)

		_receive_impact(
			normal,
			closing,
			0.65,
			other_into_self,
			hit.get_position(),
			true
		)

		other.velocity -= normal * total_impact * 0.25
		velocity += normal * total_impact * 0.75

		other.signed_speed = maxf(other.signed_speed - closing * 0.20, 0.0)
		signed_speed = clampf(
			signed_speed + closing * 0.15,
			-max_reverse_speed,
			max_speed
		)

## push_dir points away from the other car, share is this car's slice of the shunt and
## aggression is how nose-on it was. got_rear_ended means this car was bumped from behind.
## Everything scales by impact_stability, so a stable car only gets nudged where a light
## one gets slowed, shoved and spun.
func _receive_impact(
	push_dir: Vector3,
	closing: float,
	share: float,
	aggression: float,
	contact: Vector3,
	got_rear_ended: bool
) -> void:
	var soak := share / maxf(impact_stability, 0.05)
	var take := soak * (1.0 - 0.7 * aggression)

	var impulse := closing * (1.0 + impact_restitution) * impact_push * soak
	# Victims get a firm shove; aggressors mostly keep their line.
	var push_boost := 1.15 if aggression < 0.25 else 0.85
	_add_knock(push_dir * minf(impulse * push_boost, _MAX_IMPACT_SPEED))

	# A shove from behind punts the car along; a nose or flank hit scrubs speed off instead.
	var along := clampf(_planar_forward().dot(push_dir), -1.0, 1.0)
	var scrub := 0.55 if along < 0.15 else -0.2
	var speed_change := -closing * take * 0.35
	if got_rear_ended:
		speed_change = maxf(speed_change, closing * take * 0.2)
	signed_speed = clampf(signed_speed + speed_change, -max_reverse_speed, max_speed)

	# Torque about the contact arm, so corner / flank hits twist the car off line.
	var arm := contact - global_position
	var torque := (arm.z * push_dir.x - arm.x * push_dir.z) * closing * 0.24 * take
	if absf(along) < 0.45:
		torque *= 1.35
	_add_spin(torque)

	# Firm hits destabilize the lighter car: vague steering and capped throttle for a beat.
	if take > 0.18 and closing > 2.6:
		var scramble := minf(0.1 + take * closing * 0.07, 0.85)
		if got_rear_ended:
			scramble *= 0.55
		_hit_lock = maxf(_hit_lock, scramble)

	# Body roll is cosmetic, so it reads on every impact regardless of how stable the car is.
	_jolt = clampf(_jolt - push_dir.dot(global_transform.basis.x) * closing * 0.04 * share, -0.45, 0.45)


## Contact too gentle to be a hit: creep the pair apart at a fixed rate so cars grinding
## panels slide past each other instead of stacking up an impulse and pinging away.
func _ease_apart(push_dir: Vector3, share: float, delta: float) -> void:
	var yield_factor := share / maxf(impact_stability, 0.05)
	var separation_speed := _RUB_SEPARATION * yield_factor * 2.0

	var current_speed := Vector3(_knock.x, 0.0, _knock.z).dot(push_dir)

	if current_speed < separation_speed:
		var push := separation_speed - current_speed
		_add_knock(push_dir * push)


func _contact_normal(hit: KinematicCollision3D, other: ArcadeCar) -> Vector3:
	var normal := hit.get_normal()
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		normal = global_position - other.global_position
		normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return Vector3.ZERO
	return normal.normalized()


func _planar_forward() -> Vector3:
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _add_knock(push: Vector3) -> void:
	_knock.x = clampf(_knock.x + push.x, -_MAX_KNOCK, _MAX_KNOCK)
	_knock.z = clampf(_knock.z + push.z, -_MAX_KNOCK, _MAX_KNOCK)


func _add_spin(rate: float) -> void:
	_spin = clampf(_spin + rate, -_MAX_SPIN, _MAX_SPIN)


func _update_visuals(steer: float, throttle: float, delta: float) -> void:
	var speed_ratio := clampf(absf(signed_speed) / max_speed, 0.0, 1.0)
	var lean := -steer * visual_lean * speed_ratio + _jolt
	var squat := -throttle * 0.05
	_visuals.rotation.z = lerp_angle(_visuals.rotation.z, lean, 1.0 - exp(-10.0 * delta))
	_visuals.rotation.x = lerp_angle(_visuals.rotation.x, squat, 1.0 - exp(-8.0 * delta))
	_jolt = move_toward(_jolt, 0.0, 1.2 * delta)

	_wheel_spin += (signed_speed / _WHEEL_RADIUS) * delta
	var steer_yaw := -steer * 0.45
	_wheel_fl.rotation = Vector3(_wheel_spin, steer_yaw, 0.0)
	_wheel_fr.rotation = Vector3(_wheel_spin, steer_yaw, 0.0)
	_wheel_rl.rotation = Vector3(_wheel_spin, 0.0, 0.0)
	_wheel_rr.rotation = Vector3(_wheel_spin, 0.0, 0.0)
