extends "res://scripts/rpg_main.gd"
## Test-only complete RPG world/controller/UI; only persistence and autonomous AI are
## isolated, to avoid touching the user's save or incidental battle damage.
func _save_game() -> bool: return true
func _load_game() -> bool: return false
func _update_enemies(_delta: float) -> void: pass
