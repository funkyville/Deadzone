# TutorialOverlay.gd — Attach to CanvasLayer that shows arrow + text for LastZ Part 1
# Connects to Tutorial.step_changed

extends CanvasLayer

@onready var label: Label = $Panel/Label
@onready var arrow: TextureRect = $Arrow
@onready var next_btn: Button = $Panel/NextBtn
@onready var progress: ProgressBar = $Panel/Progress

var targets: Dictionary = {
	"tap_hq_btn": Vector2(100, 120),
	"place": Vector2(180, 300),
	"inspect": Vector2(180, 500),
	"wait": Vector2(180, 400),
	"go_map": Vector2(280, 80),
	"attack": Vector2(180, 300),
	"run": Vector2(180, 320),
	"expand": Vector2(180, 100),
}

func _ready():
	visible = false
	if has_node("/root/Tutorial"):
		var tut = get_node("/root/Tutorial")
		tut.step_changed.connect(_on_step)
		tut.tutorial_finished.connect(func(): visible = false)
	next_btn.pressed.connect(func(): 
		var tut = get_node_or_null("/root/Tutorial")
		if tut and tut.steps[tut.step]["action"] == "tap_hq_btn":
			tut.advance()
	)
	# Auto-start if fresh save
	await get_tree().create_timer(0.5).timeout
	var tut = get_node_or_null("/root/Tutorial")
	if tut and not tut.completed and tut.step == 0 and DeadzoneManager.food == 200: # fresh
		tut.start_tutorial()

func _on_step(st: int):
	var tut = get_node("/root/Tutorial")
	if st >= tut.steps.size() or tut.completed:
		visible = false
		return
	visible = true
	var s = tut.steps[st]
	label.text = "[%d/%d] %s" % [st+1, tut.steps.size(), s["text"]]
	progress.max_value = tut.steps.size()
	progress.value = st + 1
	# Position arrow near target
	var tgt = s.get("action","")
	if targets.has(tgt):
		arrow.global_position = targets[tgt]
		arrow.visible = true
	else:
		arrow.visible = false
	# Pulse
	var tween = create_tween()
	tween.tween_property(arrow, "modulate:a", 0.4, 0.4)
	tween.tween_property(arrow, "modulate:a", 1.0, 0.4)
	tween.set_loops()

func _process(_d):
	# Keep hint updated during wait_upgrade countdown
	var tut = get_node_or_null("/root/Tutorial")
	if tut and tut.is_active() and tut.steps[tut.step]["id"] == "wait_upgrade":
		var grid = get_tree().get_first_node_in_group("grid")
		if grid:
			for b in grid.get_all_buildings():
				if b.is_upgrading:
					label.text = "[5/10] Upgrading Farm to Lv.%d — %02d:%02d left (close app and reopen, it still finishes!)" % [b.upgrade_target_level, int((b.upgrade_finish_unix - Time.get_unix_time_from_system())/60), int((b.upgrade_finish_unix - Time.get_unix_time_from_system())%60)]
