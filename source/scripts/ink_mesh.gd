class_name InkMesh
extends RefCounted
## Indexed mesh accumulator. Vertex colour carries the ink model:
## r = wind sway weight, g = tone (albedo), b = signal flag (berry), a = occlusion.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()
var idx := PackedInt32Array()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
## softbody: current piece centre (object space) and softness, carried in UV/UV2
var _sc := Vector3.ZERO
var _sk := 0.0
var soft := 1.0
var _mark_v := 0
var _mark_i := 0


func vert(p: Vector3, col: Color) -> int:
	v.append(p)
	n.append(Vector3.ZERO)
	c.append(col)
	uv.append(Vector2(_sc.x, _sc.z))
	uv2.append(Vector2(_sc.y, _sk))
	return v.size() - 1


## Adds a triangle whose front faces `want`. Godot's front faces wind clockwise,
## so the stored order is flipped relative to the right-handed normal.
func tri(i0: int, i1: int, i2: int, want: Vector3) -> void:
	var nn := (v[i1] - v[i0]).cross(v[i2] - v[i0])
	if nn.dot(want) < 0.0:
		var t := i1
		i1 = i2
		i2 = t
	idx.append(i0)
	idx.append(i2)
	idx.append(i1)


func quad(a: int, b: int, cc: int, d: int, want: Vector3) -> void:
	tri(a, b, cc, want)
	tri(a, cc, d, want)


## Start a piece; smooth() then computes normals only for triangles added since.
func begin() -> void:
	_sk = 0.0
	_mark_v = v.size()
	_mark_i = idx.size()


func smooth() -> void:
	var i := _mark_i
	while i < idx.size():
		var a := idx[i]
		var b := idx[i + 1]
		var d := idx[i + 2]
		var fn := (v[d] - v[a]).cross(v[b] - v[a])
		n[a] += fn
		n[b] += fn
		n[d] += fn
		i += 3
	for k in range(_mark_v, v.size()):
		var q := n[k]
		n[k] = q.normalized() if q.length_squared() > 1e-14 else Vector3.UP
	_mark_v = v.size()
	_mark_i = idx.size()


func is_empty() -> bool:
	return idx.is_empty()


func add_to(mesh: ArrayMesh, mat: Material) -> void:
	if idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


# ---------------------------------------------------------------- primitives

## Displaced ellipsoid with single-vertex poles. `rough` displaces radially.
func blob(center: Vector3, r: Vector3, lat: int, lon: int, col: Color, rough: float, rng: RandomNumberGenerator, sway_by_height := 0.0, sway_ref := 1.0) -> void:
	begin()
	_sc = center
	_sk = soft
	var jit := PackedFloat32Array()
	for k in range((lat - 1) * lon + 2):
		jit.append(1.0 + (rng.randf() * 2.0 - 1.0) * rough)
	var top := vert(center + Vector3(0, r.y * jit[0], 0), _sw(col, center + Vector3(0, r.y, 0), sway_by_height, sway_ref))
	var rows := []
	for y in range(1, lat):
		var ph := PI * float(y) / lat
		var row := []
		for x in lon:
			var th := TAU * float(x) / lon + (0.5 if y % 2 == 1 else 0.0) * TAU / lon
			var d := Vector3(sin(ph) * cos(th) * r.x, cos(ph) * r.y, sin(ph) * sin(th) * r.z)
			var p := center + d * jit[1 + (y - 1) * lon + x]
			row.append(vert(p, _sw(col, p, sway_by_height, sway_ref)))
		rows.append(row)
	var bot := vert(center - Vector3(0, r.y * jit[jit.size() - 1], 0), _sw(col, center - Vector3(0, r.y, 0), sway_by_height, sway_ref))
	var r0: Array = rows[0]
	for x in lon:
		var p1: int = r0[x]
		var p2: int = r0[(x + 1) % lon]
		tri(top, p1, p2, (v[top] + v[p1] + v[p2]) / 3.0 - center)
	for y in range(rows.size() - 1):
		var a: Array = rows[y]
		var b: Array = rows[y + 1]
		for x in lon:
			var i0: int = a[x]
			var i1: int = a[(x + 1) % lon]
			var i2: int = b[(x + 1) % lon]
			var i3: int = b[x]
			var cen := (v[i0] + v[i1] + v[i2] + v[i3]) * 0.25 - center
			quad(i0, i1, i2, i3, cen)
	var rl: Array = rows[rows.size() - 1]
	for x in lon:
		var p1: int = rl[x]
		var p2: int = rl[(x + 1) % lon]
		tri(bot, p1, p2, (v[bot] + v[p1] + v[p2]) / 3.0 - center)
	smooth()


func _sw(col: Color, p: Vector3, k: float, ref: float) -> Color:
	if k <= 0.0:
		return col
	return Color(clampf(col.r + k * clampf(p.y / ref, 0.0, 1.0), 0.0, 1.0), col.g, col.b, col.a)


