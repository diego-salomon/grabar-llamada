# Grabar Llamada

A Mac app for recording calls. Double-click it and it starts recording. Stop it, and a few minutes later the full transcript is in your notes folder.

I wanted a record of what gets agreed on calls without having to set anything up while the call is happening. It works with the phone on speaker next to the Mac, and with calls on the computer itself (WhatsApp Desktop, or a Continuity call with headphones).

## How it works

It records two sources into separate files: the microphone, and the Mac's own audio. If one fails, the other keeps going. The files are written as it records, so if the app crashes nothing is lost, and the next launch finishes the interrupted recording.

When you stop, it lines the two sources up, levels them, mixes them into one `.m4a` and drops it in the folder my [diario-local](https://github.com/diego-salomon/diario-local) transcriber watches. Whisper transcribes it on the Mac, and the app sends you a notification when the text is ready. Tap it to open the transcript.

Whisper sometimes gets stuck repeating "Gracias." and skips whole minutes. `herramientas/retranscribir.py` runs the call again without feeding Whisper the previous text, which is what causes those loops.

## Run it

You need macOS 15 on Apple Silicon, the Xcode command line tools (`xcode-select --install`), and [diario-local](https://github.com/diego-salomon/diario-local) running for the transcription.

```bash
./build.sh   # compiles, makes the icon, signs it locally and installs it in /Applications
```

The first time, macOS asks for permission to use the microphone, the system audio and Documents. Every rebuild changes the local signature, so you'll be asked again.

The folders are set in `Llamada.swift` (`Documents/Personal/Diario/Audio` for the audio, `Documents/Personal/Llamadas` for the transcripts). Change them there if yours are different.

The code comments are in Spanish.
