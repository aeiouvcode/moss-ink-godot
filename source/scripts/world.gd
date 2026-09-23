class_name InkWorld
extends Node3D
## Procedural island: layered soil, rocks, a fallen log and a field of plants.
## Everything is deterministic from the seed string.

const NS := 72          # angular samples around the island
const NR := 14          # rings on the top surface
const RX := 3.3
const RZ := 2.4

var mat_thick: ShaderMaterial
var mat_thin: ShaderMaterial

var rng := RandomNumberGenerator.new()
var n_lo := FastNoiseLite.new()
var n_hi := FastNoiseLite.new()
var n_rim := FastNoiseLite.new()

var log_a := Vector3.ZERO
var log_b := Vector3.ZERO
var log_r := 0.22
var rocks: Array = []          # [Vector3, float]
var taken: Array = []          # [Vector2, float]
var static_node: MeshInstance3D
var plants: Node3D
var grown := 0


func setup(thick: ShaderMaterial, thin: ShaderMaterial) -> void:
	mat_thick = thick
	mat_thin = thin
	static_node = MeshInstance3D.new()
	add_child(static_node)
	plants = Node3D.new()
	add_child(plants)


static func hash_str(s: String) -> int:
	var h := 2166136261
	for ch in s.to_utf8_buffer():
		h = (h ^ ch) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


# ------------------------------------------------------------------ terrain

func outline(th: float) -> float:
	var c := cos(th)
	var s := sin(th)
	var e := 1.0 / sqrt((c / RX) * (c / RX) + (s / RZ) * (s / RZ))
	return e * (1.0 + 0.075 * n_rim.get_noise_2d(c * 60.0, s * 60.0) + 0.03 * n_rim.get_noise_2d(c * 190.0, s * 190.0))


func rho(x: float, z: float) -> float:
	return Vector2(x, z).length() / outline(atan2(z, x))


func height(x: float, z: float) -> float:
	var e := rho(x, z)
	var h := 0.12 + 0.15 * n_lo.get_noise_2d(x, z) + 0.035 * n_hi.get_noise_2d(x, z)
	var lip := smoothstep(0.72, 1.0, e)
	return lerpf(h, 0.0, lip) - lip * lip * 0.03


# ------------------------------------------------------------------ build

func build(seed_text: String, density: int, animate: bool) -> void:
	var hs := hash_str(seed_text)
	rng.seed = hs
	n_lo.seed = hs & 0xFFFF
	n_lo.frequency = 0.32
	n_hi.seed = (hs >> 8) & 0xFFFF
	n_hi.frequency = 1.6
	n_rim.seed = (hs >> 16) & 0xFFFF
	n_rim.frequency = 0.012
	rocks.clear()
	taken.clear()
	grown = 0
	for ch in plants.get_children():
		ch.queue_free()

	var mesh := ArrayMesh.new()
	var thick := InkMesh.new()
	var thin := InkMesh.new()
	_island(thick)
	_log(thick)
	_rocks(thick)
	thick.add_to(mesh, mat_thick)
	thin.add_to(mesh, mat_thin)
	static_node.mesh = mesh

	var shrubs := 4 + int(density * 0.08)
	var flowers := 7 + int(density * 0.14)
	var tufts := 14 + int(density * 0.3)
	var items: Array = []
	for i in shrubs:
		var p = _place(0.05, 0.86, 0.42, 0.55)
		if p != null:
			items.append(["shrub", p])
	for i in 4:
		var p = _place_near_log()
		if p != null:
			items.append(["mushrooms", p])
	for i in flowers:
		var p = _place(0.08, 0.9, 0.22, 0.35)
		if p != null:
			items.append(["flower", p])
	for i in tufts:
		var p = _place(0.1, 0.95, 0.12, 0.2)
		if p != null:
			items.append(["grass", p])
	for it in items:
		var node := _plant(it[0], it[1])
		if animate:
			var d: float = Vector2(node.position.x, node.position.z).length()
			_grow(node, 0.15 + d * 0.16 + rng.randf() * 0.25)


