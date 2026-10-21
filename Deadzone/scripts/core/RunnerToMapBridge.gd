# RunnerToMapBridge.gd — Add to Runner's Game Over to hook into Map
# Attach to Runner scene or call from HUD.gd game_over()

extends Node

# Call this instead of DeadzoneManager.on_runner_finished directly when Map exists
func finish_runner_to_map(run_result: Dictionary):
	# run_result has food/metal/score etc. from Runner
	DeadzoneManager.on_runner_finished(run_result)
	# If we were attacking a map tile, clear it
	var target = run_result.get("map_target")
	if target is Vector2i:
		# We need WorldMap instance — it may not be in current scene (Runner), so store pending
		DeadzoneManager.last_run["pending_clear"] = target
		DeadzoneManager.save_game()
	# Now go to Map (not Base) — LastZ flow: Runner → Map reveal
	DeadzoneManager.save_game()
	get_tree().change_scene_to_file("res://scenes/Map.tscn")

# Call from Map's _ready to apply pending clear
func apply_pending_clear(world_map: WorldMap):
	var pending = DeadzoneManager.last_run.get("pending_clear")
	if pending is Vector2i:
		# Need to handle if pending was saved as Dictionary {"x":..,"y":..} from JSON
		world_map.on_runner_victory(pending)
		DeadzoneManager.last_run.erase("pending_clear")
		DeadzoneManager.save_game()
	elif pending is Dictionary:
		var c = Vector2i(int(pending.get("x",0)), int(pending.get("y",0)))
		world_map.on_runner_victory(c)
		DeadzoneManager.last_run.erase("pending_clear")
