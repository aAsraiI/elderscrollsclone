extends SceneTree
## Rebuilds res://ui/ui_theme.tres from scripts/UI/ui_theme.gd. Run with:
##   godot --headless --path . -s res://tools/build_ui_theme.gd


func _initialize() -> void:
	var err := UITheme.save()
	print("ui_theme.tres written" if err == OK else "could not write ui_theme.tres (error %d)" % err)
	quit(0 if err == OK else 1)
