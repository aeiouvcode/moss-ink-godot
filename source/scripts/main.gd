extends Node3D
## Moss / Ink field study 03: scene, camera, instrument state and interface.

const FOG := Color(0.659, 0.647, 0.620)      # paper
const LIFT := Color(0.851, 0.839, 0.812)     # light paper, text on ink
const INK := Color(0.157, 0.141, 0.122)
const INK2 := Color(0.157, 0.141, 0.122, 0.72)
const HAIR := Color(0.157, 0.141, 0.122, 0.3)
const BERRY := Color(0.157, 0.141, 0.122)    # two tones only: the signal is ink

var state := {"seed": "moss41", "density": 62, "light": 38, "wind": 34}
var paused := false
var clock := 0.0

var world: InkWorld
var cam: Camera3D
var sun: DirectionalLight3D
var mat_thick: ShaderMaterial
var mat_thin: ShaderMaterial
var mat_line: ShaderMaterial
var poke_timer := 3.0
var svc: SubViewportContainer
var sv: SubViewport
var shrink := 2

var lean := Vector2.ZERO
var lean_target := Vector2.ZERO
var press_pos := Vector2.ZERO
var press_time := 0
var pressing := false
var moved := false

var mono: FontVariation
var mono_wide: FontVariation
var serif: Font
var serif_it: Font
var ui: Control
var panel: PanelContainer
var scrim: ColorRect
var toast: Label
var toast_tw: Tween
var read_field: Label
var read_canopy: Label
var read_light: Label
var read_wind: Label
var out := {}
var sliders := {}
var seed_edit: LineEdit
var pause_btn: Button
var panel_open := false
var scale_f := 1.0


func _ready() -> void:
	_read_url()
	scale_f = clampf(DisplayServer.screen_get_scale(), 1.0, 4.0)
	get_window().content_scale_factor = scale_f
	_scene()
	_ui()
	world.build(state.seed, state.density, true)
	_apply_light()
	_apply_wind()
	_sync()
	get_window().size_changed.connect(_layout)
	_layout()


# ------------------------------------------------------------------ scene

func _mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _scene() -> void:
	mat_thick = _mat("res://shaders/ink.gdshader")
	mat_thin = _mat("res://shaders/ink_thin.gdshader")
	mat_line = _mat("res://shaders/ink_outline.gdshader")
	mat_thick.next_pass = mat_line
	svc = SubViewportContainer.new()
	svc.stretch = true
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	var base := Control.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)
	base.add_child(svc)
	sv = SubViewport.new()
	sv.msaa_3d = Viewport.MSAA_DISABLED
	sv.handle_input_locally = false
	svc.add_child(sv)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = FOG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 26.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 0.0
	sv.add_child(sun)

	cam = Camera3D.new()
	cam.near = 0.1
	cam.far = 60.0
	sv.add_child(cam)

	world = InkWorld.new()
	sv.add_child(world)
	world.setup(mat_thick, mat_thin)

	_apply_cell()


func _apply_cell() -> void:
	shrink = maxi(2, int(round(scale_f)))
	svc.stretch_shrink = shrink


func _apply_light() -> void:
	# ink pools stay short: the solar-angle param maps onto a higher arc
	var a := deg_to_rad(28.0 + float(state.light) * 0.8)
	var to_sun := Vector3(-cos(a), sin(a), 0.35).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.FORWARD if absf(to_sun.y) > 0.98 else Vector3.UP), Vector3.ZERO)


func _apply_wind() -> void:
	var w: float = state.wind / 100.0
	for m in [mat_thick, mat_thin, mat_line]:
		m.set_shader_parameter("wind", w)


func _process(dt: float) -> void:
	if not paused:
		clock += dt * (0.45 + state.wind / 100.0)
		# now and then a gust nudges one clump so the blobs visibly settle
		poke_timer -= dt
		if poke_timer <= 0.0:
			poke_timer = randf_range(4.0, 7.0)
			var kids := world.plants.get_children()
			if kids.size() > 0:
				_poke((kids[randi() % kids.size()] as Node3D).global_position)
	lean = lean.lerp(lean_target, 1.0 - exp(-dt * 3.0))
	if not pressing:
		lean_target = lean_target.lerp(Vector2.ZERO, 1.0 - exp(-dt * 0.25)) if _touchy() else lean_target
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	var yaw := 0.55 + sin(clock * 0.07) * 0.75 + lean.x * 0.5
	var pitch := 0.24 + cos(clock * 0.053) * 0.04 + lean.y * 0.16
	var dist := 8.4 if portrait else 8.2
	var target := Vector3(0, -0.2 if portrait else -0.25, 0)
	cam.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	cam.look_at(target, Vector3.UP)
	if portrait:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = 40.0
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = 30.0


