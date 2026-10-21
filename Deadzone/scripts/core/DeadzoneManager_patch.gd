# DeadzoneManager patch — add tutorial_step to save (append to DeadzoneManager.gd)
# To wire: In DeadzoneManager.gd save_game(), add:
#   data["tutorial_step"] = Tutorial.step if has_node("/root/Tutorial") else 0
#   data["tutorial_done"] = Tutorial.completed
# And in _load_save(), after buildings:
#   if json.has("tutorial_step"):
#       var tut = get_node_or_null("/root/Tutorial")
#       if tut: tut.step = int(json["tutorial_step"]); tut.completed = bool(json.get("tutorial_done", false))

# This file is documentation — already applied in next commit.
pass
