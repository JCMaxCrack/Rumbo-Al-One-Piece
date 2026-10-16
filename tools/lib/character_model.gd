class_name CharacterModel
extends Node3D
## Loads a character made by the team from assets/models/characters/<id>/:
##   - the base model (<id>.fbx or modelo.fbx, downloaded from Mixamo "With Skin")
##   - one file per animation, exactly as Mixamo names them ("Running.fbx", "Hit Reaction.fbx"...)
## It recognizes Mixamo names, retargets the animations to the model skeleton, loops the ones
## that must loop, removes root motion ("In Place") and fixes the scale (cm vs m).
## Game animation names: idle, walk, run, jump, fall, hurt, death, attack.

const DIR := "res://assets/models/characters/"
const EXTS := ["fbx", "glb", "gltf"]
const LOOPING := ["idle", "walk", "run", "fall"]
const FALLBACK := {"run": "walk", "walk": "idle", "fall": "jump", "jump": "idle", "hurt": "idle", "death": "hurt", "attack": "idle"}
## Keywords used to recognize Mixamo animation names (checked in this order).
const KEYWORDS := [
	["death", ["death", "dying", "die"]],
	["hurt", ["hurt", "hit", "reaction", "impact", "damage"]],
	["jump", ["jump"]],
	["fall", ["fall"]],
	["attack", ["punch", "jab", "attack", "slash", "strike", "kick"]],
	["run", ["run", "sprint"]],
	["walk", ["walk"]],
	["idle", ["idle", "breathing", "standing"]],
]

static var report: Dictionary = {}

var model_id := ""
var loaded := false
var height := 1.8
var anim_player: AnimationPlayer
var skeleton: Skeleton3D
var current := ""
var _anims: Dictionary = {}
var _meshes: Array = []
var _flash_t := 0.0
static var _flash_mat: StandardMaterial3D


func setup(id: String, target_height: float = 1.8) -> void:
	model_id = id
	var info := find_model(id)
	if info.is_empty():
		_build_placeholder(target_height)
	else:
		_load(info, target_height)
	_collect_meshes(self)
	play("idle", true)


# ------------------------------------------------------------------ finding files
static func find_model(id: String) -> Dictionary:
	var folder := DIR + id + "/"
	if not DirAccess.dir_exists_absolute(folder):
		for ext in EXTS:
			var single: String = DIR + id + "." + str(ext)
			if ResourceLoader.exists(single):
				return {"model": single, "anims": []}
		return {}
	var files := []
	for f in ResourceLoader.list_directory(folder):
		if EXTS.has(str(f).get_extension().to_lower()):
			files.append(str(f))
	if files.is_empty():
		return {}
	var model := ""
	var anims := []
	for f in files:
		var base := str(f).get_basename().to_lower()
		if base == id or base == "modelo" or base == "model" or base.contains("t-pose") or base.contains("tpose"):
			model = folder + str(f)
		else:
			anims.append(folder + str(f))
	if model == "":
		model = folder + str(files[0])
		anims.erase(model)
	return {"model": model, "anims": anims}


static func normalize_anim(raw: String) -> String:
	var n := raw.get_file().to_lower()
	for ext in EXTS:
		if n.ends_with("." + ext):
			n = n.get_basename()
	for junk in ["armature|", "mixamo.com", "mixamo_com", "|layer0", "layer0"]:
		n = n.replace(junk, "")
	for ch in [" ", "-", "|", "."]:
		n = n.replace(ch, "_")
	n = n.strip_edges().trim_prefix("_").trim_suffix("_")
	if n == "":
		return ""
	for pair in KEYWORDS:
		if n == pair[0]:
			return pair[0]
	for pair in KEYWORDS:
		for kw in pair[1]:
			if n.contains(kw):
				return pair[0]
	return ""