func _touchy() -> bool:
	return DisplayServer.is_touchscreen_available()


# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if panel_open:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			pressing = true
			moved = false
			press_pos = e.position
			press_time = Time.get_ticks_msec()
		else:
			pressing = false
			if not moved and Time.get_ticks_msec() - press_time < 450:
				_tap(e.position)
	elif e is InputEventMouseMotion:
		var vs := get_viewport().get_visible_rect().size
		if pressing:
			if e.position.distance_to(press_pos) > 8.0:
				moved = true
			lean_target += Vector2(-e.relative.x / vs.x, -e.relative.y / vs.y) * 2.4
			lean_target = lean_target.clamp(Vector2(-1.2, -1), Vector2(1.2, 1))
		elif not _touchy():
			lean_target = Vector2(0.5 - e.position.x / vs.x, 0.5 - e.position.y / vs.y) * 0.9


func _poke(p: Vector3) -> void:
	var t := fmod(Time.get_ticks_msec() / 1000.0, 3600.0)
	for m in [mat_thick, mat_thin, mat_line]:
		m.set_shader_parameter("poke", Vector4(p.x, p.y + 0.3, p.z, t))


func _tap(pos: Vector2) -> void:
	var o := cam.project_ray_origin(pos / float(shrink))
	var d := cam.project_ray_normal(pos / float(shrink))
	var t := 0.0
	var prev_above := true
	while t < 40.0:
		var p := o + d * t
		if world.rho(p.x, p.z) < 0.9 and p.y <= world.height(p.x, p.z):
			_poke(p)
			if world.germinate(Vector3(p.x, world.height(p.x, p.z), p.z)):
				_say("A new stem took root")
			else:
				_say("The moss is full - grow a new field")
			return
		t += 0.04
	_say("Tap the moss to germinate")


# ------------------------------------------------------------------ state

func _clean_seed(s: String) -> String:
	var outs := ""
	for ch in s.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			outs += ch
	outs = outs.substr(0, 8)
	return outs if outs != "" else "moss41"


func _num(v, d: int, lo: int, hi: int) -> int:
	if v == null or not str(v).is_valid_float():
		return d
	return clampi(int(round(float(v))), lo, hi)


func _read_url() -> void:
	if not OS.has_feature("web"):
		return
	var q = JavaScriptBridge.eval("location.search", true)
	if typeof(q) != TYPE_STRING:
		return
	var kv := {}
	for part in str(q).trim_prefix("?").split("&", false):
		var bits := part.split("=")
		if bits.size() == 2:
			kv[bits[0]] = bits[1].uri_decode()
	state.seed = _clean_seed(kv.get("s", "moss41"))
	state.density = _num(kv.get("d"), 62, 25, 100)
	state.light = _num(kv.get("l"), 38, 8, 78)
	state.wind = _num(kv.get("w"), 34, 0, 100)


func _query() -> String:
	return "?s=%s&d=%d&l=%d&w=%d" % [state.seed, state.density, state.light, state.wind]


func _sync() -> void:
	read_field.text = _b36(InkWorld.hash_str(state.seed)).substr(0, 4).to_upper()
	read_canopy.text = "%d%%" % state.density
	read_light.text = "%d°" % state.light
	read_wind.text = "%.2f" % (state.wind / 100.0)
	out.density.text = read_canopy.text
	out.light.text = read_light.text
	out.wind.text = read_wind.text
	for k in ["density", "light", "wind"]:
		sliders[k].set_value(state[k])
	if not seed_edit.has_focus():
		seed_edit.text = state.seed
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try{history.replaceState(null,'','%s')}catch(e){}" % _query())


