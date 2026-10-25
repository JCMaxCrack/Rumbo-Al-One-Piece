# Requerimientos del control por gestos

## Jugar con el juego ya exportado

No hay que instalar nada. Solo se necesita:

1. Una **cámara web** conectada a la PC.
2. Permiso de cámara en Windows: **Configuración → Privacidad y seguridad → Cámara** y activar
   **"Permitir que las aplicaciones de escritorio accedan a la cámara"**.
3. Tener juntos en la misma carpeta `FindingTheOnePiece.exe` y `FindingTheOnePiece.pck`.
4. Abrir el juego e ir a **Options → Gesture control (camera)**. La primera vez tarda unos 10
   segundos en prepararse.

Si dice "no camera found", hay que cerrar los programas que estén usando la cámara (Zoom, Teams,
Discord, OBS…).

## Usarlo desde el editor de Godot o exportar el juego con el control por gestos

1. **Instalar Git**: https://git-scm.com/download/win
2. **Instalar Python 3.12**: https://www.python.org/downloads/ . Durante la instalación, marcar
   **"Add python.exe to PATH"**.
3. **Instalar Godot 4.7** (versión estándar, no .NET): https://godotengine.org/download
4. **Descargar el proyecto**. En PowerShell, dentro de una carpeta que **no** esté en OneDrive
   (por ejemplo `C:\Juegos`):
   ```
   git clone -b claude/inspiring-gauss-fxfqq3 https://github.com/JCMaxCrack/RumboAlOnePiece-C.git FindingTheOnePiece
   cd FindingTheOnePiece
   ```
5. **Instalar las librerías del detector de manos** (MediaPipe, OpenCV y PyInstaller):
   ```
   py -3.12 -m pip install -r gesture\requirements.txt
   ```
6. **Probar la cámara**: se abre una ventana con la mano detectada y el nombre del gesto
   (Esc para cerrar).
   ```
   py -3.12 gesture\hand_tracker.py --preview
   ```
7. **Usarlo en el editor**: abrir `project.godot` con Godot, ejecutar el juego (F5) y activar
   **Options → Gesture control (camera)**.

### Para exportar el juego con el control por gestos incluido

8. **Compilar el detector** (crea `gesture_bin\hand_tracker_windows.zip`, unos 200 MB):
   ```
   py -3.12 gesture\build_tracker.py
   ```
9. En Godot: **Editor → Gestionar plantillas de exportación → Descargar e instalar** (unos
   1,2 GB). Dejar al menos **3 GB libres** en el disco.
10. **Project → Export → Windows Desktop → Export Project**. Se generan
    `builds\windows\FindingTheOnePiece.exe` y `FindingTheOnePiece.pck`.
