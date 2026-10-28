// Una llamada y sus archivos, y los pasos que la convierten en transcripción:
// .caf → .m4a en Diario/Audio → .txt del transcriptor → .md en Llamadas.

import AppKit
import AVFoundation
import UserNotifications

enum Carpeta {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let audio = home.appendingPathComponent("Documents/Diario/Audio")
    static let transcripciones = home.appendingPathComponent("Documents/Diario/Transcripciones")
    static let llamadas = home.appendingPathComponent("Documents/Llamadas")
    /// Fuera de iCloud, para no subir un archivo que cambia cada segundo.
    static let trabajo = home.appendingPathComponent("Library/Application Support/Grabar Llamada")
}

struct Llamada {
    let nombre: String
    let inicio: Date

    /// Aquí van los .caf mientras se graba; se borra cuando el .m4a está a salvo.
    var carpeta: URL { Carpeta.trabajo.appendingPathComponent(nombre) }
    var audio: URL { Carpeta.audio.appendingPathComponent(nombre + ".m4a") }
    var transcripcion: URL { Carpeta.transcripciones.appendingPathComponent(nombre + ".txt") }
    var archivoFinal: URL { Carpeta.llamadas.appendingPathComponent(nombre + ".md") }

    /// llamada-AAAA-MM-DD-HHMM, con -2, -3… si ya hubo otra en ese minuto.
    static func nueva() -> Llamada {
        let inicio = Date()
        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd-HHmm"
        let base = "llamada-" + formato.string(from: inicio)
        var llamada = Llamada(nombre: base, inicio: inicio)
        var n = 2
        while llamada.yaExiste {
            llamada = Llamada(nombre: "\(base)-\(n)", inicio: inicio)
            n += 1
        }
        return llamada
    }

    /// Grabaciones que quedaron a medias porque la app se cerró de golpe.
    static func interrumpidas() -> [Llamada] {
        let contenido = (try? FileManager.default.contentsOfDirectory(at: Carpeta.trabajo, includingPropertiesForKeys: nil)) ?? []
        return contenido.filter(\.hasDirectoryPath).map { Llamada(nombre: $0.lastPathComponent, inicio: Date()) }
    }

