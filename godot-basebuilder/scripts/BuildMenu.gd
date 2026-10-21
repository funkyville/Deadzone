# BuildMenu.gd — UI to select Headquarters / Farm / Barracks to place
# Godot 4.x — attach to Control with buttons

extends Control

signal build_selected(data: BuildingData)

@onready var hq_btn: Button = $VBox/HQBtn
@onready var farm_btn: Button = $VBox/FarmBtn
@onready var barracks_btn: Button = $VBox/BarracksBtn
@onready var cancel_btn: Button = $VBox/CancelBtn
@onready var info_label: Label = $VBox/Info

var current_data: BuildingData = null

func _ready():
	hq_btn.pressed.connect(func(): _select(BuildingData.make_hq()))
	farm_btn.pressed.connect(func(): _select(BuildingData.make_farm()))
	barracks_btn.pressed.connect(func(): _select(BuildingData.make_barracks()))
	cancel_btn.pressed.connect(_cancel)
	ResourceManager.resources_updated.connect(_on_resources)
	_update_info()

func _select(d: BuildingData):
	current_data = d
	build_selected.emit(d)
	var grid = get_tree().get_first_node_in_group("grid") as BaseGrid
	if grid:
		grid.set_ghost(d)
	info_label.text = "Placing: %s (%dx%d) — Click grid\nCost: %d Food, %d Metal" % [
		d.display_name, d.size.x, d.size.y, d.build_cost_food, d.build_cost_metal]
	add_theme_color_override("font_color", Color.GREEN if ResourceManager.can_afford(d.build_cost_food, d.build_cost_metal) else Color.RED)

func _cancel():
	current_data = null
	var grid = get_tree().get_first_node_in_group("grid") as BaseGrid
	if grid:
		grid.clear_ghost()
	info_label.text = "Select a building to place."

func _on_resources(_f, _m, _h):
	_update_info()

func _update_info():
	if current_data:
		_select(current_data) # refresh afford check