# ------------------------------------------------------------------ loading
func _load(info: Dictionary, target_height: float) -> void:
	var ps := load(str(info.model)) as PackedScene
	if ps == null:
		_build_placeholder(target_height)
		return
	var inst := ps.instantiate() as Node3D
	var lines := ["Model: " + str(info.model).get_file()]
	for extra in _all_of(inst, ["Camera3D", "Light3D"]):
		extra.get_parent().remove_child(extra)
		extra.free()
	add_child(inst)
	loaded = true
	var box := visual_bounds(inst)
	if box.size.y > 0.01:
		var k := target_height / box.size.y
		inst.scale = inst.scale * k
		inst.position.y = -box.position.y * k
		height = target_height
		lines.append("  Height %.2f -> %.2f m" % [box.size.y, target_height])
	skeleton = _find(inst, "Skeleton3D") as Skeleton3D
	anim_player = _find(inst, "AnimationPlayer") as AnimationPlayer
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		inst.add_child(anim_player)
	# animations stored inside the model file (only used if they have a recognizable name)
	for lib_name in anim_player.get_animation_library_list():
		var lib := anim_player.get_animation_library(lib_name)
		for an in lib.get_animation_list():
			var game_name := normalize_anim(str(an))
			if game_name != "" and not _anims.has(game_name):
				_anims[game_name] = str(an) if str(lib_name) == "" else "%s/%s" % [lib_name, an]
				_prepare(lib.get_animation(an), game_name)
	# one file per animation
	if skeleton and not info.anims.is_empty():
		var lib2 := AnimationLibrary.new()
		for path in info.anims:
			var game_name2 := normalize_anim(str(path))
			if game_name2 == "" or lib2.has_animation(game_name2):
				lines.append("  (ignored) " + str(path).get_file())
				continue
			var anim := _extract_animation(str(path))
			if anim == null:
				continue
			_retarget(anim)
			_prepare(anim, game_name2)
			lib2.add_animation(game_name2, anim)
			lines.append("  %s <- %s" % [game_name2, str(path).get_file()])
		anim_player.add_animation_library("team", lib2)
		for an2 in lib2.get_animation_list():
			_anims[str(an2)] = "team/" + str(an2)
	report[model_id] = "\n".join(lines)


func has_animation(game_name: String) -> bool:
	return _anims.has(game_name)


func available_animations() -> Array:
	return _anims.keys()


## Real model size. With a skeleton the bones are measured, because Blender + Mixamo files
## often have the mesh in meters and the skeleton in centimeters.
func visual_bounds(inst: Node3D) -> AABB:
	var skel := _find(inst, "Skeleton3D") as Skeleton3D
	if skel and skel.get_bone_count() > 3:
		var xf := Transform3D.IDENTITY
		var chain := []
		var n: Node = skel
		while n != inst and n != null:
			if n is Node3D:
				chain.push_front((n as Node3D).transform)
			n = n.get_parent()
		for t in chain:
			xf = xf * t
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var has_top := false
		for i in skel.get_bone_count():
			var p := (xf * skel.get_bone_global_rest(i)).origin
			lo = lo.min(p)
			hi = hi.max(p)
			if skel.get_bone_name(i).to_lower().contains("headtop"):
				has_top = true
		var h := (hi.y - lo.y) * (1.0 if has_top else 1.12)
		return AABB(Vector3(lo.x, lo.y - (hi.y - lo.y) * 0.03, lo.z), Vector3(hi.x - lo.x, h, hi.z - lo.z))
	return mesh_bounds(inst)


