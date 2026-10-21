# Building.gd — Instantiate for each placed structure
# Godot 4.x — attach to Node2D/Area2D

extends Area2D
class_name Building

signal clicked(building: Building)

@export var data: BuildingData
var grid_pos: Vector2i # top-left cell
var level: int = 1
var is_upgrading: bool = false
var upgrade_finish_unix: int = 0 # Unix time when upgrade completes (persists offline)
var upgrade_target_level: int = 1

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label
@onready var timer_label: Label = $TimerLabel
@onready var progress: ProgressBar = $ProgressBar

func _ready():
	add_to_group("buildings")
	input_event.connect(_on_input)
	update_visual()
	# Start ticking
	set_process(true)

func setup(p_data: BuildingData, p_grid_pos: Vector2i):
	data = p_data
	grid_pos = p_grid_pos
	level = 1
	is_upgrading = false
	upgrade_finish_unix = 0
	update_visual()

func _on_input(_viewport, event, _shape_idx):
	if event is InputEventMouseButton and event.pressed and event.button_index == 1:
		clicked.emit(self)
		get_viewport().set_input_as_handled()

func update_visual():
	if not data: return
	if label:
		label.text = "%s\nLv.%d" % [data.display_name, level]
		if is_upgrading:
			label.text += "\n↑ Lv.%d" % upgrade_target_level
	if sprite:
		sprite.modulate = Color(0.6,0.6,0.6) if is_upgrading else Color.WHITE
		# Color by type
		match data.type:
			BuildingData.Type.HEADQUARTERS: sprite.modulate = Color(0.4,0.6,1) if not is_upgrading else Color(0.3,0.4,0.7)
			BuildingData.Type.FARM: sprite.modulate = Color(0.4,1,0.5) if not is_upgrading else Color(0.25,0.6,0.35)
			BuildingData.Type.BARRACKS: sprite.modulate = Color(1,0.5,0.4) if not is_upgrading else Color(0.7,0.35,0.25)
	if progress:
		progress.visible = is_upgrading

func start_upgrade():
	if is_upgrading or level >= data.max_level:
		return false
	var cost = data.get_upgrade_cost(level)
	# Check resources via ResourceManager singleton
	if not ResourceManager.can_afford(cost["food"], cost["metal"]):
		return false
	ResourceManager.spend(cost["food"], cost["metal"])
	is_upgrading = true
	upgrade_target_level = level + 1
	var duration = int(cost["time"])
	upgrade_finish_unix = int(Time.get_unix_time_from_system()) + duration
	update_visual()
	# Persist immediately
	SaveManager.save_game()
	return true

func _process(_delta):
	if not is_upgrading:
		if timer_label: timer_label.text = ""
		if progress: progress.visible = false
		return
	var now = int(Time.get_unix_time_from_system())
	var remaining = upgrade_finish_unix - now
	if remaining <= 0:
		_complete_upgrade()
	else:
		if timer_label:
			timer_label.text = _format_time(remaining)
		if progress:
			var cost = data.get_upgrade_cost(level)
			var total = int(cost["time"])
			var elapsed = total - remaining
			progress.max_value = total
			progress.value = elapsed
			progress.visible = true

func _complete_upgrade():
	is_upgrading = false
	level = upgrade_target_level
	upgrade_finish_unix = 0
	upgrade_target_level = level
	update_visual()
	SaveManager.save_game()
	# Notify
	ResourceManager.recalculate_generation()
	GameManagerStub.show_floating_text(global_position, "Lv.%d Ready!" % level, Color.GREEN) if Engine.has_singleton("GameManagerStub") else print("Upgrade complete Lv.", level)

func _format_time(sec: int) -> String:
	var m = sec / 60
	var s = sec % 60
	return "%02d:%02d" % [m, s]

# Called on load to restore upgrading state (offline completion)
func check_offline_completion(now_unix: int):
	if not is_upgrading:
		return
	if now_unix >= upgrade_finish_unix:
		# Could have leveled multiple times if enough time passed? For simplicity, complete one
		_complete_upgrade()
		# If the new level also had a queued upgrade that would have finished, it would be a second save — we handle one per load for safety

func to_save_dict() -> Dictionary:
	return {
		"type": data.type,
		"grid_pos": {"x": grid_pos.x, "y": grid_pos.y},
		"level": level,
		"is_upgrading": is_upgrading,
		"upgrade_finish_unix": upgrade_finish_unix,
		"upgrade_target_level": upgrade_target_level
	}

static func from_save_dict(d: Dictionary) -> Building:
	var b = preload("res://scenes/Building.tscn").instantiate() as Building
	var type = int(d["type"])
	var data: BuildingData
	match type:
		BuildingData.Type.HEADQUARTERS: data = BuildingData.make_hq()
		BuildingData.Type.FARM: data = BuildingData.make_farm()
		BuildingData.Type.BARRACKS: data = BuildingData.make_barracks()
		_: data = BuildingData.make_farm()
	var pos = Vector2i(int(d["grid_pos"]["x"]), int(d["grid_pos"]["y"]))
	b.data = data
	b.grid_pos = pos
	b.level = int(d["level"])
	b.is_upgrading = bool(d["is_upgrading"])
	b.upgrade_finish_unix = int(d.get("upgrade_finish_unix", 0))
	b.upgrade_target_level = int(d.get("upgrade_target_level", b.level))
	return b
