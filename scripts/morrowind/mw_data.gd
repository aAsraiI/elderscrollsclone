class_name MwData
extends RefCounted
## A Morrowind "Data Files" folder: loose files first, then the .bsa archives (later ones win),
## plus the .esm records characters need. Paths are like "meshes\b\b_n_imperial_m_foot.nif".

const ARCHIVES := ["Morrowind.bsa", "Tribunal.bsa", "Bloodmoon.bsa"]
const MASTERS := ["Morrowind.esm", "Tribunal.esm", "Bloodmoon.esm"]

var folder := ""
var esm := MwEsm.new()
var _bsas: Array[MwBsa] = []
var _nifs := {}


## Where Steam or GOG usually put Morrowind ("" when not found)
static func find_install() -> String:
	var tries := [
		"C:/Program Files (x86)/Steam/steamapps/common/Morrowind/Data Files",
		"C:/Program Files/Steam/steamapps/common/Morrowind/Data Files",
		"C:/GOG Games/Morrowind/Data Files",
		"C:/Program Files (x86)/GOG Galaxy/Games/Morrowind/Data Files",
		"C:/Program Files (x86)/Bethesda Softworks/Morrowind/Data Files",
	]
	# Other Steam libraries
	var vdf := "C:/Program Files (x86)/Steam/steamapps/libraryfolders.vdf"
	if FileAccess.file_exists(vdf):
		var re := RegEx.create_from_string("\"path\"\\s+\"([^\"]+)\"")
		for m in re.search_all(FileAccess.get_file_as_string(vdf)):
			tries.append(m.get_string(1).replace("\\\\", "/") + "/steamapps/common/Morrowind/Data Files")
	for t in tries:
		if FileAccess.file_exists(String(t).path_join("Morrowind.esm")):
			return t
	return ""


## Opens a Data Files folder (null if it has no Morrowind.esm)
static func open(p_folder: String) -> MwData:
	if not FileAccess.file_exists(p_folder.path_join("Morrowind.esm")):
		return null
	var d := MwData.new()
	d.folder = p_folder
	for a in ARCHIVES:
		var b := MwBsa.open(p_folder.path_join(a))
		if b != null:
			d._bsas.append(b)
	for m in MASTERS:
		var p := p_folder.path_join(m)
		if FileAccess.file_exists(p):
			d.esm.read(p)
	return d


func has(path: String) -> bool:
	path = path.to_lower().replace("/", "\\")
	if FileAccess.file_exists(folder.path_join(path.replace("\\", "/"))):
		return true
	for b in _bsas:
		if b.has(path):
			return true
	return false


func read(path: String) -> PackedByteArray:
	path = path.to_lower().replace("/", "\\")
	var loose := folder.path_join(path.replace("\\", "/"))
	if FileAccess.file_exists(loose):
		return FileAccess.get_file_as_bytes(loose)
	for i in range(_bsas.size() - 1, -1, -1):
		if _bsas[i].has(path):
			return _bsas[i].read(path)
	return PackedByteArray()


var _all_names: PackedStringArray = []


## The first archived file matching any of the patterns, tried in order ("meshes\w\w_*_longsword.nif",
## with * and ?; case does not matter; "/" works for "\"). "" if none.
func find(patterns: Array) -> String:
	if _all_names.is_empty():
		var seen := {}
		for b in _bsas:
			for n in b.names():
				seen[n] = true
		_all_names = PackedStringArray(seen.keys())
		_all_names.sort()
	for p in patterns:
		var pat := String(p).to_lower().replace("/", "\\")
		if not pat.contains("*") and not pat.contains("?"):
			if has(pat):
				return pat
			continue
		for n in _all_names:
			if n.match(pat):
				return n
	return ""


## A parsed .nif / .kf (cached), or null
func nif(path: String) -> MwNif:
	path = path.to_lower().replace("/", "\\")
	if not _nifs.has(path):
		var bytes := read(path)
		var n: MwNif = MwNif.parse(bytes) if not bytes.is_empty() else null
		if n != null and n.error != "":
			push_warning("Morrowind: %s: %s" % [path, n.error])
			n = null
		_nifs[path] = n
	return _nifs[path]


## Where converted textures are saved, so every model made in one import shares them ("" = kept in memory)
var texture_dir := ""
var _textures := {}


## A texture by the name a .nif gives it (they say .tga / .bmp; the files are mostly .dds)
func texture(name: String) -> Texture2D:
	var stem := name.to_lower().get_basename().get_file()
	if _textures.has(stem):
		return _textures[stem]
	var tex := _load_texture(name)
	if tex != null and texture_dir != "":
		var p := texture_dir.path_join(stem.validate_filename() + ".res")
		if ResourceSaver.save(tex, p, ResourceSaver.FLAG_COMPRESS) == OK:
			tex.take_over_path(p)
	_textures[stem] = tex
	return tex


func _load_texture(name: String) -> Texture2D:
	var stem := name.to_lower().get_basename()
	for ext in [".dds", "." + name.get_extension().to_lower(), ".tga", ".bmp"]:
		var p: String = "textures\\" + stem + ext
		var bytes := read(p)
		if bytes.is_empty():
			continue
		var img := Image.new()
		var err := FAILED
		match ext:
			".dds":
				img = dds_image(bytes)
				err = OK if img != null else FAILED
			".tga":
				err = img.load_tga_from_buffer(bytes)
			".bmp":
				err = img.load_bmp_from_buffer(bytes)
		if err == OK and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			img.generate_mipmaps()
			return ImageTexture.create_from_image(img)
	return null


## The full-size picture of a .dds. Morrowind's often stop their mipmap chain early, which Godot's
## own loader refuses, so only the first level is read (mipmaps are made again afterwards).
static func dds_image(bytes: PackedByteArray) -> Image:
	if bytes.size() < 128 or bytes.slice(0, 4).get_string_from_ascii() != "DDS ":
		return null
	var h := bytes.decode_u32(12)
	var w := bytes.decode_u32(16)
	var pf_flags := bytes.decode_u32(80)
	var four := bytes.slice(84, 88).get_string_from_ascii()
	var bits := bytes.decode_u32(88)
	var data := bytes.slice(128)
	if pf_flags & 4:  # compressed
		var fmt := Image.FORMAT_DXT1
		var block := 8
		match four:
			"DXT3":
				fmt = Image.FORMAT_DXT3
				block = 16
			"DXT5":
				fmt = Image.FORMAT_DXT5
				block = 16
			"DXT1":
				pass
			_:
				return null
		var size := maxi(1, (w + 3) / 4) * maxi(1, (h + 3) / 4) * block
		if data.size() < size:
			return null
		return Image.create_from_data(w, h, false, fmt, data.slice(0, size))
	# Uncompressed BGR / BGRA
	var bpp := bits / 8
	if bpp != 3 and bpp != 4 or data.size() < w * h * bpp:
		return null
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)
	var has_alpha := pf_flags & 1 != 0 and bpp == 4
	for i in w * h:
		rgba[i * 4] = data[i * bpp + 2]
		rgba[i * 4 + 1] = data[i * bpp + 1]
		rgba[i * 4 + 2] = data[i * bpp]
		rgba[i * 4 + 3] = data[i * bpp + 3] if has_alpha else 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
