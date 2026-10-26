class_name CompassHUD
extends CanvasLayer
## The compass strip at the top of the screen: north, east, south and west turn with you; gold
## diamonds point at active quest targets (with the distance), small squares at towns nearby.
## Walking into a town shows its name for a moment ("Now entering..."). Created by player.gd.

const WIDTH := 560.0
const HEIGHT := 30.0
## Degrees of view the strip covers, left to right
const SPAN_DEG := 180.0
const TOWN_RANGE := 1500.0

var _strip: Strip
var _banner: Label
var _banner_sub: Label
var _banner_time := 0.0
var _player: Node3D
var _last_town := ""
var _town_timer := 0.0


class Strip extends Control:
	var owner_hud: CompassHUD

	func _draw() -> void:
		if owner_hud != null:
			owner_hud.draw_strip(self)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # hides itself while menus pause the game
	layer = 5
	_player = get_parent() as Node3D
	_strip = Strip.new()
	_strip.owner_hud = self
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.anchor_left = 0.5
	_strip.anchor_right = 0.5
	_strip.offset_left = -WIDTH * 0.5
	_strip.offset_right = WIDTH * 0.5
	_strip.offset_top = 8
	_strip.offset_bottom = 8 + HEIGHT + 16
	add_child(_strip)
	_banner = _label(40)
	_banner.offset_top = 150
	_banner.offset_bottom = 200
	add_child(_banner)
	_banner_sub = _label(20)
	_banner_sub.offset_top = 198
	_banner_sub.offset_bottom = 226
	add_child(_banner_sub)


func _label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	l.modulate.a = 0.0
	return l


## Shows a name in the middle of the screen for a few seconds
func show_banner(title: String, subtitle: String = "") -> void:
	_banner.text = title
	_banner_sub.text = subtitle
	_banner_time = 3.5


func _process(delta: float) -> void:
	var paused := get_tree().paused
	_strip.visible = not paused and bool(GameSettings.get_value("show_compass"))
	_banner_time = maxf(_banner_time - delta, 0.0)
	var a := clampf(_banner_time / 0.8, 0.0, 1.0) * (0.0 if paused else 1.0)
	_banner.modulate.a = a
	_banner_sub.modulate.a = a
	if paused:
		return
	_strip.queue_redraw()
	_town_timer -= delta
	if _town_timer <= 0.0:
		_town_timer = 0.5
		_check_town()


# "Now entering ..." when you walk into a town
func _check_town() -> void:
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	if world == null or _player == null:
		return
	var dm := world.dungeons
	if dm != null and dm.is_inside():
		return
	var town := world.get_town_at(_player.global_position, -10.0)
	var id := town.id if town != null else ""
	if id == _last_town:
		return
	if town != null and town.town != null:
		var biome := world.get_biome_at(town.position.x, town.position.z)
		var kind := (town.poi as TownData).display_name.to_lower()
		var fest := Festivals.current(world.clock)
		var sub := "%s · %s" % [kind.capitalize(), biome.display_name if biome != null else ""]
		if Festivals.keeps(fest, world, town):
			sub = "%s  ·  %s" % [fest["name"], sub]
		show_banner(town.town.display_name, sub)
	elif _last_town != "":
		var left := world.get_poi(_last_town)
		if left != null and left.town != null:
			show_banner("Leaving %s" % left.town.display_name)
			_banner_time = 2.0
	_last_town = id


# Where on the strip a world direction is (pixels from the middle), or INF when behind you
func _strip_x(heading: float, to: Vector3) -> float:
	var ang := atan2(to.x, -to.z)  # 0 = north (-Z), +PI/2 = east (+X)
	var diff := wrapf(ang - heading, -PI, PI)
	var half := deg_to_rad(SPAN_DEG * 0.5)
	if absf(diff) > half:
		return INF
	return diff / half * WIDTH * 0.5


