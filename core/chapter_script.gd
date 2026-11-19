class_name ChapterScript
extends Node
## Base for chapters/chN.gd. Implement run(from_checkpoint) as a sequence of awaited beats.

func run(_from_checkpoint := "") -> void:
	pass

# --- helpers for beat scripts ---
func wait(seconds: float) -> void:
	if GameState.debug_autoplay:
		seconds = min(seconds, 0.05)
	await get_tree().create_timer(seconds).timeout

func objective(id: String, text: String) -> void:
	GameState.add_objective(id, text)
	EventBus.toast.emit(text)

## Waits until an objective is completed (debug autoplay completes it immediately).
func wait_objective(id: String) -> void:
	if GameState.debug_autoplay:
		GameState.complete_objective(id)
	while not GameState.is_objective_done(id):
		await EventBus.objective_completed

func wait_flag(flag: String) -> void:
	if GameState.debug_autoplay:
		GameState.set_flag(flag)
	while not GameState.get_flag(flag):
		await EventBus.flag_changed

func checkpoint(id: String) -> void:
	SaveSystem.save_checkpoint(id)
