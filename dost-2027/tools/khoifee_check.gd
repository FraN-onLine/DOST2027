extends SceneTree

# Validation: the hidden dev hook in Network.planned_trial_order() - a host
# whose name is KHOIFEE gets a run of Bathala alone, straight into Agawan Base
# (a testing shortcut). It fires on that exact name in any case, never inside a
# longer name, and never changes anybody else's order.
# Run: godot --headless --path <project> -s res://tools/khoifee_check.gd

var _problems := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	await process_frame  # let the autoloads finish _ready
	var net: Node = root.get_node("Network")
	var original: String = net.my_name

	net.my_name = "KHOIFEE"
	var dev_order: Array[StringName] = net.planned_trial_order()
	_check(dev_order.size() == 1 and dev_order[0] == Gods.BATHALA,
		"a host named KHOIFEE plans Bathala only")

	net.my_name = "khoifee"
	dev_order = net.planned_trial_order()
	_check(dev_order.size() == 1 and dev_order[0] == Gods.BATHALA,
		"the name matches in any case")

	net.run_settings = RunSettings.defaults()
	net.my_name = "KHOIFEE TWO"
	var order: Array[StringName] = net.planned_trial_order()
	_check(order.size() == net.run_settings.trials + 1 and order[order.size() - 1] == Gods.BATHALA,
		"a longer name plays the normal run, ending in Bathala")

	net.my_name = "MYKHOIFEE"
	order = net.planned_trial_order()
	_check(order.size() == net.run_settings.trials + 1,
		"the hook never matches inside a longer name")

	net.my_name = original
	print("khoifee checks: %d problem(s)" % _problems)
	print("--- DONE ---")
	quit(1 if _problems > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		printerr("FAIL: %s" % label)
		_problems += 1