func _b36(n: int) -> String:
	var digits := "0123456789abcdefghijklmnopqrstuvwxyz"
	if n == 0:
		return "0"
	var s := ""
	while n > 0:
		s = digits[n % 36] + s
		n /= 36
	return s


func _regrow(msg: String) -> void:
	world.build(state.seed, state.density, true)
	_sync()
	_say(msg)


# ------------------------------------------------------------------ interface

func _font(path: String, spacing := 0) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(path)
	f.spacing_glyph = spacing
	return f


func _label(text: String, font: Font, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box(bg: Color, border: Color, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	s.anti_aliasing = true
	return s


func _chip(text: String, signal_chip := false) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(0, 34)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", mono_wide)
	b.add_theme_font_size_override("font_size", 8)
	var base := _box(BERRY if signal_chip else Color(FOG, 0.8), BERRY if signal_chip else HAIR)
	var hot := _box(INK, INK)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hot if not _touchy() else base)
	b.add_theme_stylebox_override("pressed", hot)
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), INK))
	var fc := Color.WHITE if signal_chip else INK
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_hover_color", LIFT if not _touchy() else fc)
	b.add_theme_color_override("font_pressed_color", LIFT)
	b.add_theme_color_override("font_focus_color", fc)
	return b


func _ui() -> void:
	mono = _font("res://fonts/plex-IBMPlexMono-Medium.ttf", 0)
	mono_wide = _font("res://fonts/plex-IBMPlexMono-Medium.ttf", 1)
	serif = load("res://fonts/InstrumentSerif-Regular.ttf")
	serif_it = load("res://fonts/InstrumentSerif-Italic.ttf")
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)

	var brand := HBoxContainer.new()
	brand.name = "brand"
	brand.add_theme_constant_override("separation", 8)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sig := Control.new()
	sig.custom_minimum_size = Vector2(18, 14)
	sig.draw.connect(func():
		sig.draw_arc(Vector2(5, 13), 7.0, PI * 1.05, PI * 1.62, 10, INK, 2.0, true)
		sig.draw_arc(Vector2(13, 13), 7.0, PI * 1.38, PI * 1.95, 10, INK, 2.0, true))
	brand.add_child(sig)
	brand.add_child(_label("MOSS / INK", mono_wide, 9, INK))
	var study := _label("FIELD STUDY 03", mono_wide, 9, INK2)
	study.name = "study"
	brand.add_child(study)
	ui.add_child(brand)

	var acts := HBoxContainer.new()
	acts.name = "acts"
	acts.add_theme_constant_override("separation", 6)
	pause_btn = _chip("still")
	pause_btn.pressed.connect(func():
		paused = not paused
		pause_btn.text = "DRIFT" if paused else "STILL"
		_say("Field held still" if paused else "Drift resumed"))
	acts.add_child(pause_btn)
	var nb := _chip("new field")
	nb.pressed.connect(func():
		state.seed = _b36(randi() % 2176782336)
		_regrow("New field grown"))
	acts.add_child(nb)
	var sb := _chip("")
	sb.custom_minimum_size = Vector2(36, 34)
	sb.tooltip_text = "Field controls"
	var ico := Control.new()
	ico.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ico.set_anchors_preset(Control.PRESET_FULL_RECT)
	ico.draw.connect(func():
		var c := ico.size * 0.5
		var col := LIFT if sb.is_hovered() and not _touchy() or sb.button_pressed else INK
		for i in 3:
			var y := c.y - 5 + i * 5
			ico.draw_line(Vector2(c.x - 7, y), Vector2(c.x + 7, y), col, 1.0)
			var kx: float = c.x + [-3, 3, -1][i]
			ico.draw_rect(Rect2(kx - 1.5, y - 2.5, 3, 5), col))
	sb.add_child(ico)
	sb.mouse_entered.connect(ico.queue_redraw)
	sb.mouse_exited.connect(ico.queue_redraw)
	sb.pressed.connect(func(): _open_panel(true))
	acts.add_child(sb)
	ui.add_child(acts)

	var tip := _label("DRAG TO LEAN · TAP THE MOSS TO GERMINATE\nEACH FIELD HAS A PERMANENT ADDRESS", mono_wide, 7, INK2)
	tip.name = "tip"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not _touchy():
		tip.text = "MOVE TO LEAN · CLICK THE MOSS TO GERMINATE\nEACH FIELD HAS A PERMANENT ADDRESS"
	ui.add_child(tip)

	var read := HBoxContainer.new()
	read.name = "read"
	read.add_theme_constant_override("separation", 18)
	read.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", -18)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(_label("living", serif, 50, INK))
	title.add_child(_label("topography", serif_it, 50, INK))
	read.add_child(title)
	var dl := GridContainer.new()
	dl.columns = 2
	dl.add_theme_constant_override("h_separation", 12)
	dl.add_theme_constant_override("v_separation", 3)
	dl.size_flags_vertical = Control.SIZE_SHRINK_END
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for pair in [["FIELD", "read_field"], ["CANOPY", "read_canopy"], ["LIGHT", "read_light"], ["WIND", "read_wind"]]:
		dl.add_child(_label(pair[0], mono_wide, 7, INK2))
		var v := _label("", mono_wide, 8, INK)
		set(pair[1], v)
		dl.add_child(v)
	var dlw := MarginContainer.new()
	dlw.add_theme_constant_override("margin_bottom", 12)
	dlw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dlw.size_flags_vertical = Control.SIZE_SHRINK_END
	dlw.add_child(dl)
	read.add_child(dlw)
	ui.add_child(read)

	scrim = ColorRect.new()
	scrim.color = Color(INK, 0.12)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.visible = false
	scrim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_open_panel(false))
	ui.add_child(scrim)
	_build_panel()

	toast = _label("", mono_wide, 8, LIFT)
	var ts := _box(INK, INK, 12)
	ts.content_margin_top = 8
	ts.content_margin_bottom = 8
	toast.add_theme_stylebox_override("normal", ts)
	toast.modulate.a = 0.0
	ui.add_child(toast)


