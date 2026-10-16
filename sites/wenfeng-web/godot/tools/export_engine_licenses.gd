extends SceneTree

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected license output directory")
		quit(1)
		return
	var directory = args[0]
	DirAccess.make_dir_recursive_absolute(directory)
	var engine_license = FileAccess.open(directory.path_join("Godot-LICENSE.txt"), FileAccess.WRITE)
	engine_license.store_string(Engine.get_license_text() + "\n")
	var third_party = FileAccess.open(directory.path_join("Godot-THIRD-PARTY.txt"), FileAccess.WRITE)
	third_party.store_string("Godot Engine third-party components\n\n")
	for component in Engine.get_copyright_info():
		third_party.store_string(str(component) + "\n\n")
	var license_texts = Engine.get_license_info()
	var names = license_texts.keys()
	names.sort()
	for license_name in names:
		third_party.store_string(str(license_name) + "\n" + str(license_texts[license_name]) + "\n\n")
	quit()
