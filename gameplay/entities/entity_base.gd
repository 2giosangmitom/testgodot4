class_name EntityBase
extends Node3D
## Common base for Gazer / Mimic / CrowdGroup.
## - group `entity`, `entity_id`, activate()/deactivate()/is_active()
## - emits EventBus.entity_state_changed(entity_id, state) on every state change
## - logic runs in tick(delta) (called from _physics_process) so headless tests can drive time.
## - respects GameState.debug_autoplay via is_passive(): never catches / breaches / alerts.

signal state_changed(state: String)

@export var entity_id := ""
## Start active when the scene loads (chapters usually activate via EntityDirector instead).
@export var start_active := false
## Hide the entity while inactive.
@export var hide_when_inactive := true
## Optional explicit player node; default = GameState.player or the "player" group.
@export var player_path: NodePath

var state := "inactive"
## Tests set this to true and call tick() themselves.
var manual_tick := false
## Tests can force passive mode off/on regardless of GameState.debug_autoplay.
var passive_override := -1    # -1 = use GameState.debug_autoplay, 0 = never passive, 1 = always
var caught_player := false
var last_sequence: Node = null

var _active := false
var _player: Node3D = null

func _enter_tree() -> void:
	add_to_group("entity")

func _ready() -> void:
	if entity_id == "":
		entity_id = String(name).to_snake_case()
	if start_active:
		activate.call_deferred()
	elif hide_when_inactive:
		visible = false

func activate() -> void:
	if _active:
		return
	_active = true
	caught_player = false
	visible = true
	_on_activate()

func deactivate() -> void:
	if not _active:
		return
	_active = false
	_on_deactivate()
	set_state("inactive")
	if hide_when_inactive:
		visible = false

func is_active() -> bool:
	return _active

func set_state(s: String) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)
	EventBus.entity_state_changed.emit(entity_id, s)

func _physics_process(delta: float) -> void:
	if _active and not manual_tick:
		tick(delta)

## Override: per-frame logic.
func tick(_delta: float) -> void:
	pass

func _on_activate() -> void:
	pass

func _on_deactivate() -> void:
	pass

func is_passive() -> bool:
	if passive_override >= 0:
		return passive_override == 1
	return GameState.debug_autoplay

func get_player() -> Node3D:
	if _player and is_instance_valid(_player) and _player.is_inside_tree():
		return _player
	_player = null
	if not player_path.is_empty():
		_player = get_node_or_null(player_path) as Node3D
	if _player == null and GameState.player and is_instance_valid(GameState.player):
		_player = GameState.player
	if _player == null and is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player

func set_player(p: Node3D) -> void:
	_player = p

func get_player_camera() -> Camera3D:
	var p := get_player()
	if p == null:
		return null
	if p.has_method("get_camera"):
		return p.get_camera()
	return get_viewport().get_camera_3d() if is_inside_tree() else null

func player_is_hidden() -> bool:
	var p := get_player()
	return p != null and p.has_method("is_hidden") and p.is_hidden()

## Eye position of the player (camera if available).
func get_player_eye() -> Vector3:
	var cam := get_player_camera()
	if cam and cam.is_inside_tree():
		return cam.global_position
	var p := get_player()
	return p.global_position + Vector3.UP * 1.62 if p else Vector3.ZERO

## Shared caught flow: emits EventBus.player_caught and runs CaughtSequence on `body_node`.
## Returns the sequence (await its `finished`), or null when passive / no player.
func catch_player(cause: String, body_node: Node3D = null) -> Node:
	if caught_player or is_passive():
		return null
	caught_player = true
	set_state("caught")
	EventBus.player_caught.emit(entity_id, cause)
	var p := get_player()
	if p == null:
		return null
	last_sequence = CaughtSequence.play(body_node if body_node else self, p)
	return last_sequence

## Resolves a NodePath relative to this node into a Node3D (or null).
func node3d(path: NodePath) -> Node3D:
	if path.is_empty():
		return null
	return get_node_or_null(path) as Node3D

## Loads a model scene by character name if it exists (assets/models/chars/<name>.glb).
static func find_char_model(char_name: String) -> PackedScene:
	if char_name == "":
		return null
	for ext in ["glb", "tscn", "gltf"]:
		var p := "res://assets/models/chars/%s.%s" % [char_name, ext]
		if ResourceLoader.exists(p):
			return load(p)
	return null
