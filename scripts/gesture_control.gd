extends Node
## GestureControl (autoload, see project.godot): play with the hand in front of the PC camera.
##
## The hand tracker (gesture/hand_tracker.py: OpenCV + MediaPipe) is a separate program. The
## export includes it already built (gesture_bin/hand_tracker_<os>.zip, made by
## gesture/build_tracker.py): the first time it is turned on it is unzipped into the data folder
## of the game (user://hand_tracker/) and started from there. In the editor, without that zip, the
## Python script is started directly (Python with mediapipe and opencv-python must be installed).
##
## The tracker sends the gesture by UDP to 127.0.0.1:PORT (or any free port, if that one is taken)
## about 30 times per second, from a free port of its own; the game answers to that port: "ping"
## every second (without pings it closes itself) and "quit" when it closes. So an old tracker
## that is still open, or another program, never blocks a port. Gestures become the normal input actions of player 1, so they work like the
## keyboard or the gamepad everywhere:
##   open palm        -> walk forward (sail with the ship); hand high in the picture -> run
##   hand left/right  -> turn the camera (the helm while sailing)
##   fist             -> punch (again and again while the fist is closed)
##   victory (2 fingers) -> jump
##   index finger     -> talk / use ("interact")
##   thumb up         -> skill
## Turned on and off in Options (Preferences.gesture_control).

signal status_changed(text: String)

enum Status { OFF, STARTING, READY, NO_CAMERA, UNAVAILABLE, NOT_RESPONDING, FAILED }

const STATUS_TEXT := {
	Status.OFF: "Gesture control: off",
	Status.STARTING: "Gesture control: starting the camera...",
	Status.READY: "Gesture control: ready",
	Status.NO_CAMERA: "Gesture control: no camera found",
	Status.UNAVAILABLE: "Gesture control is not included in this version of the game",
	Status.NOT_RESPONDING: "Gesture control: the hand tracker does not respond",
	Status.FAILED: "Gesture control: the hand tracker failed (%s)",
}
const GESTURE_TEXT := {
	"none": "No hand", "open": "Open palm: walk", "fist": "Fist: punch", "victory": "Two fingers: jump",
	"point": "Index finger: talk", "thumbs_up": "Thumb up: skill", "other": "Unknown gesture",
}
## Port where the game listens (any free one if it is taken).
const PORT := 4242
const INSTALL_DIR := "user://hand_tracker"
## Seconds without news from the tracker before its input is let go / it counts as not responding.
const SILENCE := 0.6
const START_TIMEOUT := 40.0
## How far the hand must move from the centre of the picture to turn (0..0.5), and how far for full speed.
const DEAD_ZONE := 0.1
const FULL_TURN := 0.3
const PUNCH_REPEAT := 0.45

var status: int = Status.OFF
## More arguments for the tracker (the tests use "--loop-image photo.jpg" instead of the camera).
var extra_args := PackedStringArray()
var gesture := "none"
var _udp: PacketPeerUDP
## Port of the tracker (learnt from its messages; 0 = none yet).
var _tracker_port := 0
var _error := ""
## Id of this start: messages of an older tracker that is still open are ignored.
var _session := ""
var _pid := -1
var _thread: Thread
var _ping := 0.0
var _since_message := 0.0
var _since_start := 0.0
var _held: Array[String] = []
var _punch_wait := 0.0
var _label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_label.offset_left = -330.0
	_label.offset_top = -176.0
	_label.offset_right = -16.0
	_label.offset_bottom = -148.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.visible = false
	layer.add_child(_label)
	if Preferences.gesture_control:
		start()


func is_running() -> bool:
	return status != Status.OFF


func status_text() -> String:
	if status == Status.FAILED:
		return tr(STATUS_TEXT[status]) % _error
	return tr(STATUS_TEXT[status])


func set_enabled(on: bool) -> void:
	Preferences.set_gesture_control(on)
	if on:
		start()
	else:
		stop()