func _grow(node: Node3D, delay: float) -> void:
	node.scale = Vector3.ONE * 0.001
	var tw := node.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(node, "scale", Vector3.ONE, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _island(m: InkMesh) -> void:
	# top surface: polar grid
	m.begin()
	var center := m.vert(Vector3(0, height(0, 0), 0), Color(0, 0.96, 0, 1))
	var rows := []
	var rim := PackedFloat32Array()
	for j in NS:
		rim.append(outline(TAU * j / NS))
	for i in range(1, NR + 1):
		var f := float(i) / NR
		f = 1.0 - (1.0 - f) * (1.0 - f) * 0.6 - (1.0 - f) * 0.4
		var row := []
		for j in NS:
			var th := TAU * j / NS
			var r := rim[j] * f
			var x := cos(th) * r
			var z := sin(th) * r
			var tone := 0.96 + 0.04 * n_hi.get_noise_2d(x * 1.7, z * 1.7)
			row.append(m.vert(Vector3(x, height(x, z), z), Color(0, tone, 0, 1)))
		rows.append(row)
	var r0: Array = rows[0]
	for j in NS:
		m.tri(center, r0[j], r0[(j + 1) % NS], Vector3.UP)
	for i in rows.size() - 1:
		var a: Array = rows[i]
		var b: Array = rows[i + 1]
		for j in NS:
			m.quad(a[j], a[(j + 1) % NS], b[(j + 1) % NS], b[j], Vector3.UP)
	m.smooth()

	# soil strata: stepped walls and under-ledges
	var fs := [1.0, 0.95, 0.85, 0.71, 0.54]
	var tones := [0.72, 0.58, 0.68, 0.52, 0.62]
	var y := -0.02
	var ys := [y]
	for k in fs.size():
		y -= 0.22 + rng.randf() * 0.12
		ys.append(y)
	for k in fs.size():
		var f0: float = fs[k]
		var yt: float = ys[k]
		var yb: float = ys[k + 1]
		if k == 0:
			yt = height(rim[0], 0)
		m.begin()
		var ring_t := []
		var ring_m := []
		var ring_b := []
		for j in NS:
			var th := TAU * j / NS
			var wob := 1.0 + 0.035 * n_rim.get_noise_2d(cos(th) * 40.0 + k * 13.0, sin(th) * 40.0)
			var r: float = rim[j] * f0 * wob
			var d := Vector3(cos(th), 0, sin(th))
			var t0: float = tones[k] + 0.06 * n_hi.get_noise_2d(th * 3.0, k * 7.0)
			var top_y: float = height(d.x * rim[j], d.z * rim[j]) if k == 0 else yt
			ring_t.append(m.vert(d * r + Vector3(0, top_y, 0), Color(0, t0, 0, 1)))
			ring_m.append(m.vert(d * r * 1.018 + Vector3(0, lerpf(top_y, yb, 0.45), 0), Color(0, t0, 0, 0.9)))
			ring_b.append(m.vert(d * r * 0.97 + Vector3(0, yb, 0), Color(0, t0 * 0.92, 0, 0.8)))
		for j in NS:
			var j2 := (j + 1) % NS
			var out := Vector3(cos(TAU * j / NS), 0, sin(TAU * j / NS))
			m.quad(ring_t[j], ring_t[j2], ring_m[j2], ring_m[j], out)
			m.quad(ring_m[j], ring_m[j2], ring_b[j2], ring_b[j], out)
		m.smooth()
		# ledge under this layer to the next one
		if k < fs.size() - 1:
			m.begin()
			var f1: float = fs[k + 1]
			var la := []
			var lb := []
			for j in NS:
				var th := TAU * j / NS
				var d := Vector3(cos(th), 0, sin(th))
				var wob := 1.0 + 0.035 * n_rim.get_noise_2d(cos(th) * 40.0 + (k + 1) * 13.0, sin(th) * 40.0)
				la.append(m.vert(d * rim[j] * f0 * 0.97 * (1.0 + 0.035 * n_rim.get_noise_2d(cos(th) * 40.0 + k * 13.0, sin(th) * 40.0)) + Vector3(0, yb, 0), Color(0, 0.3, 0, 0.6)))
				lb.append(m.vert(d * rim[j] * f1 * wob + Vector3(0, yb - 0.01, 0), Color(0, 0.3, 0, 0.5)))
			for j in NS:
				var j2 := (j + 1) % NS
				m.quad(la[j], la[j2], lb[j2], lb[j], Vector3.DOWN)
			m.smooth()
	# root cone underneath
	m.begin()
	var yl: float = ys[ys.size() - 1]
	var fl: float = fs[fs.size() - 1] * 0.97
	var cone := []
	var steps := [[fl, yl], [fl * 0.62, yl - 0.32], [fl * 0.3, yl - 0.68]]
	for st in steps:
		var ring := []
		for j in NS:
			var th := TAU * j / NS
			var d := Vector3(cos(th), 0, sin(th))
			var wob := 1.0 + 0.08 * n_rim.get_noise_2d(cos(th) * 90.0, sin(th) * 90.0 + st[1] * 10.0)
			ring.append(m.vert(d * rim[j] * st[0] * wob + Vector3(0, st[1], 0), Color(0, 0.36, 0, 0.7)))
		cone.append(ring)
	var tip := m.vert(Vector3(0.2, yl - 1.05, -0.1), Color(0, 0.3, 0, 0.6))
	for s in cone.size() - 1:
		var a: Array = cone[s]
		var b: Array = cone[s + 1]
		for j in NS:
			var j2 := (j + 1) % NS
			var o := (m.v[a[j]] + m.v[b[j2]]) * 0.5
			m.quad(a[j], a[j2], b[j2], b[j], Vector3(o.x, -0.35, o.z))
	var lastr: Array = cone[cone.size() - 1]
	for j in NS:
		var o := m.v[lastr[j]]
		m.tri(tip, lastr[j], lastr[(j + 1) % NS], Vector3(o.x, -0.6, o.z))
	m.smooth()
	# hanging roots from the ledges
	for i in 12 + rng.randi() % 6:
		var k := 1 + rng.randi() % 3
		var th := rng.randf() * TAU
		var j := int(th / TAU * NS) % NS
		var f: float = lerpf(fs[k + 1], fs[k] * 0.95, rng.randf())
		var d := Vector3(cos(th), 0, sin(th))
		var start: Vector3 = d * rim[j] * f + Vector3(0, ys[k + 1] + 0.02, 0)
		var length := 0.25 + rng.randf() * 0.75
		var pts := PackedVector3Array()
		var rad := PackedFloat32Array()
		var wts := PackedFloat32Array()
		var curl := Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5) * 0.25 + d * 0.12
		for s in 6:
			var t := s / 5.0
			pts.append(start + Vector3(0, -length * t, 0) + curl * t * t)
			rad.append(lerpf(0.02, 0.005, t))
			wts.append(0.22 * t)
		m.tube(pts, rad, wts, 5, Color(0, 0.3, 0, 0.7), true)


