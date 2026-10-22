extends Node
## GameSession (autoload, see project.godot): how the game is being played.
##
##   coop = false: single player. Luffy uses keyboard + mouse and ANY gamepad; Zoro is a character
##                 of the island that joins the crew in Koby's mission (then he follows Luffy).
##   coop = true:  local co-op on one screen split in two. Player 1 (Luffy) uses keyboard + mouse
##                 (and a second gamepad, if there is one); player 2 (Zoro) uses the first gamepad.
##
## The input actions of player 2 are made here from the ones of player 1 (project.godot): every
## gamepad event of "jump" becomes an event of "p2_jump" for player 2's device, and so on.

const ACTIONS := ["move_left", "move_right", "move_forward", "move_back", "look_left", "look_right", "look_up", "look_down",
	"sprint", "jump", "attack", "interact", "pause", "map"]

var coop := false
## Gamepad of player 2 in co-op (-1 = none).
var p2_device := -1
var _original := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in ACTIONS:
		if InputMap.has_action(a):
			_original[a] = InputMap.action_get_events(a).duplicate()
	setup_input(false)
	Input.joy_connection_changed.connect(func(_d, _c): setup_input(coop))


func gamepads() -> Array[int]:
	return Input.get_connected_joypads()


## Co-op needs a gamepad for player 2.
func can_play_coop() -> bool:
	return not gamepads().is_empty()


func start(is_coop: bool) -> void:
	coop = is_coop and can_play_coop()
	setup_input(coop)


## Builds the input map for single player or co-op.
func setup_input(is_coop: bool) -> void:
	var pads := gamepads()
	p2_device = pads[0] if is_coop and not pads.is_empty() else -1
	# player 1: in single player any gamepad (device -1); in co-op only the second gamepad
	var p1_device := -1
	if is_coop:
		p1_device = pads[1] if pads.size() > 1 else 99
	for a in _original:
		InputMap.action_erase_events(a)
		var p2: String = "p2_" + a
		if InputMap.has_action(p2):
			InputMap.erase_action(p2)
		if is_coop:
			InputMap.add_action(p2, 0.25)
		for e in _original[a]:
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				var mine := (e as InputEvent).duplicate() as InputEvent
				mine.device = p1_device
				InputMap.action_add_event(a, mine)
				if is_coop:
					var other := (e as InputEvent).duplicate() as InputEvent
					other.device = p2_device
					InputMap.action_add_event(p2, other)
			else:
				InputMap.action_add_event(a, e)
