class_name MinigameNoodles
extends MinigameBase
## "Nấu mì" — pot: "Đổ nước" -> stove knob: "Bật bếp" (stove_click, flickering flame) -> wait for the
## boil (heat_time s, water_boil loop + steam) -> noodle pack: "Cho mì vào" -> cook_time s countdown on
## the wall timer -> knob: "Tắt bếp" -> completed. Leaving it on overboil_time s after it is cooked
## boils over (signal boiled_over, sound, toast, foam) — still completable.
##
## Anchors: Stove (burner top centre = where the pot sits), Knob (optional, stove front),
##          NoodlePack (pack rest position), TimerDisplay (wall timer / clock label).

signal state_changed(state: int)
signal boiled_over

enum State { EMPTY, WATER, BOILING, COOKING, READY, DONE }

@export var heat_time := 20.0
@export var cook_time := 30.0
@export var overboil_time := 25.0
@export var stove_model: PackedScene
@export var pot_model: PackedScene
@export var noodle_model: PackedScene
## Optional existing Label3D used as the timer display (else one is created at TimerDisplay).
@export var timer_label_path: NodePath
@export var display_font: Font

var state: int = State.EMPTY
var stove_on := false
var heat := 0.0
var cook := 0.0
var overboil := 0.0
var did_boil_over := false

var _knob: MinigameButton
var _pot_btn: MinigameButton
var _pack: MinigameButton
var _pack_visual: Node3D
var _pack_home: Transform3D
var _flame: Node3D
var _flame_light: OmniLight3D
var _water: MeshInstance3D
var _noodles: Node3D
var _foam: Node3D
var _steam: CPUParticles3D
var _boil_audio: AudioStreamPlayer3D
var _timer_label: Label3D
var _blink := 0.0

# ---------------------------------------------------------------- setup
func _build_placeholder() -> void:
	var ph := Node3D.new()
	ph.name = "Placeholder"
	add_child(ph)
	# low shelf + wall board for the timer
	MinigameUtil.solid_box(ph, Vector3(0.9, 0.6, 0.5), Color(0.5, 0.4, 0.3), Vector3(0, 0.3, 0))
	var td := get_anchor("TimerDisplay")
	if td:
		var board := MinigameUtil.box(Vector3(0.26, 0.13, 0.03), Color(0.08, 0.08, 0.08))
		ph.add_child(board)
		board.global_transform = td.global_transform * Transform3D(Basis(), Vector3(0, 0, -0.018))