    /// Lo que haya en la carpeta de una grabación interrumpida, sin alinear ni nivelar.
    var fuentesSueltas: [Fuente] {
        let archivos = (try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: nil)) ?? []
        return archivos.filter { $0.pathExtension == "caf" }.map { Fuente(archivo: $0) }
    }

    private var yaExiste: Bool {
        [carpeta, audio, transcripcion].contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Pasos

    /// Mezcla las fuentes en un .m4a y lo deja en Diario/Audio. El último paso
    /// es un renombrado, instantáneo: el transcriptor nunca ve un archivo a medias.
    func guardarAudio(_ fuentes: [Fuente]) async throws {
        let composicion = AVMutableComposition()
        var volumenes: [AVAudioMixInputParameters] = []
        for fuente in fuentes {
            let asset = AVURLAsset(url: fuente.archivo)
            guard let original = try await asset.loadTracks(withMediaType: .audio).first,
                  let pista = composicion.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            try pista.insertTimeRange(CMTimeRange(start: .zero, duration: try await asset.load(.duration)), of: original,
                                      at: CMTime(seconds: fuente.desfase, preferredTimescale: 48000))
            let volumen = AVMutableAudioMixInputParameters(track: pista)
            volumen.setVolume(fuente.ganancia, at: .zero)
            volumenes.append(volumen)
        }
        guard !volumenes.isEmpty else { throw ErrorApp("La grabación quedó vacía: no entró sonido por ningún lado.") }
        guard let exportar = AVAssetExportSession(asset: composicion, presetName: AVAssetExportPresetAppleM4A) else {
            throw ErrorApp("No pude preparar la conversión a .m4a.")
        }
        let mezcla = AVMutableAudioMix()
        mezcla.inputParameters = volumenes
        exportar.audioMix = mezcla

        let temporal = Carpeta.trabajo.appendingPathComponent(nombre + ".m4a")
        try? FileManager.default.removeItem(at: temporal)
        try await exportar.export(to: temporal, as: .m4a)
        try FileManager.default.createDirectory(at: Carpeta.audio, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: temporal, to: audio)
        try FileManager.default.removeItem(at: carpeta)
        registrar("Audio guardado: \(audio.path) (\(volumenes.count) pista(s))")
    }

    /// Espera el .txt que deja el transcriptor (diario-local). Suele tardar
    /// un 10 % de lo que dura la llamada; esperamos lo mismo que duró (mínimo 10 min).
    func esperarTranscripcion(duracionLlamada: Int,
                              progreso: @MainActor (Int) -> Void) async throws -> String {
        let limite = TimeInterval(max(10 * 60, duracionLlamada))
        let desde = Date()
        while true {
            // El .txt puede existir y aun así no poderse leer un rato (p. ej. si macOS
            // está pidiendo permiso para Documentos): se reintenta hasta el límite.
            if let texto = try? String(contentsOf: transcripcion, encoding: .utf8) { return texto }
            let pasado = Date().timeIntervalSince(desde)
            guard pasado < limite else {
                if FileManager.default.fileExists(atPath: transcripcion.path) {
                    throw ErrorApp("La transcripción está en Diario/Transcripciones/\(nombre).txt, pero no pude leerla. "
                                   + "Revisa que Grabar Llamada tenga acceso a Documentos en Ajustes del Sistema.")
                }
                throw ErrorApp("La transcripción no llegó en \(Int(limite) / 60) minutos. ¿Está corriendo el transcriptor? "
                               + "El audio quedó en Diario/Audio/\(nombre).m4a.")
            }
            await progreso(Int(pasado))
            try await Task.sleep(for: .seconds(1))
        }
    }

    /// La transcripción completa con fecha y duración arriba, lista para pasársela a quien quieras.
    func escribirArchivoFinal(_ texto: String, segundos: Int) throws {
        let fecha = DateFormatter()
        fecha.locale = Locale(identifier: "es")
        fecha.dateFormat = "d 'de' MMMM 'de' yyyy, HH:mm"
        let cuerpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let md = """
        # Llamada del \(fecha.string(from: inicio)) (\(max(1, (segundos + 30) / 60)) min)

        \(cuerpo.isEmpty ? "(No se oyó nada en la grabación.)" : cuerpo)

        ---
        Audio: [\(nombre).m4a](../Diario/Audio/\(nombre).m4a)

        """
        try FileManager.default.createDirectory(at: Carpeta.llamadas, withIntermediateDirectories: true)
        try md.write(to: archivoFinal, atomically: true, encoding: .utf8)
        registrar("Transcripción lista: \(archivoFinal.path)")
    }

    static func abrirUltima() {
        let archivos = (try? FileManager.default.contentsOfDirectory(at: Carpeta.llamadas, includingPropertiesForKeys: nil)) ?? []
        if let ultimo = archivos.filter({ $0.pathExtension == "md" }).max(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            NSWorkspace.shared.open(ultimo)
        }
    }
}

// MARK: - Utilidades

struct ErrorApp: LocalizedError {
    let errorDescription: String?
    init(_ mensaje: String) { errorDescription = mensaje }
}

/// Deja una línea en ~/Library/Application Support/Grabar Llamada/registro.log.
func registrar(_ texto: String) {
    let archivo = Carpeta.trabajo.appendingPathComponent("registro.log")
    let linea = Data("\(Date().formatted(.iso8601))  \(texto)\n".utf8)
    try? FileManager.default.createDirectory(at: Carpeta.trabajo, withIntermediateDirectories: true)
    if let manija = try? FileHandle(forWritingTo: archivo) {
        _ = try? manija.seekToEnd()
        try? manija.write(contentsOf: linea)
        try? manija.close()
    } else {
        try? linea.write(to: archivo)
    }
}

func notificar(_ titulo: String, _ cuerpo: String) {
    let contenido = UNMutableNotificationContent()
    contenido.title = titulo
    contenido.body = cuerpo
    contenido.sound = .default
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: contenido, trigger: nil))
}