func _log(m: InkMesh) -> void:
	var ang := rng.randf() * TAU
	var dir := Vector3(cos(ang), 0, sin(ang) * 0.8).normalized()
	var c := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.45, 0.45))
	var length := rng.randf_range(3.2, 3.9)
	log_r = rng.randf_range(0.2, 0.25)
	var a := c - dir * length * 0.5
	var b := c + dir * length * 0.5
	# keep it on the island, with one end allowed to overhang a little
	for tries in 12:
		if rho(a.x, a.z) < 0.93 and rho(b.x, b.z) < 1.06:
			break
		a = a.lerp(c, 0.12)
		b = b.lerp(c, 0.06)
	a.y = height(a.x, a.z) + log_r * 0.62
	b.y = (height(b.x, b.z) if rho(b.x, b.z) < 1.0 else 0.0) + log_r * 0.7
	log_a = a
	log_b = b
	var segs := 22
	var sides := 14
	var axis := (b - a).normalized()
	var nrm := (Vector3.UP - axis * axis.dot(Vector3.UP)).normalized()
	var bn := axis.cross(nrm)
	m.begin()
	var rings := []
	for i in segs + 1:
		var t := float(i) / segs
		var ctr := a.lerp(b, t)
		var ring := []
		for s in sides:
			var phi := TAU * s / sides
			var ridge := 0.055 * sin(phi * 9.0 + t * 2.0) + 0.04 * n_hi.get_noise_2d(t * 9.0, phi * 3.0)
			var r := log_r * (1.0 + ridge) * lerpf(1.0, 0.86, t)
			var tone := 0.6 + 0.08 * sin(phi * 9.0 + t * 2.0)
			ring.append(m.vert(ctr + (nrm * cos(phi) + bn * sin(phi)) * r, Color(0, tone, 0, 1)))
		rings.append(ring)
	for i in segs:
		var ra: Array = rings[i]
		var rb: Array = rings[i + 1]
		var mid := a.lerp(b, (i + 0.5) / segs)
		for s in sides:
			var s2 := (s + 1) % sides
			m.quad(ra[s], ra[s2], rb[s2], rb[s], (m.v[ra[s]] + m.v[rb[s2]]) * 0.5 - mid)
	m.smooth()
	# end grain: cut face with a shallow recess
	for e in 2:
		var ring: Array = rings[0] if e == 0 else rings[segs]
		var ctr := a if e == 0 else b
		var out := -axis if e == 0 else axis
		m.begin()
		var inner := []
		for s in sides:
			var p: Vector3 = m.v[ring[s]]
			inner.append(m.vert(ctr + (p - ctr) * 0.55 - out * 0.03, Color(0, 0.86, 0, 1)))
		var rim_ring := []
		for s in sides:
			rim_ring.append(m.vert(m.v[ring[s]], Color(0, 0.8, 0, 1)))
		var mid := m.vert(ctr - out * 0.05, Color(0, 0.72, 0, 0.8))
		for s in sides:
			var s2 := (s + 1) % sides
			m.quad(rim_ring[s], rim_ring[s2], inner[s2], inner[s], out)
			m.tri(mid, inner[s], inner[s2], out)
		m.smooth()
	# a broken branch stub
	var t0 := rng.randf_range(0.3, 0.62)
	var base := a.lerp(b, t0)
	var sd := 1.0 if rng.randf() > 0.5 else -1.0
	var bdir := (Vector3.UP * 0.8 + bn * sd * 0.7 + axis * 0.3).normalized()
	var pts := PackedVector3Array([base, base + bdir * 0.25, base + bdir * 0.48 + axis * 0.05])
	m.tube(pts, PackedFloat32Array([0.085, 0.07, 0.05]), PackedFloat32Array([0, 0, 0]), 8, Color(0, 0.62, 0, 1), true)
	# moss cushions along the top of the log
	for i in 3:
		var p := a.lerp(b, rng.randf_range(0.1, 0.9)) + nrm * log_r * 0.9
		m.blob(p, Vector3(0.12, 0.06, 0.1) * rng.randf_range(0.8, 1.3), 4, 7, Color(0, 0.7, 0, 0.9), 0.2, rng)