func _setup() -> void:
	var stove := get_anchor("Stove")
	var stove_root := stove if stove else self
	# stove body
	var sm := MinigameUtil.instance_model(stove_model)
	if sm == null:
		sm = Node3D.new()
		sm.add_child(MinigameUtil.box(Vector3(0.34, 0.09, 0.3), Color(0.25, 0.26, 0.28), Vector3(0, -0.045, 0)))
		sm.add_child(MinigameUtil.cylinder(0.06, 0.012, Color(0.12, 0.12, 0.12), Vector3(0, 0.004, 0)))
		var knob_vis := MinigameUtil.cylinder(0.022, 0.025, Color(0.1, 0.1, 0.1), Vector3(0.11, -0.045, 0.16))
		knob_vis.rotation.x = PI * 0.5
		knob_vis.name = "KnobVisual"
		sm.add_child(knob_vis)
	stove_root.add_child(sm)
	# flame
	_flame = Node3D.new()
	_flame.name = "Flame"
	_flame.position = Vector3(0, 0.012, 0)
	stove_root.add_child(_flame)
	for k in 8:
		var a := TAU * k / 8.0
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.01
		cm.height = 0.035
		cm.radial_segments = 4
		cm.rings = 1
		cone.mesh = cm
		cone.material_override = MinigameUtil.make_mat(Color(0.35, 0.55, 1.0, 0.85) if k % 2 == 0 else Color(1.0, 0.6, 0.2, 0.85), true)
		cone.position = Vector3(cos(a) * 0.045, 0.015, sin(a) * 0.045)
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame.add_child(cone)
	_flame_light = OmniLight3D.new()
	_flame_light.light_color = Color(1.0, 0.6, 0.3)
	_flame_light.omni_range = 1.4
	_flame_light.light_energy = 0.8
	_flame_light.position = Vector3(0, 0.08, 0)
	_flame.add_child(_flame_light)
	_flame.visible = false
	# pot
	var pot := Node3D.new()
	pot.name = "Pot"
	pot.position = Vector3(0, 0.012, 0)
	stove_root.add_child(pot)
	var pm := MinigameUtil.instance_model(pot_model)
	if pm == null:
		pm = Node3D.new()
		pm.add_child(MinigameUtil.cylinder(0.11, 0.012, Color(0.6, 0.6, 0.62), Vector3(0, 0.006, 0), 10))
		for k in 10:   # wall made of thin slabs so the inside is visible
			var a := TAU * k / 10.0
			var slab := MinigameUtil.box(Vector3(0.07, 0.11, 0.008), Color(0.62, 0.62, 0.64), Vector3(cos(a) * 0.107, 0.055, sin(a) * 0.107))
			slab.rotation.y = -a + PI * 0.5
			pm.add_child(slab)
		var handle := MinigameUtil.box(Vector3(0.14, 0.015, 0.025), Color(0.1, 0.1, 0.1), Vector3(0.18, 0.09, 0))
		pm.add_child(handle)
	pot.add_child(pm)
	_water = MinigameUtil.cylinder(0.102, 0.006, Color(0.55, 0.62, 0.65, 0.85), Vector3(0, 0.075, 0), 10)
	_water.visible = false
	pot.add_child(_water)
	_noodles = Node3D.new()
	_noodles.position = Vector3(0, 0.07, 0)
	pot.add_child(_noodles)
	var nb := MinigameUtil.box(Vector3(0.11, 0.025, 0.09), Color(0.92, 0.8, 0.42), Vector3(0, 0.005, 0))
	_noodles.add_child(nb)
	_noodles.visible = false
	_foam = Node3D.new()
	pot.add_child(_foam)
	_foam.add_child(MinigameUtil.cylinder(0.125, 0.02, Color(0.92, 0.9, 0.82), Vector3(0, 0.115, 0), 10))
	var spill := MeshInstance3D.new()
	var spm := PlaneMesh.new()
	spm.size = Vector2(0.42, 0.36)
	spill.mesh = spm
	spill.material_override = MinigameUtil.make_mat(Color(0.75, 0.72, 0.6, 0.55))
	spill.position = Vector3(0.0, -0.012 - 0.088, 0.0)
	_foam.add_child(spill)
	_foam.visible = false
	_steam = CPUParticles3D.new()
	_steam.amount = 10
	_steam.lifetime = 1.6
	_steam.emitting = false
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	var smat := MinigameUtil.make_mat(Color(0.9, 0.9, 0.9, 0.28), true)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = smat
	_steam.mesh = qm
	_steam.direction = Vector3.UP
	_steam.spread = 18.0
	_steam.gravity = Vector3(0, 0.06, 0)
	_steam.initial_velocity_min = 0.12
	_steam.initial_velocity_max = 0.25
	_steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_steam.emission_sphere_radius = 0.06
	_steam.position = Vector3(0, 0.12, 0)
	pot.add_child(_steam)
	_boil_audio = AudioStreamPlayer3D.new()
	_boil_audio.bus = "SFX"
	_boil_audio.unit_size = 2.0
	_boil_audio.max_distance = 12.0
	var bs := AudioDirector.get_stream("sfx", "water_boil")
	if bs:
		bs = bs.duplicate()
		if bs is AudioStreamOggVorbis or bs is AudioStreamMP3:
			bs.loop = true
		elif bs is AudioStreamWAV:
			bs.loop_mode = AudioStreamWAV.LOOP_FORWARD
			bs.loop_end = int(bs.get_length() * bs.mix_rate)
		_boil_audio.stream = bs
	pot.add_child(_boil_audio)
	# interaction volumes
	_pot_btn = MinigameButton.create("PotButton", Vector3(0.26, 0.16, 0.26), _pot_prompt, func(_p): fill_water(), Vector3(0, 0.08, 0))
	pot.add_child(_pot_btn)
	var knob_anchor := get_anchor("Knob")
	_knob = MinigameButton.create("KnobButton", Vector3(0.09, 0.08, 0.08), _knob_prompt, func(_p): toggle_stove())
	if knob_anchor:
		knob_anchor.add_child(_knob)
	else:
		stove_root.add_child(_knob)
		_knob.position = Vector3(0.11, -0.045, 0.17)
	# noodle pack
	var pack_anchor := get_anchor("NoodlePack")
	_pack = MinigameButton.create("NoodlePack", Vector3(0.16, 0.08, 0.13), _pack_prompt, func(_p): add_noodles(), Vector3(0, 0.03, 0))
	(pack_anchor if pack_anchor else self).add_child(_pack)
	_pack_visual = MinigameUtil.instance_model(noodle_model)
	if _pack_visual == null:
		_pack_visual = Node3D.new()
		_pack_visual.add_child(MinigameUtil.box(Vector3(0.13, 0.035, 0.1), Color(0.85, 0.2, 0.12), Vector3(0, 0.0175, 0)))
		_pack_visual.add_child(MinigameUtil.box(Vector3(0.07, 0.036, 0.05), Color(0.95, 0.8, 0.2), Vector3(-0.02, 0.018, 0)))
	_pack.add_child(_pack_visual)
	_pack_home = _pack_visual.transform
	# timer display
	if not timer_label_path.is_empty() and has_node(timer_label_path):
		_timer_label = get_node(timer_label_path) as Label3D
	else:
		_timer_label = MinigameUtil.label("--:--", 24, 0.0028, Color(1.0, 0.35, 0.25), display_font)
		var td := get_anchor("TimerDisplay")
		(td if td else self).add_child(_timer_label)
	_update_timer_label()

