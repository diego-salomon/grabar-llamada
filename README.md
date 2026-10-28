# Grabar Llamada

A native macOS app I wrote in Swift. Double-click it and it starts recording the call. When you stop it, a full transcript lands in your notes folder.

I wanted a record of what gets agreed on every call, with zero setup while it happens. It works with a phone on speaker as well as with a WhatsApp Desktop or Continuity call on the Mac.

## How it works

- **Two independent sources.** It records the microphone (a phone on speaker next to the Mac) and the Mac's own audio (WhatsApp Desktop, or Continuity calls with headphones) into separate `.caf` files. If one fails, the other keeps going.
- **Crash-safe.** The files are written as it records, so they stay readable if the app dies. On the next launch it finds any interrupted recording and finishes it.
- **Mixes, aligns and levels** the sources when you stop, and saves an `.m4a`.
- **Transcribes locally.** It hands the audio to my [local diary transcriber](https://github.com/diego-salomon/diario-local), which runs Whisper large-v3-turbo on Apple Silicon. Nothing goes to the cloud.
- **Notifies you** when the transcript is ready. Tapping the notification opens it.
- `herramientas/retranscribir.py` rescues a call when Whisper gets stuck in a loop (it sometimes repeats "Gracias." and skips whole minutes), by running it again without previous-text conditioning.

## Build

```bash
./build.sh   # compiles with swiftc, generates the icon from icono.svg, signs ad hoc, installs to /Applications
```

Requires macOS 15 on Apple Silicon. The code comments are in Spanish.
