class_name MwNif
extends RefCounted
## Reads a Morrowind .nif / .kf (NetImmerse 4.0.0.2). Every record becomes a Dictionary with its
## "type" and fields; references are record indices (-1 = none). NIF 4.0 does not store record
## sizes, so every record type in a file must be known: an unknown one stops the read (`error`).

var records: Array = []
var roots: PackedInt32Array = []
var error := ""
var _s: StreamPeerBuffer


static func parse(bytes: PackedByteArray) -> MwNif:
	var n := MwNif.new()
	n._s = StreamPeerBuffer.new()
	n._s.data_array = bytes
	n._read()
	n._s = null
	return n


func _read() -> void:
	var header := _line()
	if not header.begins_with("NetImmerse File Format"):
		error = "not a NIF file"
		return
	var version := _s.get_u32()
	if version != 0x04000002:
		error = "NIF version %x is not Morrowind's" % version
		return
	var count := _s.get_u32()
	for i in count:
		var type := _str()
		var r := {"type": type}
		if not _record(type, r):
			error = "unknown record type %s (record %d)" % [type, i]
			return
		records.append(r)
	var nroots := _s.get_u32()
	for i in nroots:
		roots.append(_s.get_32())


# ---------------------------------------------------------------- reading helpers

func _line() -> String:
	var out := PackedByteArray()
	while _s.get_position() < _s.get_size():
		var c := _s.get_u8()
		if c == 10:
			break
		out.append(c)
	return out.get_string_from_ascii()


func _str() -> String:
	var n := _s.get_u32()
	if n == 0:
		return ""
	var r := _s.get_data(n)
	return (r[1] as PackedByteArray).get_string_from_ascii()


func _ref() -> int:
	return _s.get_32()


func _refs() -> PackedInt32Array:
	var out := PackedInt32Array()
	var n := _s.get_u32()
	for i in n:
		out.append(_s.get_32())
	return out


func _bool() -> bool:
	return _s.get_32() != 0


func _vec3() -> Vector3:
	return Vector3(_s.get_float(), _s.get_float(), _s.get_float())


# Stored row by row; points are multiplied as M * v
func _mat3() -> Basis:
	var m := []
	for i in 9:
		m.append(_s.get_float())
	return Basis(Vector3(m[0], m[3], m[6]), Vector3(m[1], m[4], m[7]), Vector3(m[2], m[5], m[8]))


func _skip(n: int) -> void:
	_s.seek(_s.get_position() + n)


# ---------------------------------------------------------------- records

