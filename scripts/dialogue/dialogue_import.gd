class_name DialogueImport
extends RefCounted
## Dialogue written in a spreadsheet: every .csv and .json in data/dialogue/ becomes hand-written
## dialogue (DialogueData), loaded with the .tres ones. One row per answer:
##
##   who                 everyone | role:innkeeper | npc/<building id> | custom/<id>
##   topic               the topic's name ("the old mill")
##   text                the answer ({town} {name} {guild} {nearest_poi} {nearest_town} work)
##   min_disposition     0-100 (optional)
##   need_flag, not_flag, set_flag   flags (optional)
##   learn_on_greeting   yes / no: the topic is known as soon as you greet them
##   choices             follow-up topics offered under the answer, separated by |
##   learn               extra topics learned, separated by |
##
## Rows with the same who and topic are the topic's answers, tried in order (the first whose
## conditions pass is spoken). A .csv needs the first row to be these column names. A .json is a
## list of objects with the same keys. Keep .csv files as plain files (their .import says "keep").

const COLUMNS := ["who", "topic", "text", "min_disposition", "need_flag", "not_flag", "set_flag", "learn_on_greeting", "choices", "learn"]


## Every DialogueData made from the .csv and .json files of a folder
static func load_dir(dir: String) -> Array[DialogueData]:
	var out: Array[DialogueData] = []
	var names := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if (f.ends_with(".csv") or f.ends_with(".json")) and not names.has(f):
			names.append(f)
	names.sort()
	for f in names:
		out.append_array(load_file(dir + "/" + f))
	return out


## The rows of one file, grouped into DialogueData (one per "who")
static func load_file(path: String) -> Array[DialogueData]:
	var rows: Array = []
	if path.ends_with(".json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			rows = parsed
	else:
		rows = _csv_rows(path)
	return from_rows(rows)


static func _csv_rows(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var out: Array = []
	var header := PackedStringArray()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() == 1 and line[0].strip_edges() == "":
			continue
		if header.is_empty():
			header = line
			continue
		var row := {}
		for i in mini(header.size(), line.size()):
			row[header[i].strip_edges()] = line[i]
		out.append(row)
	return out


static func from_rows(rows: Array) -> Array[DialogueData]:
	var by_who := {}
	for row: Dictionary in rows:
		var who := String(row.get("who", "everyone")).strip_edges()
		var topic_name := String(row.get("topic", "")).strip_edges()
		if topic_name == "" or String(row.get("text", "")).strip_edges() == "":
			continue
		if not by_who.has(who):
			var d := DialogueData.new()
			if who == "everyone" or who == "":
				d.everyone = true
			elif who.begins_with("role:"):
				d.roles = PackedStringArray([who.trim_prefix("role:")])
			else:
				d.npc_ids = PackedStringArray([who])
			by_who[who] = d
		var data: DialogueData = by_who[who]
		var t := data.get_topic(topic_name)
		if t == null:
			t = DialogueTopic.new()
			t.topic = topic_name
			data.topics.append(t)
		if String(row.get("learn_on_greeting", "")).to_lower() in ["yes", "true", "1"]:
			t.learn_on_greeting = true
		var r := DialogueResponse.new()
		r.text = String(row["text"])
		r.min_disposition = int(row.get("min_disposition", 0))
		r.need_flag = String(row.get("need_flag", ""))
		r.not_flag = String(row.get("not_flag", ""))
		r.set_flag = String(row.get("set_flag", ""))
		r.choices = _list(String(row.get("choices", "")))
		r.learn_topics = _list(String(row.get("learn", "")))
		t.responses.append(r)
	var out: Array[DialogueData] = []
	for d in by_who.values():
		out.append(d)
	return out


static func _list(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for x in text.split("|", false):
		if x.strip_edges() != "":
			out.append(x.strip_edges())
	return out
