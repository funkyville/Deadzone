# BaseGrid.gd — 2D grid placement system
# Godot 4.x — attach to Node2D

extends Node2D
class_name BaseGrid

signal building_placed(building: Building)
signal building_selected(building: Building)
signal placement_failed(reason: String)

@export var grid_size: Vector2i = Vector2i(8, 8)
@export var cell_size: int = 64
@export var grid_origin: Vector2 = Vector2.ZERO # top-left world pos

var occupied: Dictionary = {} # Vector2i -> Building (which building owns that cell)
var buildings: Array[Building] = []

@onready var highlight: Node2D = $Highlight
@onready var buildings_root: Node2D = $Buildings

# Currently selected building type to place (null = selection mode)
var ghost_data: BuildingData = null
var ghost_pos: Vector2i = Vector2i(-1,-1)
var ghost_valid: bool = false

func _ready():
	add_to_group("grid")
	if highlight:
		highlight.visible = false
	_update_grid_visual()

func _update_grid_visual():
	queue_redraw()

func _draw():
	# Draw grid lines
	var total = Vector2(grid_size.x * cell_size, grid_size.y * cell_size)
	draw_rect(Rect2(grid_origin, total), Color(0.08, 0.08, 0.12), true)
	for x in range(grid_size.x + 1):
		var px = grid_origin.x + x * cell_size
		draw_line(Vector2(px, grid_origin.y), Vector2(px, grid_origin.y + total.y), Color(0.18, 0.18, 0.25), 1.0)
	for y in range(grid_size.y + 1):
		var py = grid_origin.y + y * cell_size
		draw_line(Vector2(grid_origin.x, py), Vector2(grid_origin.x + grid_size.x * cell_size, py), Color(0.18, 0.18, 0.25), 1.0)
	# Ghost preview
	if ghost_data and ghost_pos != Vector2i(-1,-1):
		var rect = Rect2(grid_origin + Vector2(ghost_pos) * cell_size, Vector2(ghost_data.size) * cell_size)
		draw_rect(rect, Color(0.2, 1.0, 0.4, 0.25) if ghost_valid else Color(1.0, 0.2, 0.2, 0.25), true)
		draw_rect(rect, Color(0.4, 1.0, 0.6) if ghost_valid else Color(1.0, 0.4, 0.4), false, 2.0)

func world_to_cell(world: Vector2) -> Vector2i:
	var local = world - grid_origin
	return Vector2i(floor(local.x / cell_size), floor(local.y / cell_size))

func cell_to_world(cell: Vector2i) -> Vector2:
	return grid_origin + Vector2(cell) * cell_size + Vector2(cell_size, cell_size) * 0.5 + Vector2(cell_size, cell_size) * (Vector2(data_size_offset(cell))-Vector2(0.5,0.5))

func data_size_offset(cell: Vector2i) -> Vector2i:
	# helper not needed
	return Vector2i(0,0)

func is_area_free(top_left: Vector2i, size: Vector2i) -> bool:
	if top_left.x < 0 or top_left.y < 0: return false
	if top_left.x + size.x > grid_size.x or top_left.y + size.y > grid_size.y: return false
	for y in range(size.y):
		for x in range(size.x):
			var c = top_left + Vector2i(x, y)
			if occupied.has(c):
				return false
	return true

func occupy_area(top_left: Vector2i, size: Vector2i, building: Building):
	for y in range(size.y):
		for x in range(size.x):
			occupied[top_left + Vector2i(x, y)] = building

func free_area(top_left: Vector2i, size: Vector2i):
	for y in range(size.y):
		for x in range(size.x):
			occupied.erase(top_left + Vector2i(x, y))

func set_ghost(to_place: BuildingData):
	ghost_data = to_place
	if ghost_data:
		print("[Grid] Ghost set to ", ghost_data.display_name)

func clear_ghost():
	ghost_data = null
	ghost_pos = Vector2i(-1,-1)
	queue_redraw()

func _input(event):
	if event is InputEventMouseMotion:
		if ghost_data:
			var cell = world_to_cell(event.position)
			if cell != ghost_pos:
				ghost_pos = cell
				ghost_valid = is_area_free(ghost_pos, ghost_data.size) and ResourceManager.can_afford(ghost_data.build_cost_food, ghost_data.build_cost_metal)
				queue_redraw()
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		if ghost_data:
			try_place(ghost_pos)
		else:
			# Selection: check if clicked on building
			var cell = world_to_cell(event.position)
			var b = occupied.get(cell)
			if b:
				building_selected.emit(b)
			else:
				# Clicked empty - could deselect or show build menu
				pass

func try_place(cell: Vector2i) -> bool:
	if not ghost_data:
		return false
	if not is_area_free(cell, ghost_data.size):
		placement_failed.emit("Cell occupied or out of bounds")
		return false
	if not ResourceManager.can_afford(ghost_data.build_cost_food, ghost_data.build_cost_metal):
		placement_failed.emit("Not enough resources (need %d food, %d metal)" % [ghost_data.build_cost_food, ghost_data.build_cost_metal])
		return false
	# Pay
	ResourceManager.spend(ghost_data.build_cost_food, ghost_data.build_cost_metal)
	# Instantiate
	var building_scene = preload("res://scenes/Building.tscn")
	var b = building_scene.instantiate() as Building
	b.data = ghost_data
	b.grid_pos = cell
	b.level = 1
	# Position at center of occupied area
	var world_center = grid_origin + Vector2(cell) * cell_size + Vector2(ghost_data.size) * cell_size * 0.5
	b.global_position = world_center
	buildings_root.add_child(b)
	b.clicked.connect(func(bb): building_selected.emit(bb))
	buildings.append(b)
	occupy_area(cell, ghost_data.size, b)
	building_placed.emit(b)
	SaveManager.save_game()
	queue_redraw()
	print("[Grid] Placed ", ghost_data.display_name, " at ", cell)
	return true

func add_existing_building(b: Building):
	# Called on load
	var world_center = grid_origin + Vector2(b.grid_pos) * cell_size + Vector2(b.data.size) * cell_size * 0.5
	b.global_position = world_center
	buildings_root.add_child(b)
	b.clicked.connect(func(bb): building_selected.emit(bb))
	buildings.append(b)
	occupy_area(b.grid_pos, b.data.size, b)

func get_all_buildings() -> Array[Building]:
	return buildings
