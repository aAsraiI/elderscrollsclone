class_name MwBsa
extends RefCounted
## Reads a Morrowind .bsa archive (version 0x100): a list of files, each stored uncompressed.
## Names are lower case with backslashes ("meshes\b\b_n_dark elf_m_chest.nif").

var path := ""
var _files := {}  # name -> [offset in the archive, size]


static func open(p: String) -> MwBsa:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	if f.get_32() != 0x100:
		return null
	var hash_offset := f.get_32()
	var count := f.get_32()
	var sizes := PackedInt64Array()
	var offsets := PackedInt64Array()
	for i in count:
		sizes.append(f.get_32())
		offsets.append(f.get_32())
	var name_offsets := PackedInt64Array()
	for i in count:
		name_offsets.append(f.get_32())
	var names_start := 12 + count * 8 + count * 4
	var names_len := hash_offset - count * 12
	f.seek(names_start)
	var names := f.get_buffer(names_len)
	var data_start := 12 + hash_offset + count * 8
	var b := MwBsa.new()
	b.path = p
	for i in count:
		var start := int(name_offsets[i])
		var end := names.find(0, start)
		var n := names.slice(start, end).get_string_from_ascii().to_lower()
		b._files[n] = [data_start + offsets[i], sizes[i]]
	return b


func has(file_name: String) -> bool:
	return _files.has(file_name)


func read(file_name: String) -> PackedByteArray:
	var e = _files.get(file_name)
	if e == null:
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	f.seek(e[0])
	return f.get_buffer(e[1])


func names() -> Array:
	return _files.keys()
