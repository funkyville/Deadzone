# WorldMap.gd — Overworld fog grid like LastZ after runner
# Attach to Node2D (WorldMap)

extends Node2D
class_name WorldMap

signal tile_selected(tile: MapTile)
signal tile_cleared(tile: MapTile, reward: Dictionary)
signal hq_expanded(new_radius: int)

@export var map_size: Vector2i = Vector2i(9,9) # Overworld is larger than base 8x8
@export var cell_px: int = 64
@export var hq_pos: Vector2i = Vector2i(4,4) # center

var tiles: Dictionary = {} # Vector2i -> MapTile
var hq_level: int = 1
var hq_radius: int = 1 # HQ Lv1 = 1 tile radius visible, Lv2 = 2, etc.

func _ready():
	add_to_group("world_map")
	generate()
	queue_redraw()

func generate():
	tiles.clear()
	for y in map_size.y:
		for x in map_size.x:
			var c = Vector2i(x,y)
			var t = MapTile.new()
			t.coord = c
			t.biome = randi() % MapTile.Biome.size()
			var dist = abs(c.x - hq_pos.x) + abs(c.y - hq_pos.y) # Manhattan
			if c == hq_pos:
				t.state = MapTile.State.OCCUPIED
				t.difficulty = 1
			elif dist <= hq_radius:
				t.state = MapTile.State.CLEARABLE if randf() < 0.7 else MapTile.State.FOG
				t.difficulty = clampi(int(dist), 1, 5)
			elif dist == hq_radius + 1:
				t.state = MapTile.State.FOG
			else:
				t.state = MapTile.State.LOCKED
			t.reward_food = 15 + dist * 8 + randi_range(0,10)
			t.reward_metal = 10 + dist * 6 + randi_range(0,8)
			tiles[c] = t
	refresh_fog()

func refresh_fog():
	# After HQ upgrade, unlock new ring
	for c in tiles.keys():
		var t = tiles[c]
		if t.state == MapTile.State.LOCKED:
			var dist = abs(c.x - hq_pos.x) + abs(c.y - hq_pos.y)
			if dist <= hq_radius + 1:
				t.state = MapTile.State.FOG
				if dist <= hq_radius:
					t.state = MapTile.State.CLEARABLE
	queue_redraw()

func get_tile(world_pos: Vector2) -> MapTile:
	var local = world_pos - global_position
	var c = Vector2i(floor(local.x / cell_px), floor(local.y / cell_px))
	return tiles.get(c)

func world_to_tile_coord(world: Vector2) -> Vector2i:
	var local = world - global_position
	return Vector2i(floor(local.x / cell_px), floor(local.y / cell_px))

func tile_to_world_center(coord: Vector2i) -> Vector2:
	return global_position + Vector2(coord) * cell_px + Vector2(cell_px, cell_px) * 0.5

func on_runner_victory(cleared_coord: Vector2i):
	var t = tiles.get(cleared_coord)
	if not t: return
	if t.state == MapTile.State.CLEARABLE or t.state == MapTile.State.FOG:
		t.state = MapTile.State.CLEARED
		var reward = {"food": t.reward_food, "metal": t.reward_metal}
		DeadzoneManager.food += reward["food"]
		DeadzoneManager.metal += reward["metal"]
		tile_cleared.emit(t, reward)
		# Unlock neighbors (LastZ Fog clear)
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var n = cleared_coord + d
			var nt = tiles.get(n)
			if nt and nt.state == MapTile.State.FOG:
				nt.state = MapTile.State.CLEARABLE
			if nt and nt.state == MapTile.State.LOCKED and abs(n.x - hq_pos.x) + abs(n.y - hq_pos.y) <= hq_radius + 1:
				nt.state = MapTile.State.FOG
		DeadzoneManager.save_game()
		queue_redraw()

func upgrade_hq():
	var cost_food = 80 + hq_level * 60
	var cost_metal = 50 + hq_level * 40
	if not DeadzoneManager.can_afford(cost_food, cost_metal):
		return false
	DeadzoneManager.spend(cost_food, cost_metal)
	hq_level += 1
	hq_radius = clampi(1 + int(hq_level / 2), 1, 4) # Lv1=1, Lv3=2, Lv5=3
	refresh_fog()
	hq_expanded.emit(hq_radius)
	DeadzoneManager.save_game()
	return true

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		var tile = get_tile(event.position)
		if tile:
			tile_selected.emit(tile)

func _draw():
	# Draw map tiles
	for c in tiles.keys():
		var t = tiles[c]
		var rect = Rect2(Vector2(c) * cell_px, Vector2(cell_px, cell_px))
		match t.state:
			MapTile.State.LOCKED:
				draw_rect(rect, Color(0.05, 0.05, 0.08), true)
			MapTile.State.FOG:
				draw_rect(rect, Color(0.12, 0.12, 0.18), true)
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(8, cell_px/2), "🌫", HORIZONTAL_ALIGNMENT_CENTER, cell_px, 16, Color(0.5,0.5,0.6))
			MapTile.State.CLEARABLE:
				draw_rect(rect, Color(0.18, 0.25, 0.18), true)
				draw_rect(rect, Color(0.3, 0.8, 0.4), false, 2.0)
			MapTile.State.CLEARED:
				draw_rect(rect, Color(0.14, 0.18, 0.14), true)
			MapTile.State.OCCUPIED:
				draw_rect(rect, Color(0.25, 0.22, 0.15), true)
				draw_rect(rect, Color(1.0, 0.85, 0.3), false, 3.0)
		# coord label
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, 12), "%d,%d" % [c.x, c.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.4,0.4,0.45))
		# HQ marker
		if c == hq_pos:
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(cell_px/2 - 10, cell_px/2 + 6), "🏠", HORIZONTAL_ALIGNMENT_CENTER, cell_px, 22, Color.WHITE)