func _record(type: String, r: Dictionary) -> bool:
	match type:
		"NiNode", "RootCollisionNode", "NiBSAnimationNode", "NiBSParticleNode", "AvoidNode", "NiBillboardNode":
			_av_object(r)
			r["children"] = _refs()
			r["effects"] = _refs()
		"NiTriShape":
			_av_object(r)
			r["data"] = _ref()
			r["skin"] = _ref()
		"NiTriShapeData":
			_geometry_data(r)
			var ntris := _s.get_u16()
			_s.get_u32()  # number of triangle points
			var tris := PackedInt32Array()
			tris.resize(ntris * 3)
			for i in ntris * 3:
				tris[i] = _s.get_u16()
			r["triangles"] = tris
			var groups := _s.get_u16()
			for i in groups:
				_skip(_s.get_u16() * 2)
		"NiSkinInstance":
			r["data"] = _ref()
			r["root"] = _ref()
			r["bones"] = _refs()
		"NiSkinData":
			r["basis"] = _mat3()
			r["origin"] = _vec3()
			r["scale"] = _s.get_float()
			var nbones := _s.get_u32()
			r["partition"] = _ref()
			var bones := []
			for i in nbones:
				var b := {}
				b["basis"] = _mat3()
				b["origin"] = _vec3()
				b["scale"] = _s.get_float()
				_skip(16)  # bounding sphere
				var nverts := _s.get_u16()
				var idx := PackedInt32Array()
				var w := PackedFloat32Array()
				for k in nverts:
					idx.append(_s.get_u16())
					w.append(_s.get_float())
				b["vertices"] = idx
				b["weights"] = w
				bones.append(b)
			r["bones"] = bones
		"NiTexturingProperty":
			_object_net(r)
			_s.get_u16()  # flags
			_s.get_u32()  # apply mode
			var ntex := _s.get_u32()
			var tex := []
			for i in ntex:
				var t := {}
				if _bool():
					t["source"] = _ref()
					t["clamp"] = _s.get_u32()
					_s.get_u32()  # filter
					t["uv_set"] = _s.get_u32()
					_skip(4)  # PS2 L, K
					_skip(2)
					if i == 5:
						_skip(24)  # bump map luma and matrix
				tex.append(t)
			r["textures"] = tex
		"NiSourceTexture":
			_object_net(r)
			if _s.get_u8() != 0:
				r["file"] = _str()
			else:
				_s.get_u8()
				r["pixel_data"] = _ref()
			_skip(12)  # pixel layout, mipmaps, alpha
			_s.get_u8()  # static
		"NiMaterialProperty":
			_object_net(r)
			_s.get_u16()
			r["ambient"] = _vec3()
			r["diffuse"] = _vec3()
			r["specular"] = _vec3()
			r["emissive"] = _vec3()
			r["glossiness"] = _s.get_float()
			r["alpha"] = _s.get_float()
		"NiAlphaProperty":
			_object_net(r)
			r["flags"] = _s.get_u16()
			r["threshold"] = _s.get_u8()
		"NiVertexColorProperty":
			_object_net(r)
			_s.get_u16()
			r["vertex_mode"] = _s.get_u32()
			r["lighting_mode"] = _s.get_u32()
		"NiZBufferProperty", "NiSpecularProperty", "NiWireframeProperty", "NiDitherProperty", "NiShadeProperty":
			_object_net(r)
			r["flags"] = _s.get_u16()
		"NiStencilProperty":
			_object_net(r)
			_s.get_u16()
			_skip(1 + 4 * 7)
		"NiStringExtraData":
			r["next"] = _ref()
			_s.get_u32()
			r["text"] = _str()
		"NiTextKeyExtraData":
			r["next"] = _ref()
			_s.get_u32()
			var nkeys := _s.get_u32()
			var keys := []
			for i in nkeys:
				keys.append([_s.get_float(), _str()])
			r["keys"] = keys
		"NiKeyframeController", "NiVisController", "NiAlphaController", "NiMaterialColorController":
			_time_controller(r)
			r["data"] = _ref()
		"NiUVController":
			_time_controller(r)
			_s.get_u16()
			r["data"] = _ref()
		"NiGeomMorpherController":
			_time_controller(r)
			r["data"] = _ref()
			_s.get_u8()
		"NiKeyframeData":
			var nrot := _s.get_u32()
			var rot := []
			r["rotation_type"] = 0
			if nrot > 0:
				var kind := _s.get_u32()
				r["rotation_type"] = kind
				if kind == 4:
					return false  # XYZ rotations: not used by people
				for i in nrot:
					var t := _s.get_float()
					var w := _s.get_float()
					var q := Quaternion(_s.get_float(), _s.get_float(), _s.get_float(), w)
					if kind == 3:
						_skip(12)
					rot.append([t, q])
			r["rotations"] = rot
			r["translations"] = _key_group(true)
			r["scales"] = _key_group(false)
		"NiFloatData":
			r["keys"] = _key_group(false)
		"NiVisData":
			var n := _s.get_u32()
			_skip(n * 5)
		"NiUVData":
			for i in 4:
				_key_group(false)
		"NiPosData":
			r["keys"] = _key_group(true)
		"NiColorData":
			var n := _s.get_u32()
			if n > 0:
				var kind := _s.get_u32()
				_skip(n * (4 + 16 + (12 if kind == 3 else 0) + (32 if kind == 2 else 0)))
		"NiMorphData":
			var nmorphs := _s.get_u32()
			var nverts := _s.get_u32()
			_s.get_u8()
			for i in nmorphs:
				_key_group(false, true)
				_skip(nverts * 12)
		"NiSequenceStreamHelper":
			_object_net(r)
		# Particles (flames, smoke, sparks): read so the rest of the file can be, drawn as a glow
		"NiAutoNormalParticles", "NiRotatingParticles", "NiParticles":
			_av_object(r)
			r["data"] = _ref()
			r["skin"] = _ref()
			r["particles"] = true
		"NiAutoNormalParticlesData", "NiRotatingParticlesData", "NiParticlesData":
			_geometry_data(r)
			_s.get_u16()  # particle count
			r["radius"] = _s.get_float()
			_s.get_u16()  # active
			if _bool():
				_skip((r["vertices"] as PackedVector3Array).size() * 4)
			if type == "NiRotatingParticlesData" and _bool():
				_skip((r["vertices"] as PackedVector3Array).size() * 16)
		"NiParticleSystemController", "NiBSPArrayController":
			_time_controller(r)
			_skip(24 + 12 + 16 + 4 + 4 + 4 + 1 + 4 + 4 + 4 + 2 + 12)
			r["emitter"] = _ref()
			_skip(2 + 4 + 2 + 4 + 4)
			var count := _s.get_u16()
			_s.get_u16()
			_skip(count * 40)
			_skip(4)
			r["modifier"] = _ref()
			r["collider"] = _ref()
			_s.get_u8()
		"NiGravity":
			_particle_modifier(r)
			_skip(4 + 4 + 4 + 12 + 12)
		"NiParticleGrowFade":
			_particle_modifier(r)
			_skip(8)
		"NiParticleColorModifier":
			_particle_modifier(r)
			r["data"] = _ref()
		"NiParticleRotation":
			_particle_modifier(r)
			_skip(1 + 12 + 4)
		"NiParticleBomb":
			_particle_modifier(r)
			_skip(16 + 4 + 12 + 12)
		"NiPlanarCollider":
			_particle_modifier(r)
			_skip(4 + 8 + 12 + 12 + 12 + 12 + 4)
		"NiSphericalCollider":
			_particle_modifier(r)
			_skip(4 + 4 + 12)
		"NiTextureEffect":
			_av_object(r)
			_skip(_s.get_u32() * 4)  # affected nodes
			_skip(36 + 12 + 16)
			r["texture"] = _ref()
			_skip(1 + 16 + 4 + 2)
		"NiCamera":
			# the first-person skeleton's camera: a node, then frustum (6), viewport (4), LOD adjust, the
			# scene it looks at and its screen polygons (none), which nothing here needs
			_av_object(r)
			_skip(24 + 16 + 4 + 4 + 4)
		"NiPointLight", "NiAmbientLight", "NiDirectionalLight", "NiSpotLight":
			_av_object(r)
			_skip(_s.get_u32() * 4)
			r["dimmer"] = _s.get_float()
			_skip(12)
			var c := _vec3()
			r["color"] = Color(c.x, c.y, c.z)
			_skip(12)
			if type == "NiPointLight" or type == "NiSpotLight":
				_skip(12)
			if type == "NiSpotLight":
				_skip(8)
		"NiVertWeightsExtraData":
			r["next"] = _ref()
			_skip(_s.get_u32())
		_:
			return false
	return true


