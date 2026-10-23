class_name Epilogue
extends CanvasLayer
## The epilogue (lore bible): a short narrated ending, one line per finished questline, picked by
## the player's choices, like the end slides of a classic RPG. It plays when the main story "The
## Ashen Eclipse" ends and again when the Regency Council has chosen; the Council page in the Tab
## menu can show it again at any time ("The Chronicle"). Questlines not finished yet are left out.
##   Epilogue.play(get_tree(), "The Ashen Eclipse")

const NAME := "Epilogue"
## Seconds each line takes to fade in
const LINE_TIME := 2.2


static func play(tree: SceneTree, title: String) -> void:
	if tree.root.get_node_or_null(NAME) != null:
		return
	var e := Epilogue.new()
	e.name = NAME
	e._title_text = title
	tree.root.add_child(e)


## The lines, in order: one per questline the player has finished
static func lines() -> PackedStringArray:
	var out := PackedStringArray()
	var add := func(text: String) -> void: out.append(text)
	# The main story
	if Story.stage() >= 6:
		add.call("The Ash Hierophant is dead and his circle broken. The sun rose over Caldreth as it always had, and few ever knew how close it came to not rising.")
	if QuestBook.is_done("S-CH07"):
		add.call("Beneath Cinderhold, the gate of the Black Sun is sealed. The Ashborn still leave a cup of water at its door each Deepwinter.")
	# Kingsreach and the King
	if QuestBook.flag("S-KR07:morvaine"):
		add.call("The royal taster's ledger sent a Morvaine steward to the block, and House Morvaine never quite washed the poison from its name.")
	elif QuestBook.flag("S-KR07:framed"):
		add.call("The poisoner's crime was laid at a rival house's door. The truth stayed buried in Blackfen, where truths usually do.")
	if QuestBook.flag("S-KR08:saved"):
		add.call("King Aldren lived one more year, long enough to set his realm in order and to see his granddaughter laugh again.")
	elif QuestBook.flag("S-KR08:peace"):
		add.call("King Aldren signed his will and died in peace, with the Reliquary of Aurel cold in his hands.")
	# The regency
	if Regency.is_settled():
		add.call(String(Regency.result().get("text", "")))
	# The great cities
	if QuestBook.flag("S-MW07:duke"):
		add.call("Merewater learned to hide itself in fog, and Duke Valcourt's lake became the safest water in the realm.")
	elif QuestBook.flag("S-MW07:mages"):
		add.call("The Fog Crystal went to the Mages Guild, and the scholars of Merewater still argue over what it remembers.")
	if QuestBook.is_done("S-SM07"):
		add.call("With the Saltbones broken, ships sail to the Isles again, and the coast's pirates drink to better days.")
	if QuestBook.is_done("S-TH07"):
		add.call("Nyssa Varn's letters cleared House Ashgrove at court, and the Greyfang remember who brought their brother home.")
	if QuestBook.is_done("S-BF07"):
		add.call("Blackfen's undercroft is quiet. Lady Mireille's name is still whispered on the causeways, but softly now.")
	if QuestBook.flag("S-SH07:loyal"):
		add.call("The Desert Accord was renewed, and Sahrim's riders stand with the Crown.")
	elif QuestBook.flag("S-SH07:broken"):
		add.call("The Desert Accord is broken. Sunhold keeps its own counsel now, a rival across the sands.")
	if QuestBook.is_done("S-CG07"):
		add.call("Deep in the Barrowdeep, the Barrow Folk remember who stood before their crown, and the Highland roads are safer for it.")
	if QuestBook.flag("S-WG05:loyal"):
		add.call("The Winter Moot voted for loyalty, and the Northmarch keeps its oath.")
	elif QuestBook.flag("S-WG05:free"):
		add.call("The Winter Moot voted to leave. The Northmarch is its own land now, and its border fires burn every night.")
	if QuestBook.is_done("S-WG07"):
		add.call("On the Isle of Winter the Queen's call has gone quiet, for now.")
	# The night
	if QuestBook.flag("V-VC08:regency"):
		add.call("The Velvet Court rules from behind a living throne. Caldreth sleeps soundly and wakes a little paler each year.")
	elif QuestBook.flag("V-VC08:betrayed"):
		add.call("The Knightly Order purged the Velvet Court, root and thrall. The masked balls were never quite the same.")
	elif QuestBook.flag("V-VC08:master"):
		add.call("Prince Vaelith fell while he fed, and the Velvet Court bowed to a new master: you.")
	if QuestBook.flag("V-HK08:fed"):
		add.call("Prince Ghaur fed, and the Highland villages learned to bar their doors at dusk.")
	elif QuestBook.flag("V-HK08:leader"):
		add.call("The Hollow Kin answer to a new Mother, and their hunts grew calmer.")
	if QuestBook.flag("V-AC08:north"):
		add.call("A long dusk lies over the north. The Ashen Choir sings there still.")
	elif QuestBook.flag("V-AC08:realm"):
		add.call("Dusk fell over all of Caldreth, and the Ashen Choir's song was the last thing many heard.")
	elif QuestBook.flag("V-AC08:choirmaster"):
		add.call("Somnir the Cantor was betrayed, and the Ashen Choir follows your voice now.")
	if QuestBook.flag("W-GF08:brenna"):
		add.call("Brenna keeps the peace of the Greyfang, and the forest roads are safe at night.")
	elif QuestBook.flag("W-GF08:fenris"):
		add.call("Fenris won the pack, and the forest villages burned their wolf-fires high.")
	elif QuestBook.flag("W-GF08:alpha"):
		add.call("The Greyfang run under a new Alpha: you.")
	# The guilds
	var led := PackedStringArray()
	for g in Factions.GUILDS:
		if Factions.is_member(g) and Factions.rank(g) >= 5:
			led.append(Factions.display_name(g))
	if not led.is_empty():
		add.call("You lead the %s. Their halls across the realm open their doors to you." % ", ".join(led))
	return out


var _title_text := ""
var _box: VBoxContainer
var _shown := 0
var _clock := 0.0
var _all: PackedStringArray


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_all = lines()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.025, 0.02, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 40
	scroll.offset_bottom = -70
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(720, 0)
	_box.add_theme_constant_override("separation", 16)
	center.add_child(_box)
	var title := Label.new()
	title.text = _title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	_box.add_child(title)
	if _all.is_empty():
		_all.append("Your story in Caldreth has only begun.")
	var close := Button.new()
	close.text = "Continue"
	close.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	close.offset_top = -56
	close.offset_bottom = -20
	close.offset_left = -70
	close.offset_right = 70
	close.pressed.connect(_close)
	add_child(close)


func _process(delta: float) -> void:
	# One line at a time, each fading in; a click or a key shows the rest at once
	_clock -= delta
	if _clock > 0.0 or _shown >= _all.size():
		return
	_clock = LINE_TIME
	var l := Label.new()
	l.text = _all[_shown]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", Color(0.86, 0.82, 0.74))
	l.modulate.a = 0.0
	_box.add_child(l)
	create_tween().tween_property(l, "modulate:a", 1.0, LINE_TIME * 0.6)
	_shown += 1


func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed() and _shown < _all.size():
		while _shown < _all.size():
			_clock = 0.0
			_process(0.0)
		get_viewport().set_input_as_handled()


func _close() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
