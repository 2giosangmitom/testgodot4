extends SceneTree
## Launcher for the entity logic tests (prints PASS/FAIL, exit code 0/1).
##   godot --headless --path . -s res://gameplay/entities/test/run_logic_tests.gd
## The tests live in logic_tests.gd and are loaded at runtime so that autoload globals
## (EventBus, GameState, ...) are registered before the entity scripts compile.

func _initialize() -> void:
	var script: Script = load("res://gameplay/entities/test/logic_tests.gd")
	if script == null:
		print("RESULT: FAIL (cannot load logic_tests.gd)")
		quit(1)
		return
	var runner: Node = script.new()
	runner.done.connect(func(code: int): quit(code))
	root.add_child.call_deferred(runner)
	# safety net: never hang CI
	create_timer(90.0).timeout.connect(func():
		print("RESULT: FAIL (timeout)")
		quit(1))
