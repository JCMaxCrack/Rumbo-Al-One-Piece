extends Node
## SaveManager (autoload, see project.godot): the save "database" of the game.
##
## It is a small NON-RELATIONAL (document) database stored in ONE JSON file:
##   user://saves/partidas.json
##   {
##     "database": "rumbo_al_one_piece",
##     "version": 1,
##     "slots": {
##       "1": { "data": { ...progress of that game... }, "signature": "9f3a..." },
##       "2": null,                      <- empty slot
##       "3": { ... }, "4": { ... }
##     }
##   }
## Every slot is one document (a JSON object, no tables or relations). The game can create a new
## game in a slot, overwrite (replace) a slot, read it and delete it. There are SLOT_COUNT slots.
##
## Security (so a player can not edit the file to skip the game):
##   1. Every document is signed with HMAC-SHA256. The key is built inside the game (it is not
##      written in the file) and mixed with the id of the device, so a save copied from another
##      computer/phone is not valid either. The slot number is part of what is signed, so a
##      document can not be moved to another slot.
##   2. When a slot is read, the signature is checked and every value is validated (types,
##      ranges, meat and checkpoint names that exist, coherence between values). If anything
##      fails, the slot is marked as TAMPERED: it is shown as "modificado" and can not be loaded.
##   3. Every number is saved as a whole number, so the signature does not depend on how a text
##      editor writes decimals: only a real change of a value breaks it.
##   4. The file is written to a temporary file first and then renamed, so a crash while saving
##      can not leave half a file.
## Note: like any game that saves on the player's device, someone who decompiles the game could
## find how the key is made; the signature stops editing the JSON by hand (the usual cheat).

enum SlotStatus { EMPTY, VALID, TAMPERED }

const SLOT_COUNT := 4
const FILE_PATH := "user://saves/partidas.json"
## 2 = Zoro added ("zoro": recruited). Saves of version 1 are still valid (Zoro not recruited).
const VERSION := 2
## Ids of the Checkpoint nodes of scenes/game.tscn (anything else in a save is rejected).
const CHECKPOINT_IDS := ["playa_sur", "entrada_crater", "muelle", "peninsula_oeste", "bosque_noroeste", "costa_este"]
const FIRST_CHECKPOINT := "playa_sur"
const MEAT_COUNT := 10
const PLAYER_MAX_HEALTH := 100.0
const BOSS_MAX_HEALTH := 150.0

## Slot used by the game that is being played (0 = none, nothing is saved).
var current_slot := 0
## Progress to apply when scenes/game.tscn starts (filled by load_game()).
var _pending: Dictionary = {}


# ------------------------------------------------------------------ public API
## Every slot: [{slot, status, data}] (data is empty unless the slot is VALID).
func list_slots() -> Array:
	var db := _read_db()
	var out := []
	for i in range(1, SLOT_COUNT + 1):
		out.append(_check_slot(db, i))
	return out


func read_slot(slot: int) -> Dictionary:
	return _check_slot(_read_db(), slot)


## Creates or replaces the document of a slot. Returns false if it could not be written.
func write_slot(slot: int, data: Dictionary) -> bool:
	if slot < 1 or slot > SLOT_COUNT:
		return false
	var doc := data.duplicate(true)
	doc["version"] = VERSION
	doc["slot"] = slot
	doc["saved_at"] = int(Time.get_unix_time_from_system())
	doc = _normalize(doc)
	if not _valid_data(doc, slot):
		push_error("SaveManager: refusing to save invalid data %s" % doc)
		return false
	var db := _read_db()
	db["slots"][str(slot)] = {"data": doc, "signature": _sign(slot, doc)}
	return _write_db(db)


func delete_slot(slot: int) -> bool:
	var db := _read_db()
	db["slots"][str(slot)] = null
	if current_slot == slot:
		current_slot = 0
	return _write_db(db)


## "Nueva partida": the game starts from zero in this slot (game_world.gd saves it at once).
func start_new_game(slot: int) -> void:
	current_slot = slot
	_pending = {}


## "Cargar": only valid slots of games that are not finished can be loaded.
func load_game(slot: int) -> bool:
	var info := read_slot(slot)
	if info.status != SlotStatus.VALID or bool(info.data.get("completed", false)):
		return false
	current_slot = slot
	_pending = info.data
	return true


## Called by game_world.gd when the level starts: the progress to restore (or {} for a new game).
func take_pending() -> Dictionary:
	var d := _pending
	_pending = {}
	return d


# ------------------------------------------------------------------ file
func _empty_db() -> Dictionary:
	var slots := {}
	for i in range(1, SLOT_COUNT + 1):
		slots[str(i)] = null
	return {"database": "rumbo_al_one_piece", "version": VERSION, "slots": slots}


