extends Node3D
## Headless integration checks for Track B (player / props / phone contracts).
##   godot --headless --path . res://player/test_integration.tscn
## Prints PASS/FAIL lines and quits with exit code = failures.

var failures := 0
var door_events: Array = []

func check(cond: bool, name: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + name)
	if not cond:
		failures += 1

func _ready() -> void:
	GameState.reset()
	ProtoGeo.box(self, Vector3(10, 0.2, 10), Vector3(0, -0.1, 0), Color.GRAY)
	EventBus.door_state_changed.connect(func(id: String, o: bool): door_events.append([id, o]))
	var player: Player = load("res://player/player.tscn").instantiate()
	add_child(player)
	player.teleport(Transform3D(Basis(), Vector3(0, 0, 2)))
	await _frames(5)
	check(GameState.player == player and player.is_in_group("player"), "player registered")
	check(get_tree().get_first_node_in_group("hud") != null, "HUD instanced by player")
	check(player.get_camera().near <= 0.051 and is_equal_approx(player.get_camera().fov, 70.0), "camera near/fov")
	for m in ["get_camera", "teleport", "is_crouching", "is_sprinting", "is_hidden", "look_at_point",
			"set_controls_enabled", "hold_item", "release_item", "get_held_item", "kill", "get_hold_point"]:
		check(player.has_method(m), "player." + m)
	check(player.has_signal("held_item_rotated"), "signal held_item_rotated")

	# --- door duck-typing (Mimic / room_routine)
	var door: Door = load("res://gameplay/props/door.tscn").instantiate()
	door.door_id = "d1"
	door.position = Vector3(-0.45, 0, -1)
	add_child(door)
	await _frames(2)
	check("open" in door and door.open == false and door.is_open == false, "door open alias")
	door.lock()
	check(door.is_locked() and door.locked and door.get_prompt() == "Khóa", "door lock + prompt")
	door.interact(player)
	await _frames(2)
	check(not door.is_open, "locked door stays shut on interact")
	door.force_open(0.2)
	await get_tree().create_timer(0.4).timeout
	check(door.is_open and not door.locked and absf(door._angle) > 60.0, "force_open ignores lock")
	check(door_events.has(["d1", true]), "door_state_changed(open)")
	await door.close(0.1)
	check(not door.is_open and door_events.has(["d1", false]), "door close + signal")
	door.open_door(player.global_position, 0.2)
	await get_tree().create_timer(0.35).timeout
	check(door._angle > 60.0, "door swings away from player (+Z side)")

	# --- hold / release
	var can: PickupItem = load("res://gameplay/props/pickup_item.tscn").instantiate()
	can.item_id = "can"
	add_child(can)
	can.global_position = Vector3(1, 0, 1)
	await _frames(1)
	can.interact(player)
	await _frames(2)
	check(player.get_held_item() == can and can.get_parent() == player.get_hold_point(), "hold_item reparents to hold point")
	check(can.collision_layer == 0, "held item collision off")
	var rel := [Vector2.ZERO]
	var cb := func(r: Vector2): rel[0] = r
	player.held_item_rotated.connect(cb)
	player._rotate_held(Vector2(5, -3))
	check(rel[0] == Vector2(5, -3), "held_item_rotated(relative)")
	player.held_item_rotated.disconnect(cb)
	var released := player.release_item()
	await _frames(2)
	check(released == can and player.get_held_item() == null and can.get_parent() == self, "release_item lets go")
	check(can.collision_layer == 32 and can.enabled, "released item restored (layer 6, enabled)")
	check(can.global_position.y < 0.2, "released item dropped to floor")

	# --- inventory item
	var inc: PickupItem = load("res://gameplay/props/pickup_item.tscn").instantiate()
	inc.item_id = "incense"
	inc.inventory_item = true
	add_child(inc)
	await _frames(1)
	inc.interact(player)
	check(GameState.get_flag("has_incense") == true, "inventory pickup sets has_<id>")

	# --- trigger
	var trig: TriggerZone = load("res://gameplay/props/trigger_zone.tscn").instantiate()
	trig.trigger_id = "t"
	trig.position = Vector3(3, 0, 3)
	add_child(trig)
	await _frames(2)
	player.teleport(Transform3D(Basis(), Vector3(3, 0, 3)))
	await _frames(6)
	check(GameState.get_flag("trig_t") == true, "trigger sets trig_<id>")

	# --- phone read flags
	var phone := get_tree().get_first_node_in_group("phone")
	check(phone != null, "phone instanced")
	var ids := Dialogue.messages.keys()
	if ids.size() > 0:
		GameState.unlock_message(ids[0])
		phone.open()
		check(GameState.phone_open, "phone_open flag")
		phone._activate()   # unlock
		phone._move(1)      # Tin nhắn
		phone._activate()   # threads
		phone._activate()   # first thread
		await _frames(2)
		check(GameState.get_flag("read_" + ids[0]) == true, "reading sets read_<msg_id>")
		phone.close()
		check(not GameState.phone_open, "phone closed")

	# --- flashlight
	player.set_flashlight(true)
	check(GameState.flashlight_on and player.flashlight.visible, "flashlight on")
	player.set_flashlight(false)

	# --- crouch / hide
	var hs: HideSpot = load("res://gameplay/props/hide_spot.tscn").instantiate()
	hs.position = Vector3(-3, 0, 3)
	add_child(hs)
	player.teleport(Transform3D(Basis(), Vector3(-3, 0, 3)))
	player._crouch_toggled = true
	await _frames(8)
	check(player.is_crouching() and player.is_hidden(), "crouched in hide spot -> hidden")
	player._crouch_toggled = false
	await _frames(4)
	check(not player.is_hidden(), "standing -> not hidden")

	print("\n%s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
	get_tree().quit(failures)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
