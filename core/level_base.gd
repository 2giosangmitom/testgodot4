class_name LevelBase
extends Node3D
## Root script for every level scene (levels/*/<name>.tscn).
## Expected children (by convention, see docs/conventions.md):
##   Spawns/      Marker3D children; name = spawn id ("default", "store_front", ...)
##   Markers/     Marker3D children for cutscene cameras, entity spawns, etc.
##   Presets/     LightingPreset children; name = preset id ("day", "night", "ch3_night")
##   Entities/    container for spawned entities

const PLAYER_SCENE := "res://player/player.tscn"

@export var level_id := ""
@export var default_preset := "night"

var player: Node3D

func _ready() -> void:
	add_to_group("level")
	if not GameState.player and get_tree().current_scene == self and not has_node("Spawns"):
		return

func apply_preset(preset_id: String) -> void:
	var presets := get_node_or_null("Presets")
	if presets == null:
		return
	for p in presets.get_children():
		if p.has_method("set_active"):
			p.set_active(p.name == preset_id)

func spawn_player(spawn_id := "default") -> Node3D:
	var marker := get_spawn(spawn_id)
	if player == null:
		if GameState.player and is_instance_valid(GameState.player):
			player = GameState.player
		elif ResourceLoader.exists(PLAYER_SCENE):
			player = load(PLAYER_SCENE).instantiate()
			add_child(player)
	if player and marker:
		if player.has_method("teleport"):
			player.teleport(marker.global_transform)
		else:
			player.global_transform = marker.global_transform
	return player

func get_spawn(id: String) -> Marker3D:
	return get_node_or_null("Spawns/" + id) as Marker3D

func get_marker(id: String) -> Node3D:
	return get_node_or_null("Markers/" + id) as Node3D
