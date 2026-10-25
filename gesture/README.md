# Gesture control (hand tracker)

Play Finding the One Piece with your hand in front of the PC camera. `hand_tracker.py` reads the
camera with OpenCV, finds the hand with MediaPipe (`models/hand_landmarker.task`) and sends the
gesture to the game by UDP on 127.0.0.1. The game (`scripts/gesture_control.gd`) turns it into the
normal controls of player 1. Turn it on in **Options → Gesture control (camera)**.

| Gesture | Action |
|---|---|
| Open palm | walk forward (sail with the ship); hand high in the picture: run |
| Hand to the left / right | turn the camera (the helm while sailing) |
| Fist | punch (keeps punching while closed) |
| Two fingers (victory) | jump |
| Index finger | talk / use |
| Thumb up | skill |

## Include it in the exported game (Windows)

The tracker is built into one folder with everything it needs (Python, MediaPipe, OpenCV), so
players install nothing. On the Windows PC that exports the game:

```
python -m pip install -r gesture/requirements.txt
python gesture/build_tracker.py
```

This writes `gesture_bin/hand_tracker_windows.zip` (~200 MB, not kept in git). The Windows export
preset already includes `gesture_bin/hand_tracker_windows.zip` in the game data: the export makes
`builds/windows/FindingTheOnePiece.exe` + `FindingTheOnePiece.pck` (keep them together; the data is
not embedded in the .exe because Windows fails to embed such a big package). The first time a
player turns gesture control on, the game unzips it into its data folder
(`%APPDATA%\Godot\app_userdata\...\hand_tracker`) and starts it; it closes with the game. The same
script builds `hand_tracker_linux.zip` / `hand_tracker_macos.zip` on those systems.

The build is a normal folder (no self-extracting .exe, no UPX), which is what antivirus programs
trust most. If an antivirus ever flags it, report it as a false positive or sign the program with a
code signing certificate; players never need to turn their antivirus off.

## While developing

Without the zip, the game started from the Godot editor runs `gesture/hand_tracker.py` with the
system Python (`pip install mediapipe opencv-python`). To test the tracker alone:

```
python gesture/hand_tracker.py --preview          # camera window with the hand and the gesture
python gesture/hand_tracker.py --image photo.jpg  # prints the gesture of a photo
```
