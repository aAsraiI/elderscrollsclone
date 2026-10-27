class_name MwEsm
extends RefCounted
## Reads the records a character needs from Morrowind .esm / .esp files: body parts (BODY), armour
## (ARMO), clothing (CLOT) and races (RACE). Later files override earlier ones by id.
##   bodies[id]  = {"model", "race", "part", "female", "playable", "kind"}   kind 0 skin, 1 clothing, 2 armour
##   wearables[id] = {"name", "model", "slots": [[slot, male part id, female part id], ...], "armor"}
##   races[id]   = {"name", "beast", "male_height", "female_height"}

## Body part kinds in BODY records (BYDT part)
enum Part { HEAD, HAIR, NECK, CHEST, GROIN, HAND, WRIST, FOREARM, UPPERARM, FOOT, ANKLE, KNEE, UPPERLEG, CLAVICLE, TAIL }

var bodies := {}
var wearables := {}
var races := {}


func read(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var size := f.get_length()
	while f.get_position() + 16 <= size:
		var tag := f.get_buffer(4).get_string_from_ascii()
		var length := f.get_32()
		f.get_32()
		f.get_32()
		var end := f.get_position() + length
		match tag:
			"BODY", "ARMO", "CLOT", "RACE":
				_record(tag, f.get_buffer(length))
		f.seek(end)
	return true


func _record(tag: String, data: PackedByteArray) -> void:
	var s := StreamPeerBuffer.new()
	s.data_array = data
	var id := ""
	var r := {"slots": []}
	var last_slot := -1
	while s.get_position() + 8 <= data.size():
		var sub := (s.get_data(4)[1] as PackedByteArray).get_string_from_ascii()
		var n := s.get_u32()
		var start := s.get_position()
		match sub:
			"NAME":
				id = _z(s, n).to_lower()
			"MODL":
				r["model"] = _z(s, n)
			"FNAM":
				r["fnam"] = _z(s, n)
			"BYDT":
				r["part"] = s.get_u8()
				s.get_u8()  # vampire
				var flags := s.get_u8()
				r["female"] = flags & 1 != 0
				r["playable"] = flags & 2 != 0
				r["kind"] = s.get_u8()
			"INDX":
				last_slot = s.get_u8()
				r["slots"].append([last_slot, "", ""])
			"BNAM":
				if not r["slots"].is_empty():
					r["slots"][-1][1] = _z(s, n).to_lower()
			"CNAM":
				if tag != "RACE" and not r["slots"].is_empty():
					r["slots"][-1][2] = _z(s, n).to_lower()
			"RADT":
				s.seek(start + 7 * 4 * 2)  # skill bonuses
				for i in 8 * 2:
					s.get_32()  # attributes male/female
				r["male_height"] = s.get_float()
				r["female_height"] = s.get_float()
				s.get_float()
				s.get_float()
				r["beast"] = s.get_32() & 2 != 0
		s.seek(start + n)
	if id == "":
		return
	match tag:
		"BODY":
			bodies[id] = {"model": r.get("model", ""), "race": String(r.get("fnam", "")).to_lower(), "part": r.get("part", 0),
				"female": r.get("female", false), "playable": r.get("playable", false), "kind": r.get("kind", 0)}
		"ARMO", "CLOT":
			wearables[id] = {"name": r.get("fnam", id), "model": r.get("model", ""), "slots": r["slots"], "armor": tag == "ARMO"}
		"RACE":
			races[id] = {"name": r.get("fnam", id), "beast": r.get("beast", false),
				"male_height": r.get("male_height", 1.0), "female_height": r.get("female_height", 1.0)}


static func _z(s: StreamPeerBuffer, n: int) -> String:
	var b := s.get_data(n)[1] as PackedByteArray
	var end := b.find(0)
	if end >= 0:
		b = b.slice(0, end)
	return b.get_string_from_ascii()
