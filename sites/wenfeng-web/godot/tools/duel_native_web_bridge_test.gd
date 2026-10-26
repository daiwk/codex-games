extends "res://scripts/web_bridge.gd"
# Native QA only: production command dispatch is unchanged. Disable only the
# unavailable browser publication sink, not input/action processing.
func _publish()->void:pass