# ------------------------------------------------------------------ start and stop
func start() -> void:
	if status != Status.OFF:
		return
	if not OS.has_feature("pc"):
		_set_status(Status.UNAVAILABLE)
		return
	_udp = PacketPeerUDP.new()
	if _udp.bind(PORT, "127.0.0.1") != OK and _udp.bind(0, "127.0.0.1") != OK:
		_udp = null
		_set_status(Status.NOT_RESPONDING)
		return
	_tracker_port = 0
	_session = str(randi())
	_since_start = 0.0
	_since_message = 0.0
	_set_status(Status.STARTING)
	if FileAccess.file_exists(_bundle()):
		# unzipping ~200 MB takes a few seconds: in a thread, so the game does not stop
		_thread = Thread.new()
		_thread.start(_install_and_run)
	elif OS.has_feature("editor") and FileAccess.file_exists("res://gesture/hand_tracker.py"):
		var python := "python" if OS.get_name() == "Windows" else "python3"
		_launch(python, PackedStringArray([ProjectSettings.globalize_path("res://gesture/hand_tracker.py")]) + _args())
	else:
		stop()
		_set_status(Status.UNAVAILABLE)


func stop() -> void:
	if _udp:
		if _tracker_port > 0:
			_udp.put_packet("quit".to_utf8_buffer())
		_udp.close()
		_udp = null
	if _pid > 0:
		# "quit" closes it (and without pings it closes itself); if it is frozen, it is closed by force
		var pid := _pid
		_pid = -1
		if is_inside_tree():
			get_tree().create_timer(2.0, true, false, true).timeout.connect(func() -> void:
				if OS.is_process_running(pid):
					OS.kill(pid))
	_release_all()
	gesture = "none"
	if status != Status.UNAVAILABLE or not Preferences.gesture_control:
		_set_status(Status.OFF)


func _exit_tree() -> void:
	stop()
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop()


func _args() -> PackedStringArray:
	return PackedStringArray(["--port", str(_udp.get_local_port()), "--session", _session]) + extra_args


## The tracker built for this system, inside the game (only in exports that include it).
func _bundle() -> String:
	var system := {"Windows": "windows", "macOS": "macos"}.get(OS.get_name(), "linux") as String
	return "res://gesture_bin/hand_tracker_%s.zip" % system


func _program() -> String:
	var exe := "hand_tracker.exe" if OS.get_name() == "Windows" else "hand_tracker"
	return ProjectSettings.globalize_path(INSTALL_DIR.path_join(exe))


## (Thread) unzips the tracker if it is not there yet (or it is from another version of the game)
## and starts it.
func _install_and_run() -> void:
	var zip := FileAccess.open(_bundle(), FileAccess.READ)
	var version := str(zip.get_length())
	zip.close()
	var marker := INSTALL_DIR.path_join("version.txt")
	if not FileAccess.file_exists(marker) or FileAccess.get_file_as_string(marker) != version:
		if not _unzip(_bundle(), INSTALL_DIR):
			call_deferred("_on_install_failed")
			return
		var f := FileAccess.open(marker, FileAccess.WRITE)
		f.store_string(version)
		f.close()
		if OS.get_name() != "Windows":
			OS.execute("chmod", ["+x", _program()])
	call_deferred("_launch", _program(), _args())


func _unzip(from: String, to: String) -> bool:
	var reader := ZIPReader.new()
	if reader.open(from) != OK:
		return false
	var root := ProjectSettings.globalize_path(to)
	for path in reader.get_files():
		if path.ends_with("/"):
			continue
		DirAccess.make_dir_recursive_absolute(root.path_join(path.get_base_dir()))
		var out := FileAccess.open(root.path_join(path), FileAccess.WRITE)
		if out == null:
			reader.close()
			return false
		out.store_buffer(reader.read_file(path))
		out.close()
	reader.close()
	return true


func _on_install_failed() -> void:
	stop()
	_set_status(Status.NOT_RESPONDING)


