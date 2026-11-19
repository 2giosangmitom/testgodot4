class_name MinigameItem
extends Interactable
## A holdable minigame object (product, cardboard box, mop...). Physics layers interactable(4)+pickup(32).
## interact() -> player.hold_item(self). Held state is polled from player.get_held_item(), so it also
## works if the Player picks layer-6 bodies up by itself.
##
## While held: collision is disabled (the player's interact ray passes through it to shelves,
## scanners...), and it can be rotated:
##   * if the player has `signal held_item_rotated(relative: Vector2)` (mouse pixels while RMB held),
##     the item rotates itself around the camera axes on that signal;
##   * otherwise it reads RMB (`secondary`) + mouse motion itself.
## When released by the player (not consumed by a minigame) it returns to where it was picked up.

signal picked_up(player: Node3D)
signal released(player: Node3D)

@export var pickable := true
@export var pickup_prompt := "Cầm lên"
@export var rotate_sensitivity := 0.012
@export var self_rotate := true
@export var return_home_on_release := true
## Offset from the player's hold point while held (box is held lower/closer than a can).
@export var held_offset := Vector3.ZERO

## Minigame-specific payload (product resource, index...).
var data: Dictionary = {}
## Optional overrides: prompt_override() -> String ("" = default), interact_override(player) -> bool (true = handled).
var prompt_override: Callable
var interact_override: Callable
## Set by minigames when the item was used up (scanned, placed): no return-home on release.
var consumed := false

var home_transform: Transform3D
var _home_parent: Node
var _held := false
var _player: Node3D
var _layer_backup := 0
var _home_tween: Tween

func _ready() -> void:
	super._ready()
	collision_layer = MinigameUtil.LAYER_INTERACTABLE | MinigameUtil.LAYER_PICKUP
	_layer_backup = collision_layer
	add_to_group("minigame_item")
	if not _home_parent:
		remember_home()

func remember_home() -> void:
	_home_parent = get_parent()
	if is_inside_tree():
		home_transform = global_transform

static func find_player(from: Node) -> Node3D:
	if GameState.player and is_instance_valid(GameState.player):
		return GameState.player
	if from and from.is_inside_tree():
		return from.get_tree().get_first_node_in_group("player") as Node3D
	return null

func get_prompt() -> String:
	if not enabled:
		return ""
	if prompt_override.is_valid():
		var p: String = prompt_override.call()
		if p != "":
			return p
	if not pickable or is_held():
		return ""
	var pl := find_player(self)
	if pl and pl.has_method("get_held_item") and pl.get_held_item() != null:
		return ""
	return pickup_prompt

func can_interact(player: Node3D) -> bool:
	return enabled and get_prompt() != ""

func _on_interact(player: Node3D) -> void:
	if interact_override.is_valid() and interact_override.call(player):
		return
	pick_up(player)

func is_held() -> bool:
	var pl := find_player(self)
	return pl != null and pl.has_method("get_held_item") and pl.get_held_item() == self

func pick_up(player: Node3D) -> bool:
	if not pickable or player == null or not player.has_method("hold_item"):
		return false
	if player.has_method("get_held_item") and player.get_held_item() != null:
		return false
	if _home_tween:
		_home_tween.kill()
	remember_home()
	consumed = false
	player.hold_item(self)
	AudioDirector.play_sfx("item_pickup", -4.0, randf_range(0.95, 1.05))
	_update_held_state()
	return true

## Used by minigames: makes the player let go of this item without returning it home.
func release_from_player(mark_consumed := true) -> void:
	consumed = mark_consumed
	var pl := find_player(self)
	if pl and pl.has_method("get_held_item") and pl.get_held_item() == self and pl.has_method("release_item"):
		pl.release_item()
	_update_held_state()

func _physics_process(_delta: float) -> void:
	_update_held_state()
	if _held and _player and _player.has_method("get_hold_point"):
		var hp: Node3D = _player.get_hold_point()
		if hp and not top_level:
			if hp.is_ancestor_of(self):
				if get_parent() == hp:
					position = held_offset
			else:
				# Player does not reparent held items: follow the hold point ourselves.
				global_position = hp.global_transform * held_offset

func _update_held_state() -> void:
	var now := is_held()
	if now == _held:
		return
	_held = now
	if now:
		_player = find_player(self)
		collision_layer = 0
		if _player and _player.has_signal("held_item_rotated") and not _player.is_connected("held_item_rotated", _on_player_rotated):
			_player.connect("held_item_rotated", _on_player_rotated)
		picked_up.emit(_player)
	else:
		if _player and _player.has_signal("held_item_rotated") and _player.is_connected("held_item_rotated", _on_player_rotated):
			_player.disconnect("held_item_rotated", _on_player_rotated)
		collision_layer = _layer_backup
		var p := _player
		_player = null
		_restore_parent()
		released.emit(p)
		if return_home_on_release and not consumed:
			go_home()

## If the player left us parented under its camera, move back to our original parent.
func _restore_parent() -> void:
	if not is_inside_tree() or _home_parent == null or not is_instance_valid(_home_parent):
		return
	if get_parent() != _home_parent:
		var gt := global_transform
		get_parent().remove_child(self)
		_home_parent.add_child(self)
		global_transform = gt

func go_home(duration := 0.35) -> void:
	if not is_inside_tree():
		return
	if _home_tween:
		_home_tween.kill()
	_home_tween = create_tween()
	_home_tween.tween_property(self, "global_transform", home_transform, duration).set_trans(Tween.TRANS_QUAD)

func move_to(xform: Transform3D, duration := 0.3) -> Tween:
	if _home_tween:
		_home_tween.kill()
	_home_tween = create_tween()
	_home_tween.tween_property(self, "global_transform", xform, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return _home_tween

func _on_player_rotated(relative: Vector2) -> void:
	if self_rotate:
		rotate_view(relative)

func _unhandled_input(event: InputEvent) -> void:
	if not _held or not self_rotate or _player == null or _player.has_signal("held_item_rotated"):
		return
	if event is InputEventMouseMotion and Input.is_action_pressed("secondary"):
		rotate_view(event.relative)

## Rotates around the camera's up (mouse x) and right (mouse y) axes.
func rotate_view(relative: Vector2) -> void:
	var cam: Camera3D = _player.get_camera() if _player and _player.has_method("get_camera") else null
	var up := cam.global_basis.y if cam else Vector3.UP
	var right := cam.global_basis.x if cam else Vector3.RIGHT
	var b := Basis(up.normalized(), relative.x * rotate_sensitivity) * Basis(right.normalized(), relative.y * rotate_sensitivity)
	global_basis = (b * global_basis).orthonormalized()
