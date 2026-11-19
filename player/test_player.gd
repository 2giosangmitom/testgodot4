extends Node3D
## Player/UI test room. Gray box room with a Door, light switch, hide spot under a table,
## pickup can, trigger zone, readable note. F1 toggles a GameState debug panel.
## Number keys F2..F8 trigger UI demos. Command line:
##   godot --path . res://player/test_player.tscn -- --shot=/abs.png [--demo=<name>] [--shot_frames=N]
## demos: subtitle choice phone phone_home phone_msgs phone_thread phone_todo toast paper pause
##        settings letterbox hide door dead

const PLAYER := preload("res://player/player.tscn")
const DOOR := preload("res://gameplay/props/door.tscn")
const SWITCH := preload("res://gameplay/props/light_switch.tscn")
const HIDE := preload("res://gameplay/props/hide_spot.tscn")
const PICKUP := preload("res://gameplay/props/pickup_item.tscn")
const TRIGGER := preload("res://gameplay/props/trigger_zone.tscn")
const READABLE := preload("res://gameplay/props/readable.tscn")

var player: Player
var debug_label: Label
var debug_layer: CanvasLayer
var door: Door

func _ready() -> void:
	RenderSettings.set_fog(7.0, 16.0, Color(0.03, 0.03, 0.04), 0.0)
	_build_room()
	player = PLAYER.instantiate()
	add_child(player)
	player.teleport(Transform3D(Basis(), Vector3(0, 0, 2.5)))
	_build_debug()
	GameState.set_clock(23, 47)
	GameState.chapter = 2
	DebugShot.attach_if_requested(self)
	var demo := DebugShot.get_arg("demo")
	if demo != "":
		await get_tree().create_timer(0.3).timeout
		run_demo(demo)

func _build_room() -> void:
	var gray := Color(0.55, 0.55, 0.53)
	ProtoGeo.box(self, Vector3(8, 0.2, 10), Vector3(0, -0.1, 0), Color(0.45, 0.47, 0.45), true, {"surface": "tile", "uv_scale": 8.0})
	ProtoGeo.box(self, Vector3(8, 0.2, 10), Vector3(0, 2.9, 0), Color(0.4, 0.4, 0.4))
	ProtoGeo.box(self, Vector3(0.2, 3, 10), Vector3(-4, 1.4, 0), gray)
	ProtoGeo.box(self, Vector3(0.2, 3, 10), Vector3(4, 1.4, 0), gray)
	ProtoGeo.box(self, Vector3(8, 3, 0.2), Vector3(0, 1.4, 5), gray)
	# back wall with a door opening (0.9 wide) at x = -0.45..0.45
	ProtoGeo.box(self, Vector3(3.55, 3, 0.2), Vector3(-2.225, 1.4, -5), gray)
	ProtoGeo.box(self, Vector3(3.55, 3, 0.2), Vector3(2.225, 1.4, -5), gray)
	ProtoGeo.box(self, Vector3(0.9, 0.7, 0.2), Vector3(0, 2.45, -5), gray)
	# corridor behind the door (wooden floor)
	ProtoGeo.box(self, Vector3(3, 0.2, 4), Vector3(0, -0.1, -7), Color(0.4, 0.3, 0.22), true, {"surface": "wood"})
	ProtoGeo.box(self, Vector3(0.2, 3, 4), Vector3(-1.5, 1.4, -7), gray)
	ProtoGeo.box(self, Vector3(0.2, 3, 4), Vector3(1.5, 1.4, -7), gray)
	ProtoGeo.box(self, Vector3(3, 3, 0.2), Vector3(0, 1.4, -9), gray)
	ProtoGeo.box(self, Vector3(3, 0.2, 4), Vector3(0, 2.9, -7), Color(0.4, 0.4, 0.4))
	door = DOOR.instantiate()
	door.door_id = "test_door"
	door.position = Vector3(-0.45, 0, -5)
	add_child(door)
	# table with hide spot under it
	var table := Node3D.new()
	table.position = Vector3(2.6, 0, -1.5)
	add_child(table)
	ProtoGeo.box(table, Vector3(1.4, 0.06, 0.8), Vector3(0, 0.75, 0), Color(0.45, 0.33, 0.22))
	for x in [-0.62, 0.62]:
		for z in [-0.34, 0.34]:
			ProtoGeo.box(table, Vector3(0.06, 0.72, 0.06), Vector3(x, 0.36, z), Color(0.3, 0.22, 0.15))
	var hide: HideSpot = HIDE.instantiate()
	hide.size = Vector3(1.2, 0.7, 0.7)
	table.add_child(hide)
	var can: PickupItem = PICKUP.instantiate()
	can.item_id = "can"
	can.position = Vector3(2.4, 0.78, -1.4)
	add_child(can)
	var incense: PickupItem = PICKUP.instantiate()
	incense.item_id = "incense"
	incense.display_name = "Bó nhang"
	incense.inventory_item = true
	incense.position = Vector3(2.9, 0.78, -1.6)
	add_child(incense)
	# light + switch
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 2.6, 0)
	lamp.omni_range = 9.0
	lamp.light_energy = 1.4
	lamp.light_color = Color(0.85, 0.95, 0.85)
	lamp.add_to_group("test_lights")
	add_child(lamp)
	var sw: LightSwitch = SWITCH.instantiate()
	sw.light_group = "test_lights"
	sw.position = Vector3(-3.85, 1.3, 3.5)
	sw.rotation.y = PI / 2
	add_child(sw)
	var note: Readable = READABLE.instantiate()
	note.readable_id = "rules_note"
	note.position = Vector3(-3.85, 1.5, 1.0)
	note.rotation.y = PI / 2
	add_child(note)
	ProtoGeo.box(note, Vector3(0.3, 0.4, 0.01), Vector3.ZERO, Color(0.85, 0.82, 0.7), false)
	var trig: TriggerZone = TRIGGER.instantiate()
	trig.trigger_id = "corridor"
	trig.size = Vector3(2.6, 2, 1.5)
	trig.position = Vector3(0, 0, -7.5)
	trig.triggered.connect(func(_b): EventBus.toast.emit("Trigger: corridor"))
	add_child(trig)
	var amb := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.12, 0.14)
	amb.environment = env
	add_child(amb)

