extends "res://scripts/rpg_main.gd"

# Keep the actual RPG input, lock targeting and strike resolver; isolate world
# streaming, AI, UI and persistence so a single accepted J is measurable.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	testing = true
	_configure_inputs()
	fx = Effects.new()
	fx.muted = true
	add_child(fx)
	phase = "explore"

func _process(_delta: float) -> void:
	pass

func _update_enemies(_delta: float) -> void:
	pass

func _update_streaming() -> void:
	pass

func _save_game() -> bool:
	return true