func draw_strip(c: Control) -> void:
	if _player == null:
		return
	var font := ThemeDB.fallback_font
	var forward := -_player.global_transform.basis.z
	var heading := atan2(forward.x, -forward.z)
	var mid := WIDTH * 0.5
	c.draw_rect(Rect2(0, 0, WIDTH, HEIGHT), Color(0, 0, 0, 0.45))
	c.draw_rect(Rect2(0, 0, WIDTH, HEIGHT), Color(1, 1, 1, 0.25), false, 1.0)
	# ticks and letters every 45 degrees
	var names := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	for k in 8:
		var ang := float(k) * PI / 4.0
		var x := _strip_x(heading, Vector3(sin(ang), 0.0, -cos(ang)))
		if x == INF:
			continue
		var big := k % 2 == 0
		var text: String = names[k]
		var size := 18 if big else 13
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var col := Color(1.0, 0.45, 0.4) if k == 0 else Color(1, 1, 1, 0.95 if big else 0.65)
		c.draw_string(font, Vector2(mid + x - w * 0.5, HEIGHT * 0.5 + size * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	for k in 24:
		if k % 3 == 0:
			continue
		var ang := float(k) * PI / 12.0
		var x := _strip_x(heading, Vector3(sin(ang), 0.0, -cos(ang)))
		if x != INF:
			c.draw_line(Vector2(mid + x, HEIGHT - 7), Vector2(mid + x, HEIGHT - 2), Color(1, 1, 1, 0.4), 1.0)
	var world := get_tree().get_first_node_in_group("world_manager") as WorldManager
	var here := _player.global_position
	var dm := world.dungeons if world != null else null
	if world != null and not (dm != null and dm.is_inside()):
		# towns nearby
		for t in world.towns:
			var d := Vector2(t.position.x - here.x, t.position.z - here.z).length()
			if d > TOWN_RANGE or d < 30.0 or t.town == null:
				continue
			var x := _strip_x(heading, t.position - here)
			if x == INF:
				continue
			c.draw_rect(Rect2(mid + x - 3.5, 5, 7, 7), Color(0.95, 0.85, 0.55, 0.9))
			if absf(x) < 60.0:
				var tw := font.get_string_size(t.town.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				c.draw_string_outline(font, Vector2(mid + x - tw * 0.5, HEIGHT + 12), t.town.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
				c.draw_string(font, Vector2(mid + x - tw * 0.5, HEIGHT + 12), t.town.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.92, 0.7))
		# quest targets
		for target in QuestManager.compass_targets():
			var pos: Vector2 = target["pos"]
			var to := Vector3(pos.x - here.x, 0.0, pos.y - here.z)
			var x := _strip_x(heading, to)
			if x == INF:
				x = -mid + 8.0 if wrapf(atan2(to.x, -to.z) - heading, -PI, PI) < 0.0 else mid - 8.0  # behind: pinned to the side it is on
			var at := Vector2(mid + x, HEIGHT * 0.5)
			var dia := PackedVector2Array([at + Vector2(0, -8), at + Vector2(7, 0), at + Vector2(0, 8), at + Vector2(-7, 0)])
			c.draw_colored_polygon(dia, Color(1.0, 0.85, 0.2))
			c.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color.BLACK, 1.2)
			var dist := "%dm" % roundi(to.length()) if to.length() < 1000.0 else "%.1fkm" % (to.length() / 1000.0)
			var dw := font.get_string_size(dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			c.draw_string_outline(font, Vector2(at.x - dw * 0.5, HEIGHT + 12), dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
			c.draw_string(font, Vector2(at.x - dw * 0.5, HEIGHT + 12), dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.9, 0.4))
		# your map markers (blue), only when they are ahead; the name shows when you face one
		for m in MapMarkers.all():
			var mpos: Vector2 = m["pos"]
			var mto := Vector3(mpos.x - here.x, 0.0, mpos.y - here.z)
			var mx := _strip_x(heading, mto)
			if mx == INF or mto.length() < 5.0:
				continue
			var mat := Vector2(mid + mx, HEIGHT * 0.5)
			c.draw_circle(mat, 5.5, Color.BLACK)
			c.draw_circle(mat, 4.5, WorldDebugMap.MARKER_COLOR)
			if absf(mx) < 40.0:
				var mtext := "%s  %s" % [m["name"], "%dm" % roundi(mto.length()) if mto.length() < 1000.0 else "%.1fkm" % (mto.length() / 1000.0)]
				var mw := font.get_string_size(mtext, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				c.draw_string_outline(font, Vector2(mat.x - mw * 0.5, HEIGHT + 24), mtext, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
				c.draw_string(font, Vector2(mat.x - mw * 0.5, HEIGHT + 24), mtext, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WorldDebugMap.MARKER_COLOR.lightened(0.4))
	elif dm != null and dm.nav != null:
		# inside a stitched dungeon: the way out (white), and the quest's room (gold) when a quest
		# points at this place, by the doorways (the next doorway on the way, not through walls)
		var root := dm.get_interior_root()
		var exit := root.find_child("Exit", true, false) as Node3D if root != null else null
		var marks: Array = []
		if exit != null:
			marks.append([exit.global_position, Color(0.95, 0.95, 0.95), "Exit"])
		var boss := dm.nav.boss_room()
		var poi := world.get_poi(dm.current_entrance_id)
		if boss >= 0 and poi != null:
			for t in QuestManager.compass_targets():
				if (t["pos"] as Vector2).distance_to(Vector2(poi.position.x, poi.position.z)) < 60.0:
					marks.append([dm.nav.room_center(boss), Color(1.0, 0.85, 0.2), ""])
					break
		for m: Array in marks:
			var way := dm.nav.path(here, m[0])
			var to: Vector3 = way[0] - here
			var x := _strip_x(heading, to)
			if x == INF:
				continue
			var at := Vector2(mid + x, HEIGHT * 0.5)
			var dia := PackedVector2Array([at + Vector2(0, -7), at + Vector2(6, 0), at + Vector2(0, 7), at + Vector2(-6, 0)])
			c.draw_colored_polygon(dia, m[1])
			c.draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color.BLACK, 1.2)
			if String(m[2]) != "" and absf(x) < 50.0:
				var ew := font.get_string_size(m[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
				c.draw_string_outline(font, Vector2(at.x - ew * 0.5, HEIGHT + 12), m[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color.BLACK)
				c.draw_string(font, Vector2(at.x - ew * 0.5, HEIGHT + 12), m[2], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	# the middle mark
	c.draw_line(Vector2(mid, 0), Vector2(mid, 6), Color(1.0, 0.85, 0.35), 2.0)