## Faceted rock: same as blob but every triangle keeps its own vertices.
func facet_rock(center: Vector3, r: Vector3, lat: int, lon: int, col: Color, rough: float, rng: RandomNumberGenerator) -> void:
	var tmp := InkMesh.new()
	tmp.blob(center, r, lat, lon, col, rough, rng)
	begin()
	_sc = center
	_sk = soft * 0.6
	var i := 0
	while i < tmp.idx.size():
		var a := vert(tmp.v[tmp.idx[i]], col)
		var b := vert(tmp.v[tmp.idx[i + 1]], col)
		var d := vert(tmp.v[tmp.idx[i + 2]], col)
		idx.append(a)
		idx.append(b)
		idx.append(d)
		i += 3
	smooth()


## Tube along a polyline. radii/weights per point. Caps optional.
func tube(pts: PackedVector3Array, radii: PackedFloat32Array, weights: PackedFloat32Array, sides: int, col: Color, cap_end := false) -> void:
	begin()
	var count := pts.size()
	var t0 := (pts[1] - pts[0]).normalized()
	var nrm := Vector3.UP if absf(t0.y) < 0.9 else Vector3.RIGHT
	nrm = (nrm - t0 * nrm.dot(t0)).normalized()
	var rings := []
	for i in count:
		var tg: Vector3
		if i == 0:
			tg = pts[1] - pts[0]
		elif i == count - 1:
			tg = pts[i] - pts[i - 1]
		else:
			tg = pts[i + 1] - pts[i - 1]
		tg = tg.normalized()
		nrm = (nrm - tg * nrm.dot(tg)).normalized()
		var bn := tg.cross(nrm)
		var ring := []
		var cc := Color(weights[i], col.g, col.b, col.a)
		for s in sides:
			var a := TAU * float(s) / sides
			ring.append(vert(pts[i] + (nrm * cos(a) + bn * sin(a)) * radii[i], cc))
		rings.append(ring)
	for i in range(count - 1):
		var ra: Array = rings[i]
		var rb: Array = rings[i + 1]
		var mid := (pts[i] + pts[i + 1]) * 0.5
		for s in sides:
			var i0: int = ra[s]
			var i1: int = ra[(s + 1) % sides]
			var i2: int = rb[(s + 1) % sides]
			var i3: int = rb[s]
			quad(i0, i1, i2, i3, (v[i0] + v[i2]) * 0.5 - mid)
	if cap_end:
		var last: Array = rings[count - 1]
		var tip_dir := (pts[count - 1] - pts[count - 2]).normalized()
		var tip := vert(pts[count - 1] + tip_dir * radii[count - 1] * 0.4, Color(weights[count - 1], col.g, col.b, col.a))
		for s in sides:
			tri(tip, last[s], last[(s + 1) % sides], tip_dir)
	smooth()


## A curved, cupped surface (petal or leaf). Double-sided material expected.
func petal(base: Vector3, dir: Vector3, up: Vector3, length: float, width: float, cup: float, col: Color, w0: float, w1: float) -> void:
	begin()
	var side := dir.cross(up).normalized()
	var nu := 5
	var nv := 3
	var grid := []
	for iu in nu:
		var u := float(iu) / (nu - 1)
		var shape := pow(sin(PI * (0.12 + 0.88 * u)), 0.75)
		var row := []
		for iv in nv:
			var s := (float(iv) / (nv - 1) - 0.5) * width * shape
			var lift := cup * u * u * length + absf(s) * cup * 0.9
			var p := base + dir * (u * length) + side * s + up * lift
			row.append(vert(p, Color(lerpf(w0, w1, u), col.g, col.b, col.a)))
		grid.append(row)
	for iu in nu - 1:
		var a: Array = grid[iu]
		var b: Array = grid[iu + 1]
		for iv in nv - 1:
			quad(a[iv], a[iv + 1], b[iv + 1], b[iv], up)
	smooth()


## Tapered blade (triangle strip). Double-sided material expected.
func blade(base: Vector3, lean: Vector3, h: float, w: float, col: Color, w_base: float) -> void:
	begin()
	var segs := 4
	var side := lean.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var face := side.cross(Vector3.UP)
	var prev_l := -1
	var prev_r := -1
	for i in segs + 1:
		var t := float(i) / segs
		var p := base + Vector3.UP * (h * t) + lean * (t * t * h * 0.55)
		var ww := w * (1.0 - t) + 0.001
		var cc := Color(w_base + (1.0 - w_base) * t, col.g, col.b, col.a)
		var l := vert(p - side * ww * 0.5, cc)
		var r := vert(p + side * ww * 0.5, cc)
		if prev_l >= 0:
			quad(prev_l, prev_r, r, l, face)
		prev_l = l
		prev_r = r
	smooth()