func _read_db() -> Dictionary:
	if not FileAccess.file_exists(FILE_PATH):
		return _empty_db()
	var text := FileAccess.get_file_as_string(FILE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("slots")) != TYPE_DICTIONARY:
		# the file is not our JSON any more: every slot is shown as modified
		var broken := _empty_db()
		for i in range(1, SLOT_COUNT + 1):
			broken["slots"][str(i)] = {"data": {}, "signature": ""}
		return broken
	var db := _empty_db()
	for i in range(1, SLOT_COUNT + 1):
		db["slots"][str(i)] = parsed["slots"].get(str(i))
	return db


func _write_db(db: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(FILE_PATH.get_base_dir())
	var tmp := FILE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("SaveManager: can not write %s (%d)" % [tmp, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(_ints(db), "\t", true))
	f.close()
	return DirAccess.rename_absolute(tmp, FILE_PATH) == OK


## Writes 120 instead of 120.0 in the file (only to make it easier to read).
func _ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			return int(v) if v == floorf(v) else v
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _ints(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_ints(x))
			return a
	return v


# ------------------------------------------------------------------ security
func _check_slot(db: Dictionary, slot: int) -> Dictionary:
	var doc: Variant = db["slots"].get(str(slot))
	if doc == null:
		return {"slot": slot, "status": SlotStatus.EMPTY, "data": {}}
	var bad := {"slot": slot, "status": SlotStatus.TAMPERED, "data": {}}
	if typeof(doc) != TYPE_DICTIONARY or typeof(doc.get("data")) != TYPE_DICTIONARY or typeof(doc.get("signature")) != TYPE_STRING:
		return bad
	var data: Dictionary = doc["data"]
	if doc["signature"] != _sign(slot, data) or not _valid_data(data, slot):
		return bad
	return {"slot": slot, "status": SlotStatus.VALID, "data": data}


## Same values as they will be after writing and reading the JSON (ints become floats, etc.).
func _normalize(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d, "", true, true))


func _key() -> PackedByteArray:
	# the key is not stored anywhere: it is built from pieces and the id of this device
	var pieces := PackedStringArray(["Gomu", "G0mu", "n0", "Mi", "R4mb0", "0n3", "P13c3", "%d" % (SLOT_COUNT * 7919)])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("-".join(pieces) + "|" + OS.get_unique_id()).to_utf8_buffer())
	return ctx.finish()


func _sign(slot: int, data: Dictionary) -> String:
	# each document is signed with its own version (old saves keep their valid signature)
	var message := "slot:%d|v%d|%s" % [slot, int(data.get("version", VERSION)), JSON.stringify(data, "", true, true)]
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _key(), message.to_utf8_buffer()).hex_encode()


## Only whole numbers are accepted (see point 3 above).
func _is_number(v: Variant) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and float(v) == floorf(float(v))


func _names_ok(list: Variant, valid: Array) -> bool:
	if typeof(list) != TYPE_ARRAY:
		return false
	var seen := {}
	for v in list:
		if typeof(v) != TYPE_STRING or not valid.has(v) or seen.has(v):
			return false
		seen[v] = true
	return true


## Validates every value of a save (even a correctly signed one must make sense).
func _valid_data(d: Dictionary, slot: int) -> bool:
	var meat_names := []
	for i in range(1, MEAT_COUNT + 1):
		meat_names.append("Meat%d" % i)
	var keys := ["version", "slot", "saved_at", "play_time", "health", "mission", "completed", "checkpoint", "checkpoints", "meat", "boss_health", "boss_defeated"]
	if d.get("version") is float and int(d.version) >= 2:
		keys.append("zoro")
	for k in keys:
		if not d.has(k):
			return false
	if d.size() != keys.size():
		return false
	if not _is_number(d.version) or int(d.version) < 1 or int(d.version) > VERSION or not _is_number(d.slot) or int(d.slot) != slot:
		return false
	if not _is_number(d.saved_at) or not _is_number(d.play_time) or float(d.play_time) < 0.0 or float(d.play_time) > 1.0e7:
		return false
	if not _is_number(d.health) or float(d.health) <= 0.0 or float(d.health) > PLAYER_MAX_HEALTH:
		return false
	if not _is_number(d.mission) or not [0, 1].has(int(d.mission)):
		return false
	if typeof(d.completed) != TYPE_BOOL or typeof(d.boss_defeated) != TYPE_BOOL:
		return false
	if typeof(d.checkpoint) != TYPE_STRING or not CHECKPOINT_IDS.has(d.checkpoint):
		return false
	if not _names_ok(d.checkpoints, CHECKPOINT_IDS) or not d.checkpoints.has(d.checkpoint) or not d.checkpoints.has(FIRST_CHECKPOINT):
		return false
	if not _names_ok(d.meat, meat_names):
		return false
	if not _is_number(d.boss_health) or float(d.boss_health) < 0.0 or float(d.boss_health) > BOSS_MAX_HEALTH:
		return false
	if d.boss_defeated != (float(d.boss_health) <= 0.0):
		return false
	# a finished game must really have everything done
	if d.has("zoro") and typeof(d.zoro) != TYPE_BOOL:
		return false
	if d.completed and (int(d.mission) != 1 or not d.boss_defeated or d.meat.size() != MEAT_COUNT or not d.get("zoro", true)):
		return false
	return true