func _rocks(m: InkMesh) -> void:
	for i in 2 + rng.randi() % 3:
		for tries in 20:
			var th := rng.randf() * TAU
			var e := rng.randf_range(0.5, 0.84)
			var r := outline(th) * e
			var p := Vector3(cos(th) * r, 0, sin(th) * r)
			var size := rng.randf_range(0.26, 0.5)
			if _log_dist(p) < log_r + size + 0.1 or _blocked(Vector2(p.x, p.z), size):
				continue
			p.y = height(p.x, p.z) - size * 0.2
			m.facet_rock(p, Vector3(size, size * rng.randf_range(0.55, 0.8), size * rng.randf_range(0.75, 1.0)), 5, 8, Color(0, 0.8, 0, 1), 0.2, rng)
			rocks.append([p, size])
			taken.append([Vector2(p.x, p.z), size])
			break
	for i in 10:
		var th := rng.randf() * TAU
		var r := outline(th) * rng.randf_range(0.2, 0.9)
		var p := Vector3(cos(th) * r, 0, sin(th) * r)
		if _log_dist(p) < log_r + 0.1:
			continue
		var s := rng.randf_range(0.04, 0.09)
		p.y = height(p.x, p.z)
		m.facet_rock(p, Vector3(s, s * 0.6, s * 0.8), 3, 5, Color(0, 0.76, 0, 1), 0.2, rng)


# ------------------------------------------------------------------ placement

func _log_dist(p: Vector3) -> float:
	var a := Vector2(log_a.x, log_a.z)
	var b := Vector2(log_b.x, log_b.z)
	var q := Vector2(p.x, p.z)
	var ab := b - a
	var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return q.distance_to(a + ab * t)


func _blocked(q: Vector2, r: float) -> bool:
	for t in taken:
		if q.distance_to(t[0]) < r + t[1]:
			return true
	return false


