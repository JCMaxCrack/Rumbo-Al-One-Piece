"""Hand tracker for Finding the One Piece: gesture control with the PC camera.

It reads the camera with OpenCV, finds one hand with MediaPipe (HandLandmarker) and sends what it
sees to the game by UDP on this computer only (127.0.0.1), about 30 times per second:

    {"status": "ok", "gesture": "open", "x": 0.62, "y": 0.41}

    status:  "ok", or "no_camera" when the camera can not be opened (it keeps trying).
    gesture: "none" (no hand), "open" (open palm), "fist", "point" (only the index finger),
             "victory" (index and middle fingers), "thumbs_up" or "other".
    x, y:    centre of the palm in the picture, 0..1, as in a mirror (x = 0 is the player's left).

The game (scripts/gesture_control.gd) starts this program, sends it "ping" every second and
"quit" when it closes. Without pings for PING_TIMEOUT seconds the tracker closes itself, so it
never stays open after the game.

Usage:
    hand_tracker [--port 4242] [--listen 4243] [--camera 0] [--preview]
    hand_tracker --image photo.jpg     # prints the gesture of a photo and exits (for testing)
    hand_tracker --loop-image photo.jpg  # uses a photo instead of the camera (for testing)

Built into the game with build_tracker.py (PyInstaller), see README.md.
"""

import argparse
import json
import math
import os
import socket
import sys
import time

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision

PING_TIMEOUT = 5.0
# the game starts it and connects a moment later: before the first ping it waits longer
FIRST_PING_TIMEOUT = 30.0
# a gesture must be seen this many frames in a row before it is sent (no flickering)
STABLE_FRAMES = 3

WRIST = 0
THUMB = (1, 2, 3, 4)
FINGERS = {"index": (5, 6, 7, 8), "middle": (9, 10, 11, 12), "ring": (13, 14, 15, 16), "pinky": (17, 18, 19, 20)}


def resource(name):
    """Path of a file next to the program (also inside the PyInstaller bundle)."""
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, name)


def dist(a, b):
    return math.hypot(a.x - b.x, a.y - b.y)


def classify(lm):
    """Gesture of the 21 landmarks of one hand."""
    wrist = lm[WRIST]
    palm = dist(wrist, lm[9])  # size of the hand, so it works near and far from the camera
    up = {}
    for name, (mcp, pip, _dip, tip) in FINGERS.items():
        # a finger is stretched when its tip is clearly farther from the wrist than its middle joint
        up[name] = dist(lm[tip], wrist) > dist(lm[pip], wrist) * 1.15
    # the thumb is out when its tip is far from the base of the index finger
    thumb_out = dist(lm[THUMB[3]], lm[5]) > palm * 0.55
    count = sum(up.values())
    if count >= 4:
        return "open"
    if count == 0:
        # thumb up: thumb out and its tip above the rest of the hand
        if thumb_out and lm[THUMB[3]].y < min(lm[i].y for i in (5, 9, 13, 17)) - palm * 0.2:
            return "thumbs_up"
        return "fist"
    if up["index"] and count == 1:
        return "point"
    if up["index"] and up["middle"] and count == 2:
        return "victory"
    return "other"


