# 🧟 Deadzone — Vertical Lane Runner Prototype (Godot 4)

Godot 4.2+ prototype for a **vertical 3-lane runner** — swiped from mobile survival lore. Built to connect to your **survival-api** (`https://survival-api-w6cr.onrender.com`).

---

## 🎮 Gameplay

- **3 vertical lanes** (left / center / right) — player at bottom, enemies fall from top
- **Swap lanes** smoothly with **Arrow Keys** (Left/Right) or **Swipe / Tap** halves on mobile. Uses `Tween` 0.18s for buttery motion.
- **Auto-shoot** with Space / Tap top — fires bullet upward to destroy:
  - **Obstacles** (cars) — avoid, -25 HP on hit
  - **Zombies** — 50 HP, sway side-to-side, +10 score & +5 metal on death
  - **Barrels / Gates** — destructible loot with labels: `+50 Ammo`, `+20 Metal`, `x2 Damage 5s`, `+25 HP` — shooting pops a buff
- **Game Over** when HP ≤ 0 → freezes world, shows **Results tally** (score, zombies, barrels, metal/food, time survived, high score)

### Resources synced to backend (your Render API)
`GameManager` tallies `food, metal, ammo, score` and `POST`s to `https://survival-api-w6cr.onrender.com/api/resources/:userId` on Game Over (needs `jwt_token` from login).

---

## 📁 Project Structure

```
deadzone-runner/
├── project.godot              # Input map: move_left/right, shoot, pause
├── scenes/
│   ├── Main.tscn              # Root: Player + Spawner + Road + HUD + Camera
│   ├── Player.tscn            # CharacterBody2D + CollisionShape + Sprite + Muzzle
│   ├── Bullet.tscn            # Area2D + Sprite
│   ├── Zombie.tscn            # Area2D + HPBar + AnimationPlayer
│   ├── Obstacle.tscn          # Area2D (car sprite)
│   ├── Barrel.tscn            # Area2D + Label (+50 Ammo etc.) + HPBar
│   ├── Gate.tscn              # Area2D (wider gate variant)
│   └── Menu.tscn              # Login + Play + High Score display
└── scripts/
    ├── Player.gd              # Lane switch, shoot, buffs, take_damage
    ├── Bullet.gd              # Moves up, hits destructible/enemy
    ├── Zombie.gd              # Fall + sway + die → metal drop
    ├── Obstacle.gd            # Fall, damage player
    ├── BarrelGate.gd          # Destructible loot with buffs (random_loot())
    ├── Spawner.gd             # Random spawn with difficulty ramp
    ├── GameManager.gd         # Autoload singleton: score/resources, sync to backend
    ├── HUD.gd                 # HealthBar, tallies, Game Over panel + Results
    └── Main.gd                # Road scroll + pause
```

### Scene Setup (2-min)
1. **Create new Godot 4 project** → copy this folder.
2. **Autoload:** Project Settings → Autoload → Add `scripts/GameManager.gd` as `GameManager` (enable).
3. **Input:** Already in `project.godot` — verify `move_left` (Left Arrow), `move_right` (Right), `shoot` (Space/Mouse1).
4. **Build `Main.tscn`:**
   - `Node2D` (attach `Main.gd`)
     - `Player` (CharacterBody2D, attach `Player.gd`) → assign `Bullet.tscn` to `bullet_scene`, add child `Muzzle` Marker2D at (0, -40), `ShootTimer` Timer, `Sprite2D`, `AnimationPlayer` with `idle`, `lean_left/right`, `shoot`, `hit`
     - `Spawner` (Node2D at y=-100, attach `Spawner.gd`) → drag `Zombie.tscn`, `Obstacle.tscn`, `Barrel.tscn`, `Gate.tscn` into exports, add child `Timer`
     - `Road` (Sprite2D or ParallaxBackground with scrolling texture, tag as `Road`)
     - `Camera2D` (Current)
     - `CanvasLayer` (attach `HUD.gd`) → build TopBar (HealthBar ProgressBar + 4 Labels) + `GameOverPanel` (hidden Panel with VBox + Labels + Restart/Menu buttons)
5. Play `Main.tscn`.

---

## ⌨️ Controls

| Input | Action |
|-------|--------|
| **← / →** | Switch lane (smooth tween) |
| **Space / Mouse click top** | Shoot |
| **Swipe left/right** (touch) | Switch lane (threshold 40px) |
| **Tap left/right half** (mobile fallback) | Switch lane |
| **Esc** | Pause |

---

## 🔧 Key Scripts Explained

### `Player.gd` — Lane Switching
```gdscript
func _lane_to_x(lane: int) -> float:
    var center_offset = (lane_count - 1) / 2.0
    return (lane - center_offset) * lane_distance # e.g. -120, 0, 120

func _switch_with_tween(to_x):
    var tween = create_tween()
    tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(self, "global_position:x", to_x, 0.18)
```
Touch: `InputEventScreenTouch` start/end delta vs `swipe_threshold`.

### `BarrelGate.gd` — Buffs
`take_damage() → explode() → player.apply_buff(buff_type, buff_value, duration)`
Pools: `+50 Ammo`, `x2 Damage`, `+25 HP`, etc. `damage_x` sets `damage_buff_multiplier` for 5s with red tint.

### `Spawner.gd` — Random
```gdscript
roll = randf()
if roll < 0.30: spawn_obstacle()
elif roll < 0.65: spawn_zombie()
elif roll < 0.85: spawn_barrel()
else: spawn_gate()
# Interval shrinks with elapsed * difficulty_ramp
```
`fall_speed += elapsed * 10` for ramp.

### `GameManager.gd` — Results + Backend
Stores `score, food, metal, ammo, health, run_stats{distance, zombies_killed, barrels...}`. On `trigger_game_over()` pauses tree, saves high_score, and (if `jwt_token` set via `GameManager.login(email, pass, callback)`) syncs to `https://survival-api-w6cr.onrender.com/api/resources/:userId`.

---

## 🔗 Connect to Your Backend

In `GameManager.gd`:
```gdscript
var backend_url = "https://survival-api-w6cr.onrender.com"
var jwt_token = "" # set after login
```

Call from Menu:
```gdscript
GameManager.login("test@deadzone.com", "password123", func(ok, json):
    if ok: get_tree().change_scene_to_file("res://scenes/Main.tscn"))
```

Game Over auto-syncs `food/metal/ammo/score`.

---

## 🚀 Next Steps

- Add lane indicator arrows + trail particles
- Juice: screen shake on hit (wired via `GameManager.camera_shake`), explosion `CPUParticles2D`
- Sound: shoot, explode, hit
- Export to Android: Project → Export → Android (touch already handled)

**Run:** Open in Godot 4.2+ → Play `Main.tscn` → Arrow keys / swipe.