func _build_panel() -> void:
	panel = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(FOG, 0.96)
	ps.border_color = HAIR
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(4)
	ps.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", ps)
	panel.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := HBoxContainer.new()
	var kick := _label("DETERMINISTIC FIELD INSTRUMENT", mono_wide, 7, INK2)
	kick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(kick)
	var close := _chip("×")
	close.add_theme_font_size_override("font_size", 14)
	close.custom_minimum_size = Vector2(34, 34)
	close.pressed.connect(func(): _open_panel(false))
	head.add_child(close)
	col.add_child(head)
	col.add_child(_label("Shape the climate.", serif, 32, INK))
	var intro := _label("Every setting changes the same living system. The\naddress updates with it, so this exact field can\nbe opened again.", mono, 9, INK2)
	col.add_child(intro)
	for spec in [["density", "CANOPY DENSITY", 25, 100], ["light", "SOLAR ANGLE", 8, 78], ["wind", "WIND", 0, 100]]:
		var k: String = spec[0]
		var row := HBoxContainer.new()
		var nm := _label(spec[1], mono_wide, 8, INK)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var o := _label("", mono_wide, 8, INK)
		out[k] = o
		row.add_child(o)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		col.add_child(gap)
		col.add_child(row)
		var s := InkSlider.new()
		s.min_value = spec[2]
		s.max_value = spec[3]
		sliders[k] = s
		s.changed.connect(func(v):
			state[k] = v
			if k == "light":
				_apply_light()
			elif k == "wind":
				_apply_wind()
			_sync())
		if k == "density":
			s.released.connect(func(_v): _regrow("Canopy regrown"))
		col.add_child(s)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	seed_edit = LineEdit.new()
	seed_edit.max_length = 8
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.custom_minimum_size = Vector2(0, 34)
	seed_edit.add_theme_font_override("font", mono_wide)
	seed_edit.add_theme_font_size_override("font_size", 10)
	seed_edit.add_theme_color_override("font_color", INK)
	seed_edit.add_theme_color_override("caret_color", INK)
	seed_edit.add_theme_stylebox_override("normal", _box(Color(LIFT, 0.7), HAIR))
	seed_edit.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), INK))
	seed_edit.text_submitted.connect(func(_t): _grow_seed())
	var seed_lab := HBoxContainer.new()
	var sl := _label("FIELD SEED", mono_wide, 8, INK)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_lab.add_child(sl)
	seed_lab.add_child(_label("BASE 36", mono_wide, 8, INK2))
	col.add_child(seed_lab)
	srow.add_child(seed_edit)
	var gb := _chip("grow")
	gb.pressed.connect(_grow_seed)
	srow.add_child(gb)
	col.add_child(srow)
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 6)
	var cp := _chip("copy field link", true)
	cp.pressed.connect(_copy_link)
	arow.add_child(cp)
	var ex := _chip("save still")
	ex.pressed.connect(_save_still)
	arow.add_child(ex)
	col.add_child(arow)
	var note := _label("Lives only in this page and its address. No account,\nupload or server record.", mono, 8, INK2)
	col.add_child(note)
	ui.add_child(panel)