func _place(e0: float, e1: float, r_min: float, r_max: float):
	for tries in 28:
		var th := rng.randf() * TAU
		var e := sqrt(rng.randf_range(e0 * e0, e1 * e1))
		var r := outline(th) * e
		var p := Vector3(cos(th) * r, 0, sin(th) * r)
		var rr := rng.randf_range(r_min, r_max)
		if _log_dist(p) < log_r + rr * 0.6:
			continue
		if _blocked(Vector2(p.x, p.z), rr * 0.6):
			continue
		taken.append([Vector2(p.x, p.z), rr * 0.6])
		p.y = height(p.x, p.z)
		return [p, rr]
	return null


func _place_near_log():
	for tries in 16:
		var t := rng.randf_range(0.1, 0.9)
		var base := log_a.lerp(log_b, t)
		var axis := (log_b - log_a).normalized()
		var side := axis.cross(Vector3.UP).normalized() * (1.0 if rng.randf() > 0.5 else -1.0)
		var p := base + side * (log_r + rng.randf_range(0.08, 0.2))
		if rho(p.x, p.z) > 0.9 or _blocked(Vector2(p.x, p.z), 0.08):
			continue
		taken.append([Vector2(p.x, p.z), 0.1])
		p.y = height(p.x, p.z)
		return [p, 0.1]
	return null


# ------------------------------------------------------------------ plants

func _plant(kind: String, spec: Array) -> Node3D:
	var base: Vector3 = spec[0]
	var size: float = spec[1]
	var thick := InkMesh.new()
	var thin := InkMesh.new()
	match kind:
		"shrub":
			_shrub(thick, thin, size)
		"flower":
			if rng.randf() < 0.6:
				_cup_flower(thick, thin, rng.randf() < 0.2)
			else:
				_umbel(thick, thin)
		"grass":
			_grass(thin)
		"mushrooms":
			_mushrooms(thick)
	var mesh := ArrayMesh.new()
	thick.add_to(mesh, mat_thick)
	thin.add_to(mesh, mat_thin)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = base
	mi.rotation.y = rng.randf() * TAU
	plants.add_child(mi)
	return mi


func germinate(p: Vector3) -> bool:
	if grown >= 32:
		return false
	grown += 1
	var node := _plant("flower", [p, 0.3])
	_grow(node, 0.0)
	return true


func _shrub(m: InkMesh, thin: InkMesh, r: float) -> void:
	# Foliage as loose ink strokes: a fan of blades and small leaves with
	# paper showing between them, plus one small shaded core for weight.
	var hmax := r * 1.25
	m.blob(Vector3(0, hmax * 0.18, 0), Vector3(r * 0.42, r * 0.3, r * 0.42), 4, 7, Color(0.0, 0.62, 0, 0.8), 0.16, rng, 0.35, hmax)
	var blades := 14 + rng.randi() % 8
	for i in blades:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf() * r * 0.3
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.5, 1.4)
		thin.blade(off, lean, rng.randf_range(0.55, 1.1) * hmax, rng.randf_range(0.04, 0.06), Color(0, 0.72, 0, 1), 0.0)
	var leaves := 8 + rng.randi() % 8
	for i in leaves:
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), rng.randf_range(0.2, 0.9), sin(a)).normalized()
		var up := d.cross(Vector3(-sin(a), 0, cos(a))).normalized()
		if up.y < 0:
			up = -up
		var p := Vector3(cos(a) * r * 0.25, rng.randf_range(0.25, 0.7) * hmax, sin(a) * r * 0.25)
		thin.petal(p, d, up, rng.randf_range(0.14, 0.22), 0.06, 0.2, Color(0, 0.6, 0, 1), 0.6, 1.0)


