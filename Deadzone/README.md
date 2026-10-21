# 🧟 Deadzone — Unified Project (ONE GAME)

> "They are all one project — we are building each segment one at a time, merge them, and do not separate it again."

This is the **single Deadzone Godot 4 project** that contains everything built so far, merged.

## 🗺️ Flow (One Game)

```
Menu → Base (8×8 Grid) → [Launch Run] → Runner (3-Lane Vertical) → Game Over → Back to Base with Loot → Upgrade Base → Repeat
```

- **Menu** (`scenes/Menu.tscn`): Login/Register (wired to `https://survival-api-w6cr.onrender.com`) + Guest + Play
- **Base** (`scenes/Base.tscn`): Grid where you place **Headquarters (2×2)**, **Resource Farm (1×1, +food/s)**, **Barracks (2×1, defense)**. Click building → **Inspector Popup** → Level + Upgrade (30s, persists offline) → Resource generation even when app closed.
- **Runner** (`scenes/Runner.tscn`): Vertical 3-lane runner — swipe/←→ to switch, shoot barrels (`+50 Ammo`, `x2 DAMAGE`), dodge zombies/obstacles, Game Over → tally → `DeadzoneManager.on_runner_finished()` merges `food/metal/ammo/score` back to Base and syncs to backend via `PUT /api/resources/:userId`.

## 📁 Structure (Merged)

```
Deadzone/
├── project.godot (single)
├── scripts/
│   ├── core/DeadzoneManager.gd  ← SINGLE AUTLOAD (replaces GameManager/ResourceManager/SaveManager)
│   ├── base/ (BuildingData, Building, BaseGrid, BuildMenu, BuildingInspector, MainBase)
│   └── runner/ (Player, Zombie, BarrelGate, Spawner, Bullet, Obstacle, HUD, Main)
├── scenes/
│   ├── Menu.tscn
│   ├── Base.tscn
│   └── Runner.tscn
└── web-export/ (single HTML5 export of whole game)
```

**Single Save:** `user://deadzone_save.json` stores `last_save_unix`, `resources`, `last_run`, `buildings[]` with `upgrade_finish_unix`. On load, `DeadzoneManager` calculates offline seconds, completes upgrades even if closed, adds `food_per_sec * offline`, recalculates generation.

## 🚀 Test the Unified Game

1. Godot 4.2+ → Import `Deadzone/project.godot`
2. Autoload: `DeadzoneManager.gd` as `DeadzoneManager`
3. Play `Menu.tscn` → Login → Go to **Base** → Place Farm → Upgrade Lv.2 (30s) → **Launch Run** → Play 30s → Die → Back to Base → see loot + upgraded Farm now producing `+1.0 food/s`.

**Web Export (single):** `Deadzone/web-export/index.html` will contain both Base + Runner in one canvas (coming next).

All previous separate builds (`godot-runner`, `godot-basebuilder`) are now archived — this is the only project going forward.
