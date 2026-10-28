// El estado de la app: grabando → procesando (audio, transcripción,
// archivo final) → listo. La vista solo lo lee; los pasos viven en Llamada.

import AppKit
import AVFoundation

@MainActor
final class Sesion: ObservableObject {
    enum Paso: Int, CaseIterable { case audio, transcripcion }
    enum Estado: Equatable { case preparando, grabando, procesando(Paso), listo, fallo(String) }

    @Published private(set) var estado = Estado.preparando
    @Published private(set) var segundos = 0
    @Published private(set) var nivelMicro = 0.0
    @Published private(set) var nivelMac = 0.0
    @Published private(set) var nombreMicro = ""
    @Published private(set) var espera = 0
    @Published private(set) var faltaPermisoMicro = false

    private let grabadora = Grabadora()
    private var llamada: Llamada?
    private var reloj: Timer?

    var grabando: Bool { estado == .grabando }
    var procesando: Bool { if case .procesando = estado { true } else { false } }

    func empezar() {
        AVCaptureDevice.requestAccess(for: .audio) { permitido in
            Task { @MainActor in
                guard permitido else {
                    self.faltaPermisoMicro = true
                    return self.fallar("Grabar Llamada no tiene permiso para usar el micrófono.")
                }
                self.grabar()
            }
        }
    }

    func detener() {
        guard grabando, let llamada else { return }
        reloj?.invalidate()
        let fuentes = grabadora.detener()
        (nivelMicro, nivelMac) = (0, 0)
        registrar("Detenida tras \(segundos) s")
        Task { await procesar(llamada, fuentes) }
    }

    private func grabar() {
        let interrumpidas = Llamada.interrumpidas()   // antes de crear la carpeta nueva
        let llamada = Llamada.nueva()
        do {
            try FileManager.default.createDirectory(at: llamada.carpeta, withIntermediateDirectories: true)
            try grabadora.iniciar(en: llamada.carpeta)
        } catch {
            _ = grabadora.detener()
            return fallar("No pude empezar a grabar. \(error.localizedDescription)")
        }
        self.llamada = llamada
        nombreMicro = grabadora.nombreMicro
        estado = .grabando
        registrar("Grabando \(llamada.nombre)")
        reloj = Timer.scheduledTimer(withTimeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.medir() }
        }
        Task { await recuperar(interrumpidas) }
        // Leer la carpeta ahora hace que macOS pida el permiso de Documentos al
        // empezar, contigo delante, y no al final, cuando ya hay que leer el .txt.
        DispatchQueue.global().async {
            _ = try? FileManager.default.contentsOfDirectory(atPath: Carpeta.transcripciones.path)
        }
    }

    private func medir() {
        guard let llamada else { return }
        segundos = Int(Date().timeIntervalSince(llamada.inicio))
        // Escala en decibeles (-50 dB = vacío) y caída suave, como un vúmetro.
        func escala(_ pico: Float) -> Double { pico > 0 ? min(1, max(0, (20 * log10(Double(pico)) + 50) / 50)) : 0 }
        let pico = grabadora.niveles()
        nivelMicro = max(escala(pico.micro), nivelMicro * 0.85)
        nivelMac = max(escala(pico.mac), nivelMac * 0.85)
    }

    private func procesar(_ llamada: Llamada, _ fuentes: [Fuente]) async {
        do {
            estado = .procesando(.audio)
            try await llamada.guardarAudio(fuentes)
            estado = .procesando(.transcripcion)
            let texto = try await llamada.esperarTranscripcion(duracionLlamada: segundos) { self.espera = $0 }
            try llamada.escribirArchivoFinal(texto, segundos: segundos)
            NSWorkspace.shared.open(llamada.archivoFinal)
            NSWorkspace.shared.activateFileViewerSelecting([llamada.archivoFinal])   // y a un clic en el Finder
            notificar("Transcripción lista", llamada.archivoFinal.lastPathComponent)
            estado = .listo
            try? await Task.sleep(for: .seconds(1.5))
            NSApp.terminate(nil)
        } catch {
            notificar("Grabar Llamada: algo falló", error.localizedDescription)
            fallar(error.localizedDescription)
        }
    }

    private func recuperar(_ llamadas: [Llamada]) async {
        for llamada in llamadas {
            do {
                try await llamada.guardarAudio(llamada.fuentesSueltas)
                notificar("Grabación recuperada", "\(llamada.nombre).m4a quedó en Diario/Audio y se transcribirá sola.")
            } catch {
                registrar("No pude recuperar \(llamada.nombre): \(error.localizedDescription)")
            }
        }
    }

    private func fallar(_ mensaje: String) {
        registrar("Error: \(mensaje)")
        estado = .fallo(mensaje)
    }
}
