@tool
class_name OvalTrack
extends Node3D

## Builds a closed oval circuit: driveable ground, asphalt ribbon, lane marks, barriers.

@export var radius_x: float = 52.0
@export var radius_z: float = 36.0
@export var road_width: float = 14.0
@export var segments: int = 80
@export var barrier_height: float = 1.15
@export var barrier_thickness: float = 0.45

const _ROAD_Y := 0.04
const _LINE_Y := 0.055


func _ready() -> void:
	_clear_generated()
	_build()


func _clear_generated() -> void:
	for child in get_children():
		remove_child(child)
		child.free()


func get_start_transform() -> Transform3D:
	var point := _oval_point(0.0)
	var tangent := _oval_tangent(0.0)
	point.y = 0.06
	return Transform3D(Basis.looking_at(tangent, Vector3.UP), point)


func _build() -> void:
	_add_ground()
	_add_road_and_lines()
	_add_barriers()
	_add_start_line()


func _oval_point(t: float) -> Vector3:
	return Vector3(radius_x * cos(t), 0.0, radius_z * sin(t))


func _oval_tangent(t: float) -> Vector3:
	return Vector3(-radius_x * sin(t), 0.0, radius_z * cos(t)).normalized()


func _oval_normal(t: float) -> Vector3:
	return _oval_tangent(t).cross(Vector3.UP).normalized()


func _add_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius_x * 2.0 + 80.0, 0.4, radius_z * 2.0 + 80.0)
	collision.shape = box
	collision.position.y = -0.2
	body.add_child(collision)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Grass"
	var plane := PlaneMesh.new()
	plane.size = Vector2(box.size.x, box.size.z)
	mesh_instance.mesh = plane
	mesh_instance.position.y = 0.0
	mesh_instance.material_override = load("res://materials/grass.tres")
	body.add_child(mesh_instance)
	add_child(body)


func _add_road_and_lines() -> void:
	var half_w := road_width * 0.5
	var asphalt := load("res://materials/asphalt.tres") as Material
	var line_mat := load("res://materials/lane_line.tres") as Material

	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edges := SurfaceTool.new()
	edges.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in segments:
		var t0 := float(i) / float(segments) * TAU
		var t1 := float(i + 1) / float(segments) * TAU
		_add_strip(road, t0, t1, -half_w, half_w, _ROAD_Y, 1.0)
		_add_strip(edges, t0, t1, -half_w + 0.15, -half_w + 0.45, _LINE_Y, 8.0)
		_add_strip(edges, t0, t1, half_w - 0.45, half_w - 0.15, _LINE_Y, 8.0)
		if i % 2 == 0:
			_add_strip(edges, t0, t1, -0.12, 0.12, _LINE_Y, 4.0)

	_commit_mesh("Road", road, asphalt)
	_commit_mesh("LaneLines", edges, line_mat)


func _add_barriers() -> void:
	var white := load("res://materials/barrier.tres") as Material
	var red := load("res://materials/barrier_red.tres") as Material
	var half_w := road_width * 0.5
	var offsets: Array[float] = [
		-half_w - barrier_thickness * 0.5,
		half_w + barrier_thickness * 0.5,
	]

	for side: float in offsets:
		for i in segments:
			var t0 := float(i) / float(segments) * TAU
			var t1 := float(i + 1) / float(segments) * TAU
			var p0 := _oval_point(t0) + _oval_normal(t0) * side
			var p1 := _oval_point(t1) + _oval_normal(t1) * side
			var mid := (p0 + p1) * 0.5
			var length := maxf(p0.distance_to(p1), 0.2)
			var tangent := (p1 - p0).normalized()

			var body := StaticBody3D.new()
			body.name = "Barrier_%d_%d" % [1 if side > 0.0 else 0, i]
			body.position = Vector3(mid.x, barrier_height * 0.5, mid.z)
			body.basis = Basis.looking_at(tangent, Vector3.UP)

			var collision := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(barrier_thickness, barrier_height, length + 0.08)
			collision.shape = box
			body.add_child(collision)

			var mesh_instance := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = box.size
			mesh_instance.mesh = mesh
			mesh_instance.material_override = red if i % 2 == 0 else white
			body.add_child(mesh_instance)
			add_child(body)


func _add_start_line() -> void:
	var t := 0.0
	var center := _oval_point(t)
	var tangent := _oval_tangent(t)
	var normal := _oval_normal(t)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "StartLine"
	var box := BoxMesh.new()
	box.size = Vector3(road_width - 0.8, 0.03, 1.6)
	mesh_instance.mesh = box
	mesh_instance.position = center + Vector3(0.0, _LINE_Y + 0.02, 0.0)
	mesh_instance.basis = Basis.looking_at(tangent, Vector3.UP)
	mesh_instance.material_override = load("res://materials/lane_line.tres")
	add_child(mesh_instance)

	# Visual start gates on the inner and outer edges.
	for side_sign in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.25, 2.4, 0.25)
		post.mesh = post_mesh
		post.position = center + normal * (road_width * 0.5 * side_sign) + Vector3(0.0, 1.2, 0.0)
		post.material_override = load("res://materials/barrier_red.tres")
		add_child(post)


func _add_strip(
	st: SurfaceTool,
	t0: float,
	t1: float,
	inner: float,
	outer: float,
	y: float,
	v_tile: float
) -> void:
	var a := _oval_point(t0) + _oval_normal(t0) * inner + Vector3(0.0, y, 0.0)
	var b := _oval_point(t0) + _oval_normal(t0) * outer + Vector3(0.0, y, 0.0)
	var c := _oval_point(t1) + _oval_normal(t1) * outer + Vector3(0.0, y, 0.0)
	var d := _oval_point(t1) + _oval_normal(t1) * inner + Vector3(0.0, y, 0.0)
	var u0 := (inner + road_width * 0.5) / road_width
	var u1 := (outer + road_width * 0.5) / road_width
	var v0 := t0 / TAU * v_tile
	var v1 := t1 / TAU * v_tile
	_add_quad(st, a, b, c, d, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1))


func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2,
	uv_d: Vector2
) -> void:
	st.set_normal(Vector3.UP)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_b)
	st.add_vertex(b)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_a)
	st.add_vertex(a)
	st.set_uv(uv_c)
	st.add_vertex(c)
	st.set_uv(uv_d)
	st.add_vertex(d)


func _commit_mesh(mesh_name: String, st: SurfaceTool, material: Material) -> void:
	st.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = material
	add_child(mesh_instance)
