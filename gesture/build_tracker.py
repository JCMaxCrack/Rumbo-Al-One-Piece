"""Builds the hand tracker into the game: gesture/hand_tracker.py -> gesture_bin/hand_tracker_<os>.zip

    python -m pip install -r gesture/requirements.txt
    python gesture/build_tracker.py

Run it on the system you export the game for (on Windows for the Windows export). PyInstaller
makes a folder with the program and everything it needs (Python, MediaPipe, OpenCV, the hand
model), so the players do not need to install anything. It is a normal folder, not a
self-extracting .exe and not compressed with UPX: that is what antivirus programs trust most.
The folder is zipped into gesture_bin/; the Windows export preset includes gesture_bin/* in the
game, and the game unzips it into its data folder the first time gesture control is turned on.
"""

import os
import platform
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SYSTEMS = {"Windows": "windows", "Linux": "linux", "Darwin": "macos"}


def main():
    system = SYSTEMS.get(platform.system())
    if system is None:
        sys.exit("Unsupported system: " + platform.system())
    work = os.path.join(HERE, "build")
    dist = os.path.join(work, "dist")
    sep = ";" if system == "windows" else ":"
    subprocess.check_call([
        sys.executable, "-m", "PyInstaller", "--noconfirm", "--clean", "--onedir", "--noupx",
        "--name", "hand_tracker", "--exclude-module", "tkinter",
        "--distpath", dist, "--workpath", os.path.join(work, "tmp"), "--specpath", work,
        "--add-data", os.path.join(HERE, "models", "hand_landmarker.task") + sep + "models",
        "--collect-data", "mediapipe", "--collect-binaries", "mediapipe",
        "--console" if system != "windows" else "--noconsole",
        os.path.join(HERE, "hand_tracker.py"),
    ])
    out_dir = os.path.join(ROOT, "gesture_bin")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "hand_tracker_%s.zip" % system)
    folder = os.path.join(dist, "hand_tracker")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for base, _dirs, files in os.walk(folder):
            for f in files:
                path = os.path.join(base, f)
                z.write(path, os.path.relpath(path, folder))
    shutil.rmtree(work, ignore_errors=True)
    print("Hand tracker ready: %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6))


if __name__ == "__main__":
    main()
