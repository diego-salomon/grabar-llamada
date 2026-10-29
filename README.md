<div align="center">

<img src="icono.svg" width="110" alt="Grabar Llamada app icon" />

# 📞 Grabar Llamada

### A Mac app that records a call from both sides and gives you a local transcript. Double-click to start, stop when you hang up.

[![Swift](https://img.shields.io/badge/Swift-native_macOS_app-FA7343?logo=swift&logoColor=white&style=flat-square)](#run-it)
[![macOS 15](https://img.shields.io/badge/macOS-15_Apple_Silicon-555?logo=apple&logoColor=white&style=flat-square)](#run-it)
[![Local Whisper](https://img.shields.io/badge/transcript-local_Whisper-729B1B?style=flat-square)](https://github.com/diego-salomon/diario-local)
[![License: MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

<br>

<img src="docs/assets/flow.png" width="900" alt="The microphone and the Mac's own audio are recorded as two separate files, then aligned, leveled and mixed into one .m4a, transcribed locally by diario-local, and saved to ~/Documents/Llamadas with a notification." />

</div>

---

The text lands in `~/Documents/Llamadas`.

It records the microphone (phone on speaker next to the Mac) and the Mac's own audio (WhatsApp Desktop, Continuity calls) as two separate files. If one source fails, the other keeps going, and a crash loses nothing: the next launch finishes the recording. On stop it aligns, levels and mixes both into one `.m4a`, hands it to [diario-local](https://github.com/diego-salomon/diario-local) for a local Whisper transcript, and notifies you when it's ready.

If Whisper gets stuck repeating a phrase and skips minutes, `herramientas/retranscribir.py` runs the call again without that context.

## Run it

macOS 15 on Apple Silicon, Xcode command line tools (`xcode-select --install`), and diario-local running.

```bash
./build.sh   # compiles, makes the icon, signs locally, installs to /Applications
```

macOS asks for microphone, system audio and Documents access the first time, and again after each rebuild. Folders are set at the top of `Llamada.swift`.

Code comments are in Spanish.

---

<div align="center">
<sub>Built by <a href="https://github.com/diego-salomon">Diego Salomón</a>. · <a href="https://www.linkedin.com/in/diegosalomon">LinkedIn</a></sub>
</div>
