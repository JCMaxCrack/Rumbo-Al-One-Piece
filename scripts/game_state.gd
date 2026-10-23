extends Node
## GameState (autoload, see project.godot): everything Luffy carries from one island to another.
##   - the voyage: island being played, islands that can be visited and islands completed;
##   - the crew (Zoro, Usopp, Nami) that already joined;
##   - the inventory: INVENTORY_SIZE slots, each with one kind of item (meat and tangerines stack);
##   - experience: defeating enemies gives XP; every full bar is a level and a skill point;
##   - the skills (new attacks) learned in the skill shop and the one that is equipped.
## The islands keep their own progress (mission, checkpoints, meat taken...) in `islands`.
## SaveManager writes all of it in the save slots (see collect() / restore()).

signal inventory_changed
signal xp_changed(level: int, xp: int, needed: int)
signal leveled_up(level: int)
signal skills_changed

const ISLANDS := ["isla_inicio", "villa_syrup", "whisky_peak"]
const ISLAND_SCENES := {
	"isla_inicio": "res://scenes/game.tscn",
	"villa_syrup": "res://scenes/islands/villa_syrup.tscn",
	"whisky_peak": "res://scenes/islands/whisky_peak.tscn",
}
const ISLAND_NAMES := {"isla_inicio": "Isla del Payaso", "villa_syrup": "Villa Syrup", "whisky_peak": "Whisky Peak"}
const CREW := ["zoro", "usopp", "nami"]

const INVENTORY_SIZE := 4
## id -> name, health it gives back when eaten (0 = it can not be eaten), how many fit in a slot.
const ITEMS := {
	"meat": {"name": "Carne", "heal": 35.0, "stack": 9, "color": Color(0.85, 0.42, 0.2)},
	"orange": {"name": "Mandarina", "heal": 15.0, "stack": 9, "color": Color(1.0, 0.6, 0.1)},
	"key": {"name": "Llave de la mansión", "heal": 0.0, "stack": 1, "color": Color(0.95, 0.8, 0.3)},
}

## Skills of Luffy. "island": index of the island where they appear in the shop (2 per island).
const SKILLS := {
	"muchi": {"name": "Gomu Gomu no Muchi", "island": 0, "cost": 1, "cooldown": 4.0, "damage": 22.0,
		"text": "Patada giratoria: golpea a todos los enemigos a tu alrededor."},
	"bazooka": {"name": "Gomu Gomu no Bazooka", "island": 0, "cost": 2, "cooldown": 6.0, "damage": 40.0,
		"text": "Empujón con las dos palmas: mucho daño y lanza lejos al enemigo."},
	"gatling": {"name": "Gomu Gomu no Gatling", "island": 1, "cost": 2, "cooldown": 7.0, "damage": 9.0,
		"text": "Lluvia de puñetazos hacia delante: muchos golpes seguidos."},
	"fusen": {"name": "Gomu Gomu no Fusen", "island": 1, "cost": 1, "cooldown": 10.0, "damage": 10.0,
		"text": "Te inflas como un globo: nada te hace daño y empujas a los enemigos."},
	"ono": {"name": "Gomu Gomu no Ono", "island": 2, "cost": 2, "cooldown": 8.0, "damage": 48.0,
		"text": "Hachazo con el talón: una onda de choque delante de ti."},
	"storm": {"name": "Gomu Gomu no Storm", "island": 2, "cost": 3, "cooldown": 14.0, "damage": 14.0,
		"text": "Tormenta de golpes en todas las direcciones."},
}
const MAX_LEVEL := 30

var island := "isla_inicio"
var unlocked: Array = ["isla_inicio"]
var completed: Array = []
var crew: Array = []
## INVENTORY_SIZE entries: {} (empty) or {"id": "meat", "count": 3}.
var inventory: Array = []
var selected_slot := 0
var level := 1
var xp := 0
var skill_points := 0
var skills: Array = []
var equipped := ""
## island id -> progress of that island (written and read by the island scripts).
var islands := {}
var play_time := 0.0
## Luffy's health when he left the last island (0 = full).
var health := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()


## A new game.
func reset() -> void:
	island = "isla_inicio"
	unlocked = ["isla_inicio"]
	completed = []
	crew = []
	inventory = []
	for i in INVENTORY_SIZE:
		inventory.append({})
	selected_slot = 0
	level = 1
	xp = 0
	skill_points = 0
	skills = []
	equipped = ""
	islands = {}
	play_time = 0.0
	health = 0.0


## Local co-op: Zoro is player 2 from the first island.
func coop_zoro() -> bool:
	return GameSession.coop


func island_index(id: String = "") -> int:
	return ISLANDS.find(island if id == "" else id)


func next_island(id: String = "") -> String:
	var i := island_index(id) + 1
	return ISLANDS[i] if i > 0 and i < ISLANDS.size() else ""


func has_crew(member: String) -> bool:
	return crew.has(member)


func add_crew(member: String) -> void:
	if not crew.has(member):
		crew.append(member)


## The mission of the island is done: the next island can be visited.
func complete_island(id: String) -> void:
	if not completed.has(id):
		completed.append(id)
	var nxt := next_island(id)
	if nxt != "" and not unlocked.has(nxt):
		unlocked.append(nxt)


func is_last_island(id: String) -> bool:
	return island_index(id) == ISLANDS.size() - 1


# ------------------------------------------------------------------ inventory
func item_name(id: String) -> String:
	return tr(ITEMS[id].name) if ITEMS.has(id) else ""