func _grow_seed() -> void:
	state.seed = _clean_seed(seed_edit.text)
	seed_edit.release_focus()
	_regrow("Field grown from seed")


func _open_panel(on: bool) -> void:
	panel_open = on
	panel.visible = on
	scrim.visible = on
	_layout()
	if on:
		sliders.density.grab_focus()


func _copy_link() -> void:
	if not OS.has_feature("web"):
		DisplayServer.clipboard_set(_query())
		_say("Field link copied")
		return
	JavaScriptBridge.eval("window.__miCopy=0;try{navigator.clipboard.writeText(location.href).then(()=>{window.__miCopy=1},()=>{window.__miCopy=2})}catch(e){window.__miCopy=2}")
	for i in 30:
		await get_tree().process_frame
		var r = JavaScriptBridge.eval("window.__miCopy", true)
		if r == 1:
			_say("Field link copied")
			return
		if r == 2:
			break
	_say("Copy unavailable - use the address bar")


func _save_still() -> void:
	panel.visible = false
	scrim.visible = false
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	if img != null and not img.is_empty():
		img.resize(img.get_width() * shrink, img.get_height() * shrink, Image.INTERPOLATE_NEAREST)
	panel.visible = panel_open
	scrim.visible = panel_open
	if img == null or img.is_empty():
		_say("The still could not be saved")
		return
	var buf := img.save_png_to_buffer()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(buf, "moss-ink-%s.png" % state.seed, "image/png")
		_say("Still saved to downloads")
	else:
		_say("Still captured")


func _say(text: String) -> void:
	toast.text = text.to_upper()
	toast.reset_size()
	_layout()
	if toast_tw:
		toast_tw.kill()
	toast_tw = create_tween()
	toast_tw.tween_property(toast, "modulate:a", 1.0, 0.18)
	toast_tw.tween_interval(1.6)
	toast_tw.tween_property(toast, "modulate:a", 0.0, 0.4)


func _layout() -> void:
	if ui == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var portrait := vs.y > vs.x
	var m := 18.0
	var brand: Control = ui.get_node("brand")
	brand.get_node("study").visible = vs.x >= 480.0
	brand.reset_size()
	brand.position = Vector2(m, 22)
	var acts: Control = ui.get_node("acts")
	acts.reset_size()
	acts.position = Vector2(vs.x - acts.size.x - 14, 12)
	var tip: Control = ui.get_node("tip")
	tip.reset_size()
	var read: Control = ui.get_node("read")
	read.reset_size()
	read.position = Vector2(m, vs.y - read.size.y - 14)
	if portrait:
		tip.position = Vector2(vs.x - tip.size.x - 14, 56)
	else:
		tip.position = Vector2(vs.x - tip.size.x - 18, vs.y - tip.size.y - 20)
	if toast:
		toast.reset_size()
		toast.position = Vector2((vs.x - toast.size.x) * 0.5, (vs.y * 0.74) if portrait else vs.y - 70)
	if panel:
		var w := minf(360.0, vs.x - 20.0)
		var col: Control = panel.get_child(0)
		col.custom_minimum_size.x = w - 44.0
		col.reset_size()
		panel.custom_minimum_size.x = w
		panel.size = Vector2(w, 0)
		panel.reset_size()
		if portrait:
			panel.position = Vector2((vs.x - w) * 0.5, vs.y - panel.size.y - 10)
		else:
			panel.position = Vector2(vs.x - w - 14, 58)
