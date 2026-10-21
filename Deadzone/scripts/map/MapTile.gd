# MapTile.gd — Single overworld tile (like LastZ Fog/Claim system)
# Godot 4.x

extends Resource
class_name MapTile

enum State { LOCKED, FOG, CLEARABLE, CLEARED, OCCUPIED } # Occupied = you built an outpost
enum Biome { WASTELAND, RUINS, FOREST, DESERT }

@export var coord: Vector2i
@export var state: State = State.FOG
@export var biome: Biome = Biome.WASTELAND
@export var difficulty: int = 1 # 1-5, higher = tougher runner
@export var reward_food: int = 20
@export var reward_metal: int = 15
@export var zombie_density: int = 1

func can_attack() -> bool: return state == State.CLEARABLE
func is_visible() -> bool: return state != State.LOCKED
func label() -> String:
	match state:
		State.LOCKED: return "🔒 Locked"
		State.FOG: return "🌫 Fog"
		State.CLEARABLE: return "⚔ Lvl %d" % difficulty
		State.CLEARED: return "✓ Cleared"
		State.OCCUPIED: return "🏠 Outpost"
		_: return "?"