func _build_debug() -> void:
	debug_layer = CanvasLayer.new()
	debug_layer.layer = 125
	add_child(debug_layer)
	debug_label = Label.new()
	debug_label.theme = preload("res://ui/theme.tres")
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.position = Vector2(8, 120)
	debug_label.visible = false
	debug_layer.add_child(debug_label)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_F1: debug_label.visible = not debug_label.visible
		KEY_F2: run_demo("subtitle")
		KEY_F3: run_demo("choice")
		KEY_F4: run_demo("toast")
		KEY_F5: run_demo("msg")
		KEY_F6: run_demo("letterbox")
		KEY_F7: run_demo("look")
		KEY_F8: run_demo("dead")

func _process(_dt: float) -> void:
	if debug_label.visible:
		var s := "chapter %d  phase %s  clock %s\n" % [GameState.chapter, GameState.phase, GameState.clock_string()]
		s += "locks %s  phone %s  flash %s\n" % [GameState.input_locks.keys(), GameState.phone_open, GameState.flashlight_on]
		s += "stamina %.0f  exhausted %s  crouch %s  hidden %s  sprint %s\n" % [player.stamina, player.exhausted, player.is_crouching(), player.is_hidden(), player.is_sprinting()]
		s += "held %s\nflags %s\nobjectives %s\nmsgs %s" % [player.get_held_item(), GameState.flags, GameState.objectives, GameState.unlocked_messages]
		debug_label.text = s

func _phone() -> Node:
	return get_tree().get_first_node_in_group("phone")

func run_demo(demo: String) -> void:
	match demo:
		"subtitle":
			EventBus.subtitle.emit("Hùng", "Ê Nam, tối nay mày trực à? Nhớ khóa cửa cẩn thận, dạo này ngõ mình lạ lắm.", 4.0)
		"choice":
			EventBus.subtitle.emit("???", "Nam ơi... mở cửa cho tao vào với. Tao quên chìa khóa.", 30.0)
			var i := await Dialogue.ask("Giọng Hùng gọi ngoài cửa", PackedStringArray(["Mở cửa", "Im lặng", "Hỏi: \"Mày là ai?\""]))
			EventBus.toast.emit("Chọn: %d" % i)
		"toast":
			GameState.add_objective("t1", "Quét mã vạch hàng mới về")
			GameState.add_objective("t2", "Lau sàn khu đồ uống")
			EventBus.toast.emit("Đã lưu tiến trình")
		"msg":
			_seed_messages()
		"phone", "phone_home", "phone_msgs", "phone_thread", "phone_todo":
			_seed_messages()
			GameState.add_objective("o1", "Khóa cửa phòng")
			GameState.add_objective("o2", "Nấu mì")
			GameState.complete_objective("o2")
			GameState.add_objective("o3", "Đọc tin nhắn của Hùng")
			await get_tree().create_timer(0.2).timeout
			var ph := _phone()
			ph.open()
			if demo == "phone_home" or demo == "phone_msgs" or demo == "phone_thread" or demo == "phone_todo":
				ph._activate()
			if demo == "phone_msgs" or demo == "phone_thread":
				ph._move(1)
				ph._activate()
			if demo == "phone_todo":
				ph._activate()
			if demo == "phone_thread":
				ph._activate()
		"paper":
			door.interact(player)
			await get_tree().create_timer(0.1).timeout
			var note := get_tree().get_nodes_in_group("interactable").filter(func(n): return n is Readable)[0] as Readable
			note.interact(player)
		"pause":
			get_tree().get_first_node_in_group("hud").pause_menu.open()
		"settings":
			var pm = get_tree().get_first_node_in_group("hud").pause_menu
			pm.open()
			pm._open_settings()
		"letterbox":
			EventBus.letterbox.emit(true)
			EventBus.subtitle.emit("Bác Tư bảo vệ", "Cháu về muộn thế. Đi đường cẩn thận nhé.", 3.0)
		"hide":
			player.teleport(Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2.6, 0, -0.6)))
			player._crouch_toggled = true
		"door":
			player.teleport(Transform3D(Basis(), Vector3(0.1, 0, -3.6)))
			await get_tree().create_timer(0.2).timeout
			door.interact(player)
		"look":
			await player.look_at_point(door.global_position + Vector3(0.45, 1.5, 0), 1.5)
		"dead":
			player.kill("test")
		"pickup":
			player.teleport(Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(1.6, 0, -1.4)))
			player._pitch = deg_to_rad(-35)
			await get_tree().create_timer(0.3).timeout
			player._do_interact()
		"prompt":
			player.teleport(Transform3D(Basis(), Vector3(0.0, 0, -3.8)))
			player.stamina = 45.0
		"flash":
			player.set_flashlight(true)
			player.teleport(Transform3D(Basis(), Vector3(0, 0, -6)))

func _seed_messages() -> void:
	var ids := Dialogue.messages.keys()
	for i in mini(5, ids.size()):
		GameState.unlock_message(ids[i])