class Tracker:
    def __init__(self, args):
        self.args = args
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # a tracker that the game just closed may still be letting go of the port
        for attempt in range(50):
            try:
                self.sock.bind(("127.0.0.1", args.listen))
                break
            except OSError:
                if attempt == 49:
                    raise
                time.sleep(0.1)
        self.sock.setblocking(False)
        self.target = ("127.0.0.1", args.port)
        options = vision.HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=resource(os.path.join("models", "hand_landmarker.task"))),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=1,
            min_hand_detection_confidence=0.6,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self.landmarker = vision.HandLandmarker.create_from_options(options)
        self.cap = None
        self.last_ping = None
        self.started = time.monotonic()
        self.candidate = "none"
        self.candidate_frames = 0
        self.gesture = "none"

    def send(self, data):
        try:
            self.sock.sendto(json.dumps(data).encode(), self.target)
        except OSError:
            pass

    def read_messages(self):
        """Pings and "quit" from the game. Returns False when the tracker must close."""
        while True:
            try:
                msg, _ = self.sock.recvfrom(256)
            except (BlockingIOError, OSError):
                break
            if msg.strip() == b"quit":
                return False
            self.last_ping = time.monotonic()
        now = time.monotonic()
        if self.last_ping is None:
            return now - self.started < FIRST_PING_TIMEOUT
        return now - self.last_ping < PING_TIMEOUT

    def open_camera(self):
        if self.args.loop_image:
            return True
        if self.cap is not None and self.cap.isOpened():
            return True
        backend = cv2.CAP_DSHOW if sys.platform == "win32" else cv2.CAP_ANY
        self.cap = cv2.VideoCapture(self.args.camera, backend)
        if not self.cap.isOpened():
            self.cap = None
            return False
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
        return True

    def frame(self):
        if self.args.loop_image:
            time.sleep(1.0 / 30.0)
            return cv2.imread(self.args.loop_image)
        ok, img = self.cap.read()
        if not ok:
            self.cap.release()
            self.cap = None
            return None
        return img

    def stable(self, gesture):
        if gesture == self.candidate:
            self.candidate_frames += 1
        else:
            self.candidate = gesture
            self.candidate_frames = 1
        if self.candidate_frames >= STABLE_FRAMES or gesture == "none":
            self.gesture = gesture
        return self.gesture

    def run(self):
        while self.read_messages():
            if not self.open_camera():
                self.send({"status": "no_camera", "gesture": "none", "x": 0.5, "y": 0.5})
                time.sleep(2.0)
                continue
            img = self.frame()
            if img is None:
                continue
            img = cv2.flip(img, 1)  # a mirror: moving the hand to the right moves it right on screen
            rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
            result = self.landmarker.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb), int(time.monotonic() * 1000))
            gesture, x, y = "none", 0.5, 0.5
            if result.hand_landmarks:
                lm = result.hand_landmarks[0]
                gesture = classify(lm)
                x = (lm[0].x + lm[9].x) / 2.0
                y = (lm[0].y + lm[9].y) / 2.0
            gesture = self.stable(gesture)
            self.send({"status": "ok", "gesture": gesture, "x": round(x, 3), "y": round(y, 3)})
            if self.args.preview:
                self.draw_preview(img, result, gesture)
        self.close()

    def draw_preview(self, img, result, gesture):
        h, w = img.shape[:2]
        for lm in result.hand_landmarks:
            for p in lm:
                cv2.circle(img, (int(p.x * w), int(p.y * h)), 4, (0, 220, 255), -1)
        cv2.putText(img, gesture, (12, 36), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (40, 255, 40), 2)
        cv2.imshow("Hand tracker", img)
        if cv2.waitKey(1) & 0xFF == 27:
            self.last_ping = 0.0

    def close(self):
        self.send({"status": "closed", "gesture": "none", "x": 0.5, "y": 0.5})
        if self.cap is not None:
            self.cap.release()
        self.landmarker.close()
        self.sock.close()


def gesture_of_image(path):
    options = vision.HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=resource(os.path.join("models", "hand_landmarker.task"))),
        running_mode=vision.RunningMode.IMAGE, num_hands=1)
    with vision.HandLandmarker.create_from_options(options) as landmarker:
        img = cv2.imread(path)
        if img is None:
            return "error: can not read " + path
        rgb = cv2.cvtColor(cv2.flip(img, 1), cv2.COLOR_BGR2RGB)
        result = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        return classify(result.hand_landmarks[0]) if result.hand_landmarks else "none"


def main():
    parser = argparse.ArgumentParser(description="Hand gesture tracker for Finding the One Piece")
    parser.add_argument("--port", type=int, default=4242, help="UDP port of the game (where gestures are sent)")
    parser.add_argument("--listen", type=int, default=4243, help="UDP port where the game's pings arrive")
    parser.add_argument("--camera", type=int, default=0, help="index of the camera")
    parser.add_argument("--preview", action="store_true", help="show the camera with the hand (to test it)")
    parser.add_argument("--image", help="print the gesture of a photo and exit")
    parser.add_argument("--loop-image", help="use a photo instead of the camera")
    args = parser.parse_args()
    if args.image:
        print(gesture_of_image(args.image))
        return
    Tracker(args).run()


if __name__ == "__main__":
    main()
