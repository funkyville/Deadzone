# Menu.gd
# Godot 4.x - Login / Register screen that auto-logs into backend
# Attach to Control node in Menu.tscn

extends Control

@onready var email_input: LineEdit = $VBox/Email
@onready var password_input: LineEdit = $VBox/Password
@onready var username_input: LineEdit = $VBox/Username
@onready var continent_option: OptionButton = $VBox/Continent
@onready var status_label: Label = $VBox/Status
@onready var login_btn: Button = $VBox/LoginBtn
@onready var register_btn: Button = $VBox/RegisterBtn
@onready var guest_btn: Button = $VBox/GuestBtn
@onready var play_btn: Button = $VBox/PlayBtn
@onready var logout_btn: Button = $VBox/LogoutBtn
@onready var user_label: Label = $VBox/UserLabel
@onready var play_label: Label = $VBox/PlayLabel

func _ready():
	login_btn.pressed.connect(_on_login)
	register_btn.pressed.connect(_on_register)
	guest_btn.pressed.connect(_on_guest)
	play_btn.pressed.connect(_on_play)
	logout_btn.pressed.connect(_on_logout)
	GameManager.auth_changed.connect(_update_ui)
	# Setup continents
	if continent_option and continent_option.item_count == 0:
		for c in ["NA - Wastelands", "EU - Ruins", "AS - Badlands", "AF - Outback", "SA - Jungles", "OC - Islands"]:
			continent_option.add_item(c)
	# Check existing auth
	if GameManager.jwt_token != "":
		GameManager.verify_token(func(ok, _d):
			_update_ui(ok, GameManager.current_user.get("username",""))
		)
	else:
		_update_ui(false, "")

func _update_ui(logged_in: bool, username: String):
	if logged_in:
		user_label.text = "👤 Logged in as " + username + " — Synced"
		user_label.modulate = Color.GREEN
		play_btn.visible = true
		logout_btn.visible = true
		login_btn.visible = false
		register_btn.visible = false
		guest_btn.visible = false
		play_label.text = "Ready to run! Your loot will sync to the cloud."
	else:
		user_label.text = "● Offline — login to save progress"
		user_label.modulate = Color.GRAY
		play_btn.visible = false
		logout_btn.visible = false
		login_btn.visible = true
		register_btn.visible = true
		guest_btn.visible = true
		play_label.text = "Guest runs are local only."

func _on_login():
	var email = email_input.text.strip_edges()
	var password = password_input.text
	if email == "" or password == "":
		status_label.text = "❌ Fill email & password"
		return
	status_label.text = "Logging in…"
	login_btn.disabled = true
	GameManager.login(email, password, func(ok, json):
		login_btn.disabled = false
		if ok:
			status_label.text = "✅ Logged in as " + json["user"]["username"]
			status_label.modulate = Color.GREEN
		else:
			status_label.text = "❌ Login failed — check email/password"
			status_label.modulate = Color.RED
	)

func _on_register():
	var username = username_input.text.strip_edges()
	var email = email_input.text.strip_edges()
	var password = password_input.text
	var continent_id = (continent_option.selected + 1) if continent_option else 1
	if username == "":
		username = email.split("@")[0].substr(0, 20) if email != "" else "player%d" % randi_range(100,999)
	if email == "" or password == "":
		status_label.text = "❌ Need username, email & password (6+ chars)"
		return
	status_label.text = "Registering…"
	register_btn.disabled = true
	GameManager.register_user(username, email, password, continent_id, func(ok, json):
		register_btn.disabled = false
		if ok:
			status_label.text = "✅ Registered as " + json["user"]["username"] + " — auto-logged in"
			status_label.modulate = Color.GREEN
		else:
			status_label.text = "❌ Register failed — email taken?"
			status_label.modulate = Color.RED
	)

func _on_guest():
	GameManager.logout()
	status_label.text = "Playing as Guest — stats local only"
	_on_play()

func _on_logout():
	GameManager.logout()
	status_label.text = "Logged out"
	_update_ui(false, "")

func _on_play():
	GameManager.reset_run()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
