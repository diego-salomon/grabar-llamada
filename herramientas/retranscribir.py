"""
Vuelve a transcribir una llamada y deja el resultado en ~/Documents/Personal/Llamadas.

Sirve para rescatar una llamada cuya transcripción falló o salió con huecos
(Whisper a veces se atasca repitiendo "Gracias." y se salta minutos enteros).
Usa el mismo modelo que el transcriptor, pero sin darle a Whisper el texto
anterior como contexto, que es lo que alimenta esos bucles.

Uso (con el Python del transcriptor, que ya tiene mlx-whisper):
    ~/Diario-transcriptor/.venv/bin/python herramientas/retranscribir.py \
        ~/Documents/Personal/Diario/Audio/llamada-AAAA-MM-DD-HHMM.m4a

No toca el audio ni el .txt original de Diario/Transcripciones.
"""

import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path.home() / "Diario-transcriptor"))
from transcriptor import texto_en_parrafos  # mismo formato que el resto de transcripciones

import mlx_whisper

LLAMADAS = Path.home() / "Documents/Personal/Llamadas"
os.environ["PATH"] = "/opt/homebrew/bin:" + os.environ.get("PATH", "")  # Whisper necesita ffmpeg


def main() -> None:
    audio = Path(sys.argv[1]).expanduser()
    nombre = audio.stem
    duracion = float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(audio)],
        capture_output=True, text=True, check=True).stdout)

    print(f"Transcribiendo {audio.name} ({duracion / 60:.0f} min)…", flush=True)
    resultado = mlx_whisper.transcribe(
        str(audio),
        path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
        language="es",
        condition_on_previous_text=False,
        verbose=None,
    )

    # llamada-2026-10-19-2207 → 19 de octubre de 2026, 22:07
    inicio = datetime.strptime(nombre.removeprefix("llamada-")[:15], "%Y-%m-%d-%H%M")
    meses = "enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre".split()
    fecha = f"{inicio.day} de {meses[inicio.month - 1]} de {inicio.year}, {inicio:%H:%M}"

    LLAMADAS.mkdir(parents=True, exist_ok=True)
    destino = LLAMADAS / f"{nombre}.md"
    destino.write_text(
        f"# Llamada del {fecha} ({round(duracion / 60)} min)\n\n"
        f"{texto_en_parrafos(resultado)}\n\n"
        f"---\nAudio: [{nombre}.m4a](../Diario/Audio/{nombre}.m4a)\n",
        encoding="utf-8",
    )
    print(f"Listo: {destino}")


if __name__ == "__main__":
    main()
