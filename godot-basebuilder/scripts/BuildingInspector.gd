# BuildingInspector.gd — Popup that shows level + Upgrade button with persistent timer
# Godot 4.x — attach to Panel (CanvasLayer or in-world UI)

extends Panel
class_name BuildingInspector

signal upgrade_started(building: Building)
signal closed

var current: Building = null

@onready var title: Label = $VBox/Title
@onready var level_label: Label = $VBox/Level
@onready var stats_label: Label = $VBox/Stats
@onready var cost_label: Label = $VBox/Cost
@onready var timer_label: Label = $VBox/Timer
@onready var upgrade_btn: Button = $VBox/UpgradeBtn
@onready var close_btn: Button = $VBox/CloseBtn
@onready var progress: ProgressBar = $VBox/ProgressBar

func _ready():
	visible = false
	upgrade_btn.pressed.connect(_on_upgrade)
	close_btn.pressed.connect(hide_inspector)
	# SaveManager auto-saves, but we also update UI every second
	var t = Timer.new()
	t.wait_time = 0.1
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)

func show_for(building: Building):
	current = building
	visible = true
	_update_ui()

func hide_inspector():
	visible = false
	current = null
	closed.emit()

func _update_ui():
	if not current or not current.data:
		return
	var d = current.data
	title.text = d.display_name
	level_label.text = "Level %d / %d" % [current.level, d.max_level]
	var gen = d.get_generation(current.level)
	stats_label.text = "Produces: %.1f food/s, %.1f metal/s\nDefense: +%d  Storage: +%d" % [
		gen["food"], gen["metal"],
		d.defense_bonus[current.level] if current.level < d.defense_bonus.size() else 0,
		d.storage_bonus[current.level] if current.level < d.storage_bonus.size() else 0
	]
	if current.is_upgrading:
		var remaining = current.upgrade_finish_unix - int(Time.get_unix_time_from_system())
		remaining = max(0, remaining)
		cost_label.text = "Upgrading to Lv.%d" % current.upgrade_target_level
		timer_label.text = "⏱ %s remaining (persists if closed)" % _format_time(remaining)
		upgrade_btn.disabled = true
		upgrade_btn.text = "Upgrading…"
		progress.visible = true
	elif current.level >= d.max_level:
		cost_label.text = "MAX LEVEL"
		timer_label.text = ""
		upgrade_btn.disabled = true
		upgrade_btn.text = "Max Level"
		progress.visible = false
	else:
		var cost = d.get_upgrade_cost(current.level)
		cost_label.text = "Cost: %d Food, %d Metal" % [cost["food"], cost["metal"]]
		timer_label.text = "Time: %s (persists offline)" % _format_time(int(cost["time"]))
		var can = ResourceManager.can_afford(cost["food"], cost["metal"])
		upgrade_btn.disabled = not can
		upgrade_btn.text = "Upgrade → Lv.%d" % (current.level + 1)
		if not can:
			cost_label.text += " — Not enough!"
		progress.visible = false

func _tick():
	if visible and current:
		_update_ui()
		# Auto-close if upgrade finished? Keep open to show completed
		if current.is_upgrading:
			var now = int(Time.get_unix_time_from_system())
			if now >= current.upgrade_finish_unix:
				# Building will complete on its own _process, just refresh
				_update_ui()

func _on_upgrade():
	if not current:
		return
	var ok = current.start_upgrade()
	if ok:
		upgrade_started.emit(current)
		print("[Inspector] Upgrade started for ", current.data.display_name)
	else:
		print("[Inspector] Upgrade failed — afford check")

func _format_time(s: int) -> String:
	var m = s / 60
	var r = s % 60
	return "%02d:%02d" % [m, r]