static func mesh_bounds(root: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack := [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var t: Transform3D = item[1]
		if node is Node3D and node != root:
			t = t * (node as Node3D).transform
		if node is MeshInstance3D and (node as MeshInstance3D).mesh:
			var b := t * (node as MeshInstance3D).mesh.get_aabb()
			out = b if first else out.merge(b)
			first = false
		for c in node.get_children():
			stack.append([c, t])
	return out


static func _extract_animation(path: String) -> Animation:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
	var result: Animation = null
	if ap:
		var best := -1.0
		for an in ap.get_animation_list():
			var a := ap.get_animation(an)
			if a.length > best:
				best = a.length
				result = a.duplicate(true)
	inst.free()
	return result


static func track_bone(p: NodePath) -> String:
	var sub := str(p.get_concatenated_subnames())
	if sub != "":
		return sub
	if p.get_name_count() > 0:
		return str(p.get_name(p.get_name_count() - 1))
	return ""


static func bone_key(b: String) -> String:
	var k := b.to_lower()
	if k.contains(":"):
		k = k.get_slice(":", k.get_slice_count(":") - 1)
	for junk in ["mixamorig", "_", ".", " "]:
		k = k.replace(junk, "")
	return k


func _hips_bone() -> int:
	if skeleton == null:
		return -1
	for i in skeleton.get_bone_count():
		if bone_key(skeleton.get_bone_name(i)) == "hips":
			return i
	return -1


## Points the tracks of an animation from another file to this model's skeleton.
func _retarget(anim: Animation) -> void:
	var root := anim_player.get_node(anim_player.root_node)
	var skel_path := str(root.get_path_to(skeleton))
	var bones := {}
	for i in skeleton.get_bone_count():
		bones[bone_key(skeleton.get_bone_name(i))] = skeleton.get_bone_name(i)
	for ti in range(anim.get_track_count() - 1, -1, -1):
		var key := bone_key(track_bone(anim.track_get_path(ti)))
		if key == "" or not bones.has(key):
			anim.remove_track(ti)
			continue
		anim.track_set_path(ti, NodePath(skel_path + ":" + str(bones[key])))
	# match units if the animation uses different ones (cm vs m)
	var hips := _hips_bone()
	if hips < 0:
		return
	var rest_y := skeleton.get_bone_rest(hips).origin.y
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) == Animation.TYPE_POSITION_3D and bone_key(track_bone(anim.track_get_path(ti))) == "hips" and anim.track_get_key_count(ti) > 0:
			var ky: float = (anim.track_get_key_value(ti, 0) as Vector3).y
			if absf(ky) > 0.001 and absf(rest_y) > 0.001:
				var ratio := rest_y / ky
				if ratio > 5.0 or ratio < 0.2:
					for tj in anim.get_track_count():
						if anim.track_get_type(tj) == Animation.TYPE_POSITION_3D:
							for k in anim.track_get_key_count(tj):
								anim.track_set_key_value(tj, k, (anim.track_get_key_value(tj, k) as Vector3) * ratio)
			break


## Loops, removes horizontal root motion ("In Place") and, for jumps, removes the
## vertical root motion (the physics already lifts the character; this avoids a double jump).
func _prepare(anim: Animation, game_name: String) -> void:
	if LOOPING.has(game_name):
		anim.loop_mode = Animation.LOOP_LINEAR
	var hips := _hips_bone()
	var rest_y := skeleton.get_bone_rest(hips).origin.y if hips >= 0 else INF
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		if bone_key(track_bone(anim.track_get_path(ti))) != "hips":
			continue
		var n := anim.track_get_key_count(ti)
		if n < 2:
			continue
		var first: Vector3 = anim.track_get_key_value(ti, 0)
		for k in n:
			var v: Vector3 = anim.track_get_key_value(ti, k)
			var y := v.y
			if (game_name == "jump" or game_name == "fall") and y > rest_y:
				y = rest_y
			anim.track_set_key_value(ti, k, Vector3(first.x, y, first.z))


# ------------------------------------------------------------------ playback
## Plays a game animation. from_time skips the beginning (used to sync the jump).
func play(anim: String, restart: bool = false, speed: float = 1.0, from_time: float = 0.0) -> void:
	if anim == current and not restart:
		return
	current = anim
	if not loaded or anim_player == null:
		return
	var a := anim
	var guard := 0
	while not _anims.has(a) and guard < 6:
		a = FALLBACK.get(a, "idle")
		guard += 1
	if not _anims.has(a):
		return
	anim_player.play(_anims[a], 0.15, speed)
	if from_time > 0.0:
		anim_player.seek(from_time, true)


func flash() -> void:
	if _flash_mat == null:
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.albedo_color = Color(1, 1, 1, 0.55)
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for m in _meshes:
		(m as MeshInstance3D).material_overlay = _flash_mat
	_flash_t = 0.12


func _process(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			for m in _meshes:
				if is_instance_valid(m):
					(m as MeshInstance3D).material_overlay = null


# ------------------------------------------------------------------ helpers
func _collect_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_meshes.append(c)
		_collect_meshes(c)


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


static func _all_of(n: Node, classes: Array) -> Array:
	var out := []
	for c in n.get_children():
		for cls in classes:
			if c.is_class(cls):
				out.append(c)
				break
		out.append_array(_all_of(c, classes))
	return out


## Simple capsule used when the team's model is missing (so the game never breaks).
func _build_placeholder(target_height: float) -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.35
	cap.height = target_height
	mi.mesh = cap
	mi.position.y = target_height / 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.3, 0.3)
	mi.material_override = m
	add_child(mi)
	height = target_height
	report[model_id] = "No model found for '%s': using a placeholder capsule." % model_id