func count_of(id: String) -> int:
	var n := 0
	for s in inventory:
		if s.get("id", "") == id:
			n += int(s.count)
	return n


## Puts an item in the inventory. Returns false if there is no room for it.
func add_item(id: String, amount: int = 1) -> bool:
	if not ITEMS.has(id) or not can_add(id, amount):
		return false
	var left := amount
	var stack: int = ITEMS[id].stack
	for s in inventory:
		if left > 0 and s.get("id", "") == id and int(s.count) < stack:
			var put := mini(left, stack - int(s.count))
			s.count = int(s.count) + put
			left -= put
	for i in inventory.size():
		if left > 0 and (inventory[i] as Dictionary).is_empty():
			var put := mini(left, stack)
			inventory[i] = {"id": id, "count": put}
			left -= put
	inventory_changed.emit()
	return true


func can_add(id: String, amount: int = 1) -> bool:
	var stack: int = ITEMS[id].stack
	var room := 0
	for s in inventory:
		if (s as Dictionary).is_empty():
			room += stack
		elif s.id == id:
			room += stack - int(s.count)
	return room >= amount


## Takes items out of the inventory (eating, giving them away). Returns false if there are not enough.
func remove_item(id: String, amount: int = 1) -> bool:
	if count_of(id) < amount:
		return false
	var left := amount
	for i in range(inventory.size() - 1, -1, -1):
		var s: Dictionary = inventory[i]
		if left > 0 and s.get("id", "") == id:
			var take := mini(left, int(s.count))
			s.count = int(s.count) - take
			left -= take
			if int(s.count) <= 0:
				inventory[i] = {}
	inventory_changed.emit()
	return true


func selected_item() -> String:
	return str((inventory[selected_slot] as Dictionary).get("id", ""))


func select_slot(i: int) -> void:
	selected_slot = posmod(i, INVENTORY_SIZE)
	inventory_changed.emit()


## Next slot with something in it (or simply the next one if they are all empty).
func select_next(dir: int = 1) -> void:
	for k in range(1, INVENTORY_SIZE + 1):
		var i := posmod(selected_slot + k * dir, INVENTORY_SIZE)
		if not (inventory[i] as Dictionary).is_empty():
			select_slot(i)
			return
	select_slot(selected_slot + dir)


# ------------------------------------------------------------------ experience
func xp_needed(lv: int = -1) -> int:
	var l := level if lv < 0 else lv
	return 40 + 30 * (l - 1)


## Experience for defeating an enemy (or finishing a mission).
func add_xp(amount: int) -> void:
	if amount <= 0 or level >= MAX_LEVEL:
		return
	xp += amount
	var ups := 0
	while xp >= xp_needed() and level < MAX_LEVEL:
		xp -= xp_needed()
		level += 1
		skill_points += 1
		ups += 1
	if level >= MAX_LEVEL:
		xp = 0
	xp_changed.emit(level, xp, xp_needed())
	if ups > 0:
		leveled_up.emit(level)


# ------------------------------------------------------------------ skills
## Skills that appear in the shop: 2 more for every island that was reached.
func shop_skills() -> Array:
	var out := []
	var reached := 0
	for id in unlocked:
		reached = maxi(reached, island_index(id))
	reached = maxi(reached, island_index())
	for id in SKILLS:
		if int(SKILLS[id].island) <= reached:
			out.append(id)
	return out


func can_learn(id: String) -> bool:
	return SKILLS.has(id) and not skills.has(id) and shop_skills().has(id) and skill_points >= int(SKILLS[id].cost)


func learn(id: String) -> bool:
	if not can_learn(id):
		return false
	skill_points -= int(SKILLS[id].cost)
	skills.append(id)
	if equipped == "":
		equipped = id
	skills_changed.emit()
	return true


func equip(id: String) -> void:
	if skills.has(id):
		equipped = id
		skills_changed.emit()


func equip_next() -> void:
	if skills.is_empty():
		return
	var i := skills.find(equipped)
	equipped = skills[(i + 1) % skills.size()]
	skills_changed.emit()


func skill_name(id: String) -> String:
	return tr(SKILLS[id].name) if SKILLS.has(id) else ""


# ------------------------------------------------------------------ saving
## The part of a save document that does not belong to one island.
func collect() -> Dictionary:
	var inv := []
	for s in inventory:
		inv.append([str((s as Dictionary).get("id", "")), int((s as Dictionary).get("count", 0))])
	return {
		"level": level, "xp": xp, "points": skill_points, "skills": skills.duplicate(), "equipped": equipped,
		"inventory": inv, "crew": crew.duplicate(), "unlocked": unlocked.duplicate(), "done": completed.duplicate(),
	}


## Restores what collect() gave (the values were already validated by SaveManager).
func restore(d: Dictionary, island_id: String, island_data: Dictionary, time: float) -> void:
	reset()
	island = island_id
	level = int(d.level)
	xp = int(d.xp)
	skill_points = int(d.points)
	skills = (d.skills as Array).duplicate()
	equipped = str(d.equipped)
	crew = (d.crew as Array).duplicate()
	unlocked = (d.unlocked as Array).duplicate()
	completed = (d.done as Array).duplicate()
	for i in INVENTORY_SIZE:
		var e: Array = d.inventory[i]
		inventory[i] = {} if str(e[0]) == "" else {"id": str(e[0]), "count": int(e[1])}
	islands = island_data.duplicate(true)
	play_time = time


## Scene of the island being played.
func island_scene(id: String = "") -> String:
	return ISLAND_SCENES[island if id == "" else id]
