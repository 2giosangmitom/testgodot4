class_name LightingPreset
extends Node3D
## A named lighting setup inside a level (Presets/<id>). Children lights/WorldEnvironment are
## enabled only while this preset is active. Also sets the global PSX fog preset and ambience.

@export var fog_preset := "night"
@export var ambience := ""            # AudioDirector ambience name for layer "base"
@export var ambience_hum := ""        # optional second layer "hum"
@export var clock_hours := -1          # set GameState clock when applied (-1 = keep)

func _ready() -> void:
	if not is_active():
		_set_children(false)

func is_active() -> bool:
	return visible

func set_active(on: bool) -> void:
	visible = on
	_set_children(on)
	if on:
		RenderSettings.set_fog_preset(fog_preset, 0.0)
		if ambience != "":
			AudioDirector.play_ambience(ambience, "base")
		if ambience_hum != "":
			AudioDirector.play_ambience(ambience_hum, "hum", -6.0)
		else:
			AudioDirector.stop_ambience("hum")
		if clock_hours >= 0:
			GameState.set_clock(clock_hours)

func _set_children(on: bool) -> void:
	for c in get_children():
		if c is Light3D:
			c.visible = on
		elif c is WorldEnvironment:
			# Only one WorldEnvironment may be active: park the resource in meta while inactive.
			if not c.has_meta("env") and c.environment:
				c.set_meta("env", c.environment)
			c.environment = c.get_meta("env", null) if on else null
		elif c is Node3D:
			c.visible = on
