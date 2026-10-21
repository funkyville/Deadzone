# MapUI.gd — Inspector for HQ/Map like LastZ
# Attach to CanvasLayer

extends CanvasLayer

@onready var hq_label: Label = $TopBar/HQLevel
@onready var radius_label: Label = $TopBar/Radius
@onready var expand_btn: Button = $TopBar/ExpandBtn
@onready var map_info: Label = $MapInfo
@onready var attack_btn: Button = $MapInfo/AttackBtn
@onready var back_btn: Button = $TopBar/BackToBaseBtn
@onready var world: WorldMap = get_node("/root/Main/WorldMap") # adjust path as needed

var selected: MapTile = null

func _ready():
	expand_btn.pressed.connect(_on_expand)
	attack_btn.pressed.connect(_on_attack)
	back_btn.pressed.connect(func(): DeadzoneManager.go_base())
	var wm = get_tree().get_first_node_in_group("world_map") as WorldMap
	if wm:
		wm.tile_selected.connect(_on_tile_selected)
		wm.tile_cleared.connect(func(_t,_r): _refresh_hq())
		wm.hq_expanded.connect(func(_r): _refresh_hq())
	_refresh_hq()

func _refresh_hq():
	var wm = get_tree().get_first_node_in_group("world_map") as WorldMap
	if not wm: return
	hq_label.text = "HQ Lv.%d" % wm.hq_level
	radius_label.text = "Radius: %d" % wm.hq_radius
	var cost_f = 80 + wm.hq_level * 60
	var cost_m = 50 + wm.hq_level * 40
	expand_btn.text = "Expand HQ (%d Food, %d Metal)" % [cost_f, cost_m]
	expand_btn.disabled = not DeadzoneManager.can_afford(cost_f, cost_m)

func _on_tile_selected(tile: MapTile):
	selected = tile
	map_info.visible = true
	map_info.text = "%s  %s\nDiff %d  Reward +%d Food +%d Metal" % [str(tile.coord), tile.label(), tile.difficulty, tile.reward_food, tile.reward_metal]
	attack_btn.visible = tile.can_attack()
	attack_btn.text = "⚔ Attack Lv.%d" % tile.difficulty if tile.can_attack() else "Locked"

func _on_attack():
	if not selected or not selected.can_attack(): return
	# Launch Runner with difficulty = tile difficulty
	DeadzoneManager.last_run["map_target"] = selected.coord
	DeadzoneManager.save_game()
	# Pass difficulty via autoload
	DeadzoneManager.last_run["difficulty"] = selected.difficulty
	get_tree().change_scene_to_file("res://scenes/Runner.tscn")

func _on_expand():
	var wm = get_tree().get_first_node_in_group("world_map") as WorldMap
	if wm and wm.upgrade_hq():
		_refresh_hq()
		map_info.text = "🏠 HQ Expanded! New radius %d" % wm.hq_radius