func _launch(program: String, args: PackedStringArray) -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null
	if status == Status.OFF:
		return
	_pid = OS.create_process(program, args)
	if _pid <= 0:
		stop()
		_set_status(Status.NOT_RESPONDING)


func _set_status(s: int) -> void:
	if status == s:
		return
	status = s
	status_changed.emit(status_text())


# ------------------------------------------------------------------ gestures
func _process(delta: float) -> void:
	if _udp == null:
		_label.visible = false
		return
	_since_start += delta
	_since_message += delta
	_ping -= delta
	if _ping <= 0.0 and _tracker_port > 0:
		_ping = 1.0
		_udp.put_packet("ping".to_utf8_buffer())
	var last: Dictionary = {}
	while _udp.get_available_packet_count() > 0:
		var data: Variant = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		var from := _udp.get_packet_port()
		if data is Dictionary and str(data.get("session", "")) == _session:
			last = data
			if from != _tracker_port and data.get("status") != "error":
				_tracker_port = from
				_udp.set_dest_address("127.0.0.1", from)
	if not last.is_empty():
		_since_message = 0.0
		if last.get("status") == "error":
			_error = str(last.get("message", ""))
			_release_all()
			gesture = "none"
			_set_status(Status.FAILED)
		elif last.get("status") == "no_camera":
			_set_status(Status.NO_CAMERA)
			_apply("none", 0.5, 0.5, delta)
		elif last.get("status") == "ok":
			_set_status(Status.READY)
			_apply(str(last.get("gesture", "none")), float(last.get("x", 0.5)), float(last.get("y", 0.5)), delta)
	elif _since_message > SILENCE:
		_release_all()
		gesture = "none"
		if status == Status.STARTING and _since_start > START_TIMEOUT:
			_set_status(Status.NOT_RESPONDING)
	_label.visible = status == Status.READY and _in_game()
	_label.text = tr(GESTURE_TEXT.get(gesture, "Unknown gesture"))


func _in_game() -> bool:
	return get_tree().get_first_node_in_group("world") != null


## Turns a gesture of the tracker into the input actions of player 1.
func _apply(g: String, x: float, y: float, delta: float) -> void:
	var started := g != gesture
	gesture = g
	var world := get_tree().get_first_node_in_group("world") as World
	var sailing := world != null and world.ship.steering
	var want := {}
	if g == "open":
		want["move_forward"] = 1.0
		if y < 0.33 and not sailing:
			want["sprint"] = 1.0
	if g != "none":
		# the hand away from the centre turns: the camera on foot, the helm on the ship
		var off := x - 0.5
		if absf(off) > DEAD_ZONE:
			var k := clampf((absf(off) - DEAD_ZONE) / (FULL_TURN - DEAD_ZONE), 0.0, 1.0)
			var side := ("move_right" if off > 0.0 else "move_left") if sailing else ("look_right" if off > 0.0 else "look_left")
			want[side] = k
	for a in _held.duplicate():
		if not want.has(a):
			Input.action_release(a)
			_held.erase(a)
	for a in want:
		Input.action_press(a, want[a])
		if not _held.has(a):
			_held.append(a)
	# one-shot actions: when the gesture starts (the fist keeps punching)
	_punch_wait -= delta
	match g:
		"fist":
			if started or _punch_wait <= 0.0:
				_punch_wait = PUNCH_REPEAT
				_tap("attack")
		"victory":
			if started:
				_tap("jump")
		"point":
			if started:
				_tap("interact")
		"thumbs_up":
			if started:
				_tap("skill")


## A press of an action as a real input event (menus and dialogues listen to events); it is let
## go a moment later, so the code that checks "just pressed" in the physics frames sees it too.
func _tap(action: String) -> void:
	_send(action, true)
	get_tree().create_timer(0.12, true, false, true).timeout.connect(_send.bind(action, false))


func _send(action: String, pressed: bool) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = pressed
	e.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(e)


func _release_all() -> void:
	for a in _held:
		Input.action_release(a)
	_held.clear()