func _object_net(r: Dictionary) -> void:
	r["name"] = _str()
	r["extra"] = _ref()
	r["controller"] = _ref()


func _av_object(r: Dictionary) -> void:
	_object_net(r)
	r["flags"] = _s.get_u16()
	r["origin"] = _vec3()
	r["basis"] = _mat3()
	r["scale"] = _s.get_float()
	_vec3()  # velocity
	r["properties"] = _refs()
	if _bool():
		_bounding_volume()


func _bounding_volume() -> void:
	var kind := _s.get_u32()
	match kind:
		0:
			_skip(16)
		1:
			_skip(12 + 36 + 12)
		2:
			_skip(12 + 12 + 8)
		3:
			_skip(12 + 12 + 12 + 8)
		4:
			var n := _s.get_u32()
			for i in n:
				_bounding_volume()
		5:
			_skip(16 + 12)


func _particle_modifier(r: Dictionary) -> void:
	r["next"] = _ref()
	r["controller"] = _ref()


func _time_controller(r: Dictionary) -> void:
	r["next"] = _ref()
	r["flags"] = _s.get_u16()
	r["frequency"] = _s.get_float()
	r["phase"] = _s.get_float()
	r["start"] = _s.get_float()
	r["stop"] = _s.get_float()
	r["target"] = _ref()


func _geometry_data(r: Dictionary) -> void:
	var n := _s.get_u16()
	var verts := PackedVector3Array()
	if _bool():
		verts.resize(n)
		for i in n:
			verts[i] = _vec3()
	r["vertices"] = verts
	var normals := PackedVector3Array()
	if _bool():
		normals.resize(n)
		for i in n:
			normals[i] = _vec3()
	r["normals"] = normals
	_vec3()  # centre
	_s.get_float()  # radius
	var colors := PackedColorArray()
	if _bool():
		colors.resize(n)
		for i in n:
			colors[i] = Color(_s.get_float(), _s.get_float(), _s.get_float(), _s.get_float())
	r["colors"] = colors
	var nuv := _s.get_u16() & 63
	var uvs := []
	if _bool():
		for k in nuv:
			var set := PackedVector2Array()
			set.resize(n)
			for i in n:
				set[i] = Vector2(_s.get_float(), _s.get_float())
			uvs.append(set)
	r["uvs"] = uvs


# Keys of floats or Vector3s: [[time, value], ...]. Morph keys store their kind even when empty.
func _key_group(vector: bool, always_kind: bool = false) -> Array:
	var out := []
	var n := _s.get_u32()
	if n == 0 and not always_kind:
		return out
	var kind := _s.get_u32()
	for i in n:
		var t := _s.get_float()
		var v = _vec3() if vector else _s.get_float()
		if kind == 2:
			_skip(24 if vector else 8)
		elif kind == 3:
			_skip(12)
		out.append([t, v])
	return out
