# MainBase.gd — Root controller for base-building scene
# Godot 4.x — attach to Node2D

extends Node2D

@onready var grid: BaseGrid = $BaseGrid
@onready var inspector: BuildingInspector = $CanvasLayer/Inspector
@onready var build_menu: Control = $CanvasLayer/BuildMenu
@onready var top_bar: Control = $CanvasLayer/TopBar
@onready var food_lbl: Label = $CanvasLayer/TopBar/Food
@onready var metal_lbl: Label = $CanvasLayer/TopBar/Metal
@onready var prod_lbl: Label = $CanvasLayer/TopBar/Production

func _ready():
	# Load save (includes offline progress)
	SaveManager.load_game()
	# Wire grid
	grid.building_selected.connect(_on_building_selected)
	grid.building_placed.connect(func(_b): ResourceManager.recalculate_generation(); SaveManager.save_game())
	grid.placement_failed.connect(func(msg): print("[Base] ", msg))
	build_menu.build_selected.connect(func(d): inspector.hide_inspector())
	inspector.upgrade_started.connect(func(_b): SaveManager.save_game())
	# Resources UI
	ResourceManager.resources_updated.connect(_on_resources)
	ResourceManager.production_updated.connect(_on_production)
	ResourceManager.recalculate_generation()
	_on_resources(ResourceManager.food, ResourceManager.metal, ResourceManager.hard_currency)
	# Auto-save every 5s + on pause
	var autosave = Timer.new()
	autosave.wait_time = 5.0
	autosave.autostart = true
	autosave.timeout.connect(func(): SaveManager.save_game())
	add_child(autosave)

func _on_building_selected(b: Building):
	inspector.show_for(b)

func _on_resources(food: int, metal: int, _h: int):
	food_lbl.text = "Food: %d" % food
	metal_lbl.text = "Metal: %d" % metal

func _on_production(food_ps: float, metal_ps: float):
	prod_lbl.text = "+%.1f food/s  +%.1f metal/s" % [food_ps, metal_ps]

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		SaveManager.save_game()