# ---------------------------------------------------------------- flow
func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)
	_update_visuals()

func _on_start() -> void:
	heat = 0.0
	cook = 0.0
	overboil = 0.0
	did_boil_over = false
	stove_on = false
	_pack.visible = true
	_pack_visual.transform = _pack_home
	_set_state(State.EMPTY)

func _on_reset() -> void:
	_on_start()
	_set_state(State.EMPTY)

func _pot_prompt() -> String:
	return "Đổ nước vào nồi" if _active and state == State.EMPTY else ""

func _knob_prompt() -> String:
	if not _active:
		return ""
	return "Tắt bếp" if stove_on else "Bật bếp"

func _pack_prompt() -> String:
	return "Cho mì vào nồi" if _active and (state == State.WATER or state == State.BOILING) else ""

func fill_water() -> void:
	if not _active or state != State.EMPTY:
		return
	sfx("water_drip", _pot_btn, 2.0, 0.8)
	_set_state(State.WATER)

func toggle_stove() -> void:
	if not _active:
		return
	if not stove_on:
		if state == State.EMPTY:
			toast("Nồi chưa có nước.")
			return
		stove_on = true
		sfx("stove_click", _knob)
	else:
		stove_on = false
		sfx("stove_click", _knob, -8.0, 1.3)
		if state == State.READY:
			_set_state(State.DONE)
			complete()
			return
		if state == State.COOKING:
			toast("Mì chưa chín.")
	_update_visuals()

func add_noodles() -> void:
	if not _active:
		return
	if state == State.WATER:
		toast("Nước chưa sôi.")
		return
	if state != State.BOILING:
		return
	sfx("item_drop", _pot_btn, -6.0)
	var t := create_tween()
	t.tween_property(_pack_visual, "global_position", _noodles.global_position + Vector3(0, 0.12, 0), 0.25)
	t.tween_callback(func(): _pack.visible = false)
	cook = 0.0
	_set_state(State.COOKING)
	toast("Chờ %d giây..." % int(cook_time))

func _tick(delta: float) -> void:
	if stove_on:
		match state:
			State.WATER:
				heat += delta
				if heat >= heat_time:
					_set_state(State.BOILING)
					toast("Nước sôi rồi.")
			State.COOKING:
				cook += delta
				if cook >= cook_time:
					_set_state(State.READY)
					toast("Mì chín rồi. Tắt bếp.")
			State.READY:
				overboil += delta
				if overboil >= overboil_time and not did_boil_over:
					_boil_over()
	_blink += delta
	_update_timer_label()

func _boil_over() -> void:
	did_boil_over = true
	_foam.visible = true
	sfx("water_boil", _pot_btn, 4.0, 1.25)
	toast("Nồi trào rồi! Tắt bếp đi!")
	boiled_over.emit()

func _process(delta: float) -> void:
	super._process(delta)
	if _flame.visible:
		var f := 0.85 + randf() * 0.3
		_flame.scale = Vector3(1, f, 1)
		_flame_light.light_energy = 0.6 + randf() * 0.35

func _update_visuals() -> void:
	_water.visible = state >= State.WATER
	_noodles.visible = state >= State.COOKING
	_flame.visible = stove_on
	var boiling := stove_on and state >= State.BOILING and state != State.DONE
	_steam.emitting = boiling
	if _boil_audio.stream:
		if boiling and not _boil_audio.playing:
			_boil_audio.play()
		elif not boiling and _boil_audio.playing:
			_boil_audio.stop()

func _update_timer_label() -> void:
	if _timer_label == null:
		return
	var txt := "--:--"
	match state:
		State.WATER:
			txt = "--:--" if not stove_on else ("..." if int(_blink * 2.0) % 2 == 0 else ". .")
		State.BOILING:
			txt = "00:%02d" % int(cook_time) if int(_blink * 2.0) % 2 == 0 else ""
		State.COOKING:
			txt = "00:%02d" % ceili(maxf(cook_time - cook, 0.0))
		State.READY:
			txt = "00:00" if int(_blink * 2.0) % 2 == 0 else ""
		State.DONE:
			txt = "00:00"
	_timer_label.text = txt

func time_left() -> float:
	return maxf(cook_time - cook, 0.0)

# ---------------------------------------------------------------- debug / tests
func _autoplay() -> void:
	fill_water()
	toggle_stove()
	advance(heat_time + 0.2)
	await get_tree().create_timer(0.1).timeout
	if not _active:
		return
	add_noodles()
	advance(cook_time + 0.2)
	await get_tree().create_timer(0.1).timeout
	toggle_stove()

func debug_shot_prep(_player: Node3D) -> void:
	fill_water()
	toggle_stove()
	advance(heat_time + 0.2)
	add_noodles()
	advance(cook_time * 0.4)
