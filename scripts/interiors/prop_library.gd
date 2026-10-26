@tool
class_name PropLibrary
extends RefCounted
## Every prop scene (scenes/interiors/props/*.tscn), indexed without building them: its tags,
## socket kinds, themes, wealth range, snap and weight are read from the saved scene. Spawn points
## ask here for something that fits (pick). New props in the folder are found automatically.

const DIR := "res://scenes/interiors/props/"

class Entry:
	var path := ""
	var tags: PackedStringArray = []
	var kinds: PackedStringArray = []
	var themes: PackedStringArray = []
	var wealth_min := 0
	var wealth_max := 2
	var weight := 1.0
	var radius := 0.5
	var snap := 0

static var _all: Array[Entry] = []
static var _loaded := false


static func all() -> Array[Entry]:
	if _loaded:
		return _all
	_loaded = true
	for f in DirAccess.get_files_at(DIR):
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tscn"):
			continue
		var ps := load(DIR + file) as PackedScene
		if ps == null:
			continue
		var st := ps.get_state()
		var e := Entry.new()
		e.path = DIR + file
		for i in st.get_node_property_count(0):
			var v: Variant = st.get_node_property_value(0, i)
			match st.get_node_property_name(0, i):
				&"tags": e.tags = v
				&"socket_kinds": e.kinds = v
				&"themes": e.themes = v
				&"wealth_min": e.wealth_min = v
				&"wealth_max": e.wealth_max = v
				&"weight": e.weight = v
				&"radius": e.radius = v
				&"snap": e.snap = v
		_all.append(e)
	return _all


## A prop for a spawn point: of its kind, matching one of its tags (if it has any), fitting the
## theme and wealth. Weighted by the props' Weight. null when nothing fits.
static func pick(kind: String, tags: PackedStringArray, theme: String, wealth: int, rng: RandomNumberGenerator) -> Entry:
	var fits: Array[Entry] = []
	var total := 0.0
	for e in all():
		if not e.kinds.has(kind):
			continue
		if not e.themes.is_empty() and not e.themes.has(theme):
			continue
		if wealth < e.wealth_min or wealth > e.wealth_max:
			continue
		if not tags.is_empty():
			var hit := false
			for t in tags:
				if e.tags.has(t) or e.path.get_file().get_basename() == t:
					hit = true
			if not hit:
				continue
		fits.append(e)
		total += e.weight
	if fits.is_empty():
		return null
	var roll := rng.randf() * total
	for e in fits:
		roll -= e.weight
		if roll <= 0.0:
			return e
	return fits[-1]
