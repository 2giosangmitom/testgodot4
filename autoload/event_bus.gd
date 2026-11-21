extends Node
## Global signal hub. Systems emit/listen here instead of holding direct references.
## Do not add signals in tracks — request them; the list below is the contract.

# --- Player / interaction ---
signal interacted(target: Node)
signal interact_prompt(text: String)            # "" hides the prompt
signal flashlight_toggled(on: bool)
signal phone_toggled(open: bool)
signal noise_emitted(position: Vector3, loudness: float)   # 0..1 (walk 0.15, sprint 0.8, drop item 0.5)
signal player_hidden_changed(hidden: bool)        # crouched under a desk/counter
signal player_spawned(player: Node3D)

# --- Objectives / story ---
signal objective_added(id: String, text: String)
signal objective_completed(id: String)
signal objectives_reset()
signal minigame_completed(id: String)
signal message_received(msg_id: String)
signal flag_changed(flag: String, value: Variant)
signal resolve_changed(value: int, delta: int, reason: String)
signal chapter_started(chapter: int, phase: String)
signal chapter_finished(chapter: int)
signal checkpoint_reached(id: String)

# --- Dialogue / cutscene (UI listens) ---
signal subtitle(speaker: String, text: String, duration: float)
signal subtitle_clear()
signal choice_requested(prompt: String, options: PackedStringArray)
signal choice_made(index: int)
signal cutscene_started(id: String)
signal cutscene_finished(id: String)
signal letterbox(on: bool)
signal fade_request(to_black: bool, duration: float)
signal fade_done()
signal toast(text: String)                        # small HUD notification

# --- World / horror ---
signal lights_flicker(group_name: String, duration: float)
signal lights_set(group_name: String, on: bool)
signal door_state_changed(door_id: String, open: bool)
signal door_knock(door_id: String)
signal entity_state_changed(entity_id: String, state: String)
signal player_caught(entity_id: String, cause: String)
signal static_amount(value: float)               # 0..1 drives post-fx glitch
signal camera_shake(strength: float, duration: float)