func _stem(m: InkMesh, h: float, lean: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var rad := PackedFloat32Array()
	var wts := PackedFloat32Array()
	var top := Vector3(lean.x, h, lean.z)
	for i in 8:
		var t := i / 7.0
		var q := Vector3(0, 0, 0).lerp(Vector3(0, h * 0.55, 0), t).lerp(Vector3(0, h * 0.55, 0).lerp(top, t), t)
		pts.append(q)
		rad.append(lerpf(0.018, 0.011, t))
		wts.append(t)
	m.tube(pts, rad, wts, 5, Color(0, 0.62, 0.5, 1))
	return pts


func _leaves(thin: InkMesh, pts: PackedVector3Array) -> void:
	for i in 1 + rng.randi() % 2:
		var k := 1 + rng.randi() % 3
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0.55, sin(a)).normalized()
		var up := d.cross(Vector3(-sin(a), 0, cos(a))).normalized()
		if up.y < 0:
			up = -up
		thin.petal(pts[k], d, up, rng.randf_range(0.16, 0.24), 0.07, 0.25, Color(0, 0.6, 0, 1), k / 7.0, k / 7.0 + 0.2)


func _cup_flower(m: InkMesh, thin: InkMesh, berry: bool) -> void:
	var h := rng.randf_range(0.55, 1.3)
	var lean := Vector3(rng.randf_range(-0.14, 0.14), 0, rng.randf_range(-0.14, 0.14))
	var pts := _stem(m, h, lean)
	_leaves(thin, pts)
	var top := pts[pts.size() - 1]
	var face := (Vector3.UP + lean * 1.6).normalized()
	var ref := Vector3.RIGHT if absf(face.x) < 0.9 else Vector3.FORWARD
	var u := face.cross(ref).normalized()
	var w := face.cross(u)
	var count := 5 + rng.randi() % 3
	var plen := rng.randf_range(0.16, 0.24)
	var cup := rng.randf_range(0.25, 0.6)
	var flag := 1.0 if berry else 0.0
	for i in count:
		var a := TAU * i / count + rng.randf() * 0.2
		var d := (u * cos(a) + w * sin(a)).normalized()
		thin.petal(top + d * 0.025, (d + face * 0.15).normalized(), face, plen, plen * 0.62, cup, Color(0, 1.0, flag, 1), 1.0, 1.0)
	m.blob(top + face * 0.015, Vector3.ONE * 0.055, 4, 6, Color(1.0, 0.34, 0, 1), 0.1, rng)


func _umbel(m: InkMesh, thin: InkMesh) -> void:
	var h := rng.randf_range(0.7, 1.35)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
	var pts := _stem(m, h, lean)
	_leaves(thin, pts)
	var top := pts[pts.size() - 1]
	var spokes := 9 + rng.randi() % 5
	var spread := rng.randf_range(0.16, 0.24)
	for i in spokes:
		var a := TAU * i / spokes + rng.randf() * 0.3
		var rr := spread * sqrt(rng.randf_range(0.35, 1.0))
		var tip := top + Vector3(cos(a) * rr, 0.07 + (spread - rr) * 0.5, sin(a) * rr)
		var sp := PackedVector3Array([top, top.lerp(tip, 0.5) + Vector3(0, 0.015, 0), tip])
		m.tube(sp, PackedFloat32Array([0.006, 0.005, 0.004]), PackedFloat32Array([1, 1, 1]), 3, Color(0, 0.6, 0.5, 1))
		m.blob(tip, Vector3(0.04, 0.028, 0.04), 3, 6, Color(1.0, 1.0, 0, 1), 0.1, rng)


func _grass(thin: InkMesh) -> void:
	for i in 5 + rng.randi() % 5:
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * rng.randf() * 0.06
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.15, 0.6)
		thin.blade(off, lean, rng.randf_range(0.14, 0.5), rng.randf_range(0.022, 0.036), Color(0, 0.72, 0, 1), 0.0)


func _mushrooms(m: InkMesh) -> void:
	for i in 2 + rng.randi() % 3:
		var off := Vector3(rng.randf_range(-0.07, 0.07), 0, rng.randf_range(-0.07, 0.07))
		var h := rng.randf_range(0.06, 0.13)
		var tilt := Vector3(rng.randf_range(-0.03, 0.03), 0, rng.randf_range(-0.03, 0.03))
		var top := off + Vector3(0, h, 0) + tilt
		m.tube(PackedVector3Array([off, off.lerp(top, 0.5), top]), PackedFloat32Array([0.016, 0.013, 0.012]), PackedFloat32Array([0, 0, 0]), 6, Color(0, 0.9, 0, 1))
		var cr := rng.randf_range(0.045, 0.075)
		m.blob(top, Vector3(cr, cr * 0.5, cr), 5, 9, Color(0, 0.96, 0, 1), 0.04, rng)
