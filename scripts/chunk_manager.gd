class_name ChunkManager
extends Node3D
## Streams the island by chunks (like Minecraft, but with normal 3D models instead of blocks).
##
## The island (IslandBuilder size: 440 x 440 m) is divided in a grid of chunks of chunk_size
## meters. Each chunk is a scene in assets/chunks/chunk_XX_ZZ.scn with:
##   - one MultiMeshInstance3D per kind of object (Trees, Palms, Rocks, Bushes, Grass): every tree
##     of the chunk is drawn in one draw call per material, and far away chunks are not drawn;
##   - Colliders (StaticBody3D) with the collision shapes of those trees and rocks.
## Only the chunks closer than load_radius to the player exist in the scene. They are loaded in
## background threads (ResourceLoader.load_threaded_request) and added a few per frame, so moving
## around does not cause hitches; chunks farther than load_radius + unload_margin are freed.
## When the player jumps far (a loaded save, a respawn), the chunks around him are loaded at once.
##
## The terrain is not streamed (the island must always be visible): it is split in tiles with two
## levels of detail (TerrainTiles, see apply_quality()), and its collision is one height map.

@export var target: Node3D
## Node with the terrain tiles: children "Tile_XX_ZZ" (near, detailed) and "Tile_XX_ZZ_Far".
@export var terrain_tiles: Node3D
@export var chunk_size := 40.0
@export var grid_size := 11
@export var chunk_dir := "res://assets/chunks/"
@export var load_radius := 160.0
@export var unload_margin := 25.0
## Chunks added to the scene per frame (the loading itself happens in threads).
@export var max_instances_per_frame := 1
@export var update_interval := 0.2

## Distance at which each kind of object stops being drawn (set by GraphicsSettings).
var view_ranges := {"Grass": 45.0, "Bushes": 100.0, "Rocks": 140.0, "Trees": 160.0, "Palms": 160.0}
var grass_density := 1.0
var vegetation_shadows := true
var terrain_detail_range := 100.0

var _loaded := {}      # Vector2i -> Node3D
var _requested := {}   # Vector2i -> path being loaded in a thread
var _waiting: Array = []  # [Vector2i, PackedScene] loaded, waiting to be added
var _exists := {}      # Vector2i -> bool (is there a chunk file for this cell)
var _timer := 0.0
var _last_pos := Vector3.INF


func _ready() -> void:
	for x in grid_size:
		for z in grid_size:
			var c := Vector2i(x, z)
			_exists[c] = ResourceLoader.exists(chunk_path(c))
	if target:
		load_around(target.global_position)


func chunk_path(c: Vector2i) -> String:
	return chunk_dir + "chunk_%02d_%02d.scn" % [c.x, c.y]


func loaded_count() -> int:
	return _loaded.size()


func is_loaded(c: Vector2i) -> bool:
	return _loaded.has(c)


func coord_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(p.x / chunk_size), 0, grid_size - 1), clampi(int(p.z / chunk_size), 0, grid_size - 1))


## Horizontal distance from a point to the square of a chunk (0 if it is inside).
func distance_to_chunk(p: Vector3, c: Vector2i) -> float:
	var lo := Vector2(c.x * chunk_size, c.y * chunk_size)
	var q := Vector2(clampf(p.x, lo.x, lo.x + chunk_size), clampf(p.z, lo.y, lo.y + chunk_size))
	return q.distance_to(Vector2(p.x, p.z))


## Loads (in this frame, without threads) the chunks next to a point, then the rest in threads.
func load_around(p: Vector3) -> void:
	for c in _exists:
		if _exists[c] and not _loaded.has(c) and distance_to_chunk(p, c) <= chunk_size:
			_add_chunk(c, load(chunk_path(c)) as PackedScene)
	_last_pos = p
	_update(p)


func _process(delta: float) -> void:
	if target == null:
		return
	_collect_threads()
	var added := 0
	while added < max_instances_per_frame and not _waiting.is_empty():
		var item: Array = _waiting.pop_front()
		if not _loaded.has(item[0]) and distance_to_chunk(target.global_position, item[0]) <= load_radius + unload_margin:
			_add_chunk(item[0], item[1])
			added += 1
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = update_interval
	var p := target.global_position
	if _last_pos != Vector3.INF and p.distance_to(_last_pos) > chunk_size * 1.5:
		load_around(p)  # teleport: the player must never stand where nothing is loaded
	_last_pos = p
	_update(p)


func _update(p: Vector3) -> void:
	for c in _exists:
		if not _exists[c]:
			continue
		var d := distance_to_chunk(p, c)
		if d <= load_radius:
			if not _loaded.has(c) and not _requested.has(c) and not _is_waiting(c):
				var path := chunk_path(c)
				if ResourceLoader.load_threaded_request(path, "PackedScene", true) == OK:
					_requested[c] = path
		elif d > load_radius + unload_margin and _loaded.has(c):
			_loaded[c].queue_free()
			_loaded.erase(c)


func _is_waiting(c: Vector2i) -> bool:
	for item in _waiting:
		if item[0] == c:
			return true
	return false


func _collect_threads() -> void:
	for c in _requested.keys():
		var path: String = _requested[c]
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				_requested.erase(c)
				var ps := ResourceLoader.load_threaded_get(path) as PackedScene
				if ps:
					_waiting.append([c, ps])
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_requested.erase(c)
				push_warning("ChunkManager: could not load " + path)


func _add_chunk(c: Vector2i, ps: PackedScene) -> void:
	if ps == null:
		return
	var chunk := ps.instantiate() as Node3D
	add_child(chunk)
	_loaded[c] = chunk
	_setup_chunk(chunk)


## Quality of one chunk: how far each kind of object is drawn, grass density and shadows.
func _setup_chunk(chunk: Node3D) -> void:
	for child in chunk.get_children():
		var mmi := child as MultiMeshInstance3D
		if mmi == null:
			continue
		var kind := str(mmi.name)
		var r: float = view_ranges.get(kind, load_radius)
		mmi.visibility_range_end = r
		mmi.visibility_range_end_margin = r * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if kind == "Grass":
			mmi.multimesh.visible_instance_count = int(mmi.multimesh.instance_count * grass_density)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif kind == "Bushes":
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if vegetation_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Called by GraphicsSettings with the values of the preset.
func apply_quality(s: Dictionary) -> void:
	load_radius = s.chunk_radius
	grass_density = s.grass_density
	vegetation_shadows = s.vegetation_shadows and s.shadows
	terrain_detail_range = s.terrain_detail_range
	view_ranges = {"Grass": s.grass_range, "Bushes": s.bush_range, "Rocks": s.rock_range, "Trees": s.chunk_radius, "Palms": s.chunk_radius}
	for c in _loaded:
		_setup_chunk(_loaded[c])
	_setup_terrain()
	if target:
		_update(target.global_position)


## Terrain LOD: the detailed tile is used near the camera, the light one farther away.
func _setup_terrain() -> void:
	if terrain_tiles == null:
		return
	for tile in terrain_tiles.get_children():
		var gi := tile as GeometryInstance3D
		if gi == null:
			continue
		if str(tile.name).ends_with("_Far"):
			gi.visibility_range_begin = terrain_detail_range
			gi.visibility_range_begin_margin = 0.0
		else:
			gi.visibility_range_end = terrain_detail_range
			gi.visibility_range_end_margin = 0.0  # same switch distance: never a hole
