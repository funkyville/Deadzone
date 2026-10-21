# 🏗️ Deadzone — 2D Grid Base-Builder (Godot 4)

Godot 4.2+ prototype for a **grid-based base-building UI** with persistent upgrades — drop-in for your Deadzone survival backend.

---

## ✨ Features

- **Grid (8×8, 64px cells)** — click to place, ghost preview (green/red), multi-cell buildings (HQ 2×2, Barracks 2×1)
- **3 structures:** `Headquarters` (storage, 2×2, free), `Resource Farm` (1×1, +0.5→3 food/s), `Barracks` (2×1, defense)
- **Inspector popup** — shows name, level/max, stats, cost, countdown + ProgressBar; Upgrade button disables if unaffordable/max
- **Upgrade timer persists if app is closed** — stores `upgrade_finish_unix = now + 30s` to `user://deadzone_base.json`; on load compares `Time.get_unix_time_from_system()`, completes offline, awards level, recalculates generation

---

## 📁 Structure

```
deadzone-basebuilder/
├── project.godot                # Autoloads: ResourceManager, SaveManager
├── scenes/
│   ├── Base.tscn                # Root: BaseGrid + Buildings + CanvasLayer (TopBar/BuildMenu/Inspector)
│   ├── Building.tscn            # Area2D + Sprite2D + Label + TimerLabel + ProgressBar
│   └── Menu.tscn (optional)
└── scripts/
    ├── BuildingData.gd          # Resource defs: costs, times, generation per level
    ├── Building.gd              # Area2D: level, is_upgrading, upgrade_finish_unix, _process countdown, to_save_dict
    ├── BaseGrid.gd              # 8×8 grid: world_to_cell, occupied Dict, ghost preview, try_place, add_existing_building
    ├── BuildMenu.gd             # HQ/Farm/Barracks buttons → grid.set_ghost()
    ├── BuildingInspector.gd     # Panel: shows Lv, stats, cost, timer, UpgradeBtn
    ├── ResourceManager.gd       # Autoload: food/metal, can_afford/spend, food_per_sec, offline progress
    ├── SaveManager.gd           # Autoload: save/load JSON to user://deadzone_base.json, offline completion
    └── MainBase.gd              # Root: load_game, wire signals, autosave every 5s
```

### Scene Setup (2 min)
1. New Godot 4 project → copy folder → Project Settings → Autoload: `ResourceManager.gd`, `SaveManager.gd`, `GameManager` (if using runner)
2. `Building.tscn`: Area2D + CollisionShape2D (size 64×64), Sprite2D, Label (`$Label`), TimerLabel (`$TimerLabel`), ProgressBar (`$ProgressBar`), AnimationPlayer optional — attach `Building.gd`
3. `Base.tscn`: Node2D (attach `MainBase.gd`) → `BaseGrid` (Node2D, 8×8, attach `BaseGrid.gd`, child `Buildings` Node2D + `Highlight`) → `CanvasLayer` → `TopBar` (3 Labels), `BuildMenu` (VBox + 4 Buttons, attach `BuildMenu.gd`), `Inspector` (Panel, attach `BuildingInspector.gd`)
4. Play `Base.tscn`.

---

## 🔁 Persistence (offline upgrades)

**Save (`SaveManager.save_game()`):**
```json
{
  "last_save_unix": 1730000000,
  "resources": {"food": 200, "metal": 150},
  "buildings": [{
    "type": 1, "grid_pos": {"x":2,"y":1}, "level":1,
    "is_upgrading": true, "upgrade_finish_unix": 1730000030, "upgrade_target_level": 2
  }]
}
```

**Load (`SaveManager.load_game()`):**
```gdscript
now = Time.get_unix_time_from_system()
offline_sec = now - last_save_unix  # e.g. app closed 30s → 30
for b in buildings:
  b.check_offline_completion(now)  # if now >= upgrade_finish_unix → complete, level++
ResourceManager.apply_offline_progress(offline_sec) # +food/metal = food_per_sec * offline_sec
ResourceManager.recalculate_generation() # updates TopBar
```

**Building timer (`Building._process`):**
```gdscript
remaining = upgrade_finish_unix - now
if remaining <= 0: _complete_upgrade()  # even if app was closed, this fires on next run
else: timer_label.text = "%02d:%02d" % [remaining/60, remaining%60]
```

---

## 🔗 Backend Connect (optional)
Your `survival-api-w6cr.onrender.com` — sync upgrades to cloud:
```gdscript
# In Building._complete_upgrade(), after SaveManager.save_game():
if GameManager.jwt_token != "":
  GameManager.sync_resources_to_backend() # PUT /api/resources/:userId with food/metal
```

---

## 🎮 Controls

| Action | Input |
|--------|-------|
| Select building type | BuildMenu: HQ / Farm / Barracks |
| Place | Click green ghost on grid (red = occupied/unaffordable) |
| Inspect | Click placed building → popup |
| Upgrade | Inspector → Upgrade (30s, persists offline) |
| Cancel placing | BuildMenu → Cancel |

**Run:** Open in Godot 4.2+ → Play `Base.tscn` → Build Farm → Click → Upgrade → Wait 30s or close app and reopen after 30s → Lv.2 + new generation rate.

---

## 🚀 Next

- Add drag-move buildings, demolish
- Export to Android (touch already handled)
- Wire to Render static deploy: copy `deadzone-basebuilder` to `godot-runner` pattern
