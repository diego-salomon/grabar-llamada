// Graba dos fuentes independientes, cada una en su .caf:
//   - el micrófono (lo principal: el teléfono en altavoz cerca del Mac),
//   - el audio del Mac (llamadas por WhatsApp Desktop o Continuity con audífonos).
// Si una falla, la otra sigue. Al detener se mezclan en Llamada.guardarAudio.
// Los .caf se escriben poco a poco y siguen legibles si la app se cae.

import AVFoundation
import AudioToolbox
import CoreAudio

final class Grabadora {
    private var micro: Micro?
    private var mac: AudioDelMac?
    private var activa = false
    private(set) var nombreMicro = ""

    /// Arranca el micrófono (si falla, lanza error) y, en segundo plano, el
    /// audio del Mac: su arranque puede tardar, p. ej. mientras macOS pide permiso.
    func iniciar(en carpeta: URL) throws {
        micro = try Micro(archivo: carpeta.appendingPathComponent("micro.caf"))
        nombreMicro = AVCaptureDevice.default(for: .audio)?.localizedName ?? "Micrófono"
        activa = true
        registrar("Micrófono: \(nombreMicro)")
        DispatchQueue.global().async {
            do {
                let mac = try AudioDelMac(archivo: carpeta.appendingPathComponent("mac.caf"))
                DispatchQueue.main.async {
                    if self.activa { self.mac = mac } else { mac.detener() }
                }
            } catch {
                registrar("Audio del Mac no disponible: \(error.localizedDescription)")
            }
        }
    }

    /// Pico de cada fuente desde la última consulta (0...1), para los medidores.
    func niveles() -> (micro: Float, mac: Float) {
        (micro?.pista.leerPico() ?? 0, mac?.pista.leerPico() ?? 0)
    }

    /// Detiene todo y devuelve las fuentes con sonido, alineadas y niveladas.
    func detener() -> [Fuente] {
        activa = false
        micro?.detener()
        mac?.detener()
        let pistas = [micro?.pista, mac?.pista].compactMap { $0 }.filter { $0.maximo > 0 }
        registrar(String(format: "Picos: micrófono %.3f, audio del Mac %.3f",
                         micro?.pista.maximo ?? 0, mac?.pista.maximo ?? 0))
        let primera = pistas.map(\.inicio).min() ?? 0
        return pistas.map { pista in
            Fuente(archivo: pista.archivo,
                   desfase: AVAudioTime.seconds(forHostTime: pista.inicio) - AVAudioTime.seconds(forHostTime: primera),
                   ganancia: min(8, 0.5 / pista.maximo))   // cada voz a medio volumen: la suma no satura
        }
    }
}

/// Un archivo de audio de la llamada, listo para mezclar.
struct Fuente {
    let archivo: URL
    var desfase: TimeInterval = 0
    var ganancia: Float = 1
}

// MARK: - Pista: un .caf mono de 48 kHz que se escribe poco a poco

final class Pista {
    let archivo: URL
    private var ref: ExtAudioFileRef?
    // Los escribe el hilo de audio y los lee la interfaz. Una carrera aquí
    // solo mueve un medidor un instante, así que no vale un candado.
    private var pico: Float = 0
    private(set) var maximo: Float = 0
    private(set) var inicio: UInt64 = 0   // hora (host time) de la primera muestra

    /// `frecuencia` es la de las muestras que llegan; el archivo siempre
    /// queda a 48 kHz y ExtAudioFile convierte por el camino.
    init(archivo: URL, frecuencia: Double) throws {
        self.archivo = archivo
        var formatoArchivo = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        var formatoEntrada = AudioStreamBasicDescription(
            mSampleRate: frecuencia, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1,
            mBitsPerChannel: 32, mReserved: 0)
        try comprobar(ExtAudioFileCreateWithURL(archivo as CFURL, kAudioFileCAFType, &formatoArchivo, nil,
                                                AudioFileFlags.eraseFile.rawValue, &ref), "crear el archivo de audio")
        try comprobar(ExtAudioFileSetProperty(ref!, kExtAudioFileProperty_ClientDataFormat,
                                              UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &formatoEntrada),
                      "preparar el archivo de audio")
        // La escritura asíncrona hay que "cebarla" una vez fuera del hilo de audio.
        try comprobar(ExtAudioFileWriteAsync(ref!, 0, nil), "preparar la escritura")
    }

    /// Apta para el hilo de audio: no reserva memoria ni espera.
    func escribir(_ muestras: UnsafeMutablePointer<Float>, cuadros: Int, hora: UInt64) {
        guard let ref, cuadros > 0 else { return }
        if inicio == 0 { inicio = hora }
        var p: Float = 0
        for i in 0..<cuadros { p = max(p, abs(muestras[i])) }
        pico = max(pico, p)
        maximo = max(maximo, p)
        var lista = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 1, mDataByteSize: UInt32(cuadros * 4), mData: muestras))
        ExtAudioFileWriteAsync(ref, UInt32(cuadros), &lista)
    }

    func leerPico() -> Float {
        defer { pico = 0 }
        return pico
    }

    func cerrar() {
        if let ref { ExtAudioFileDispose(ref) }
        ref = nil
    }
}

// MARK: - Micrófono (el que esté por defecto)

private final class Micro {
    let pista: Pista
    private let motor = AVAudioEngine()

    init(archivo: URL) throws {
        let entrada = motor.inputNode
        let formato = entrada.outputFormat(forBus: 0)
        guard formato.sampleRate > 0, formato.channelCount > 0 else { throw ErrorApp("No hay ningún micrófono conectado.") }
        pista = try Pista(archivo: archivo, frecuencia: formato.sampleRate)
        var mono = [Float]()
        entrada.installTap(onBus: 0, bufferSize: 4096, format: formato) { [pista] buffer, hora in
            guard let canales = buffer.floatChannelData else { return }
            let (n, c) = (Int(buffer.frameLength), Int(buffer.format.channelCount))
            // Este bloque no corre en el hilo de audio: aquí sí se puede reservar memoria.
            mono = (0..<n).map { i in (0..<c).reduce(0) { $0 + canales[$1][i] } / Float(c) }
            mono.withUnsafeMutableBufferPointer { pista.escribir($0.baseAddress!, cuadros: n, hora: hora.hostTime) }
        }
        try motor.start()
    }

    func detener() {
        motor.inputNode.removeTap(onBus: 0)
        motor.stop()
        pista.cerrar()
    }
}

// MARK: - Audio del Mac (process tap de Core Audio, macOS 14.2+)

private final class AudioDelMac {
    let pista: Pista
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var agregado = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?

    init(archivo: URL) throws {
        // Copia en mono de todo lo que suena en el Mac.
        let descripcion = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        descripcion.uuid = UUID()
        descripcion.isPrivate = true
        descripcion.muteBehavior = .unmuted
        try comprobar(AudioHardwareCreateProcessTap(descripcion, &tap), "capturar el audio del Mac")
        let formato: AudioStreamBasicDescription = try leer(tap, kAudioTapPropertyFormat, inicial: AudioStreamBasicDescription())
        pista = try Pista(archivo: archivo, frecuencia: formato.mSampleRate)

        // Un dispositivo agregado privado con la salida de audio como reloj y el tap como entrada.
        let salida: AudioObjectID = try leer(AudioObjectID(kAudioObjectSystemObject),
                                             kAudioHardwarePropertyDefaultOutputDevice, inicial: AudioObjectID(kAudioObjectUnknown))
        let uidSalida = try texto(salida, kAudioDevicePropertyDeviceUID)
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Grabar Llamada",
            kAudioAggregateDeviceUIDKey: "GrabarLlamada-" + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: uidSalida,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uidSalida]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: descripcion.uuid.uuidString,
                                              kAudioSubTapDriftCompensationKey: true]],
        ]
        try comprobar(AudioHardwareCreateAggregateDevice(config as CFDictionary, &agregado), "preparar el audio del Mac")

        // Si la salida también tiene micrófono (p. ej. unos AirPods), sus
        // entradas llegan primero; el tap siempre es la última.
        try comprobar(AudioDeviceCreateIOProcIDWithBlock(&proc, agregado, nil) { [pista] _, entrada, hora, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: entrada))
            guard let tap = buffers.last, let datos = tap.mData, tap.mNumberChannels == 1 else { return }
            pista.escribir(datos.assumingMemoryBound(to: Float.self), cuadros: Int(tap.mDataByteSize) / 4,
                           hora: hora.pointee.mHostTime)
        }, "preparar el audio del Mac")
        try comprobar(AudioDeviceStart(agregado, proc), "empezar a grabar el audio del Mac")
        registrar("Audio del Mac: grabando desde \((try? texto(salida, kAudioObjectPropertyName)) ?? "?")")
    }

    func detener() {
        AudioDeviceStop(agregado, proc)
        if let proc { AudioDeviceDestroyIOProcID(agregado, proc) }
        AudioHardwareDestroyAggregateDevice(agregado)
        AudioHardwareDestroyProcessTap(tap)
        pista.cerrar()
    }
}

// MARK: - Ayudas para Core Audio

private func comprobar(_ estado: OSStatus, _ que: String) throws {
    guard estado == noErr else { throw ErrorApp("No pude \(que) (código Core Audio \(estado)).") }
}

private func direccion(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
}

private func leer<T: BitwiseCopyable>(_ objeto: AudioObjectID, _ selector: AudioObjectPropertySelector, inicial: T) throws -> T {
    var dir = direccion(selector)
    var valor = inicial
    var tamano = UInt32(MemoryLayout<T>.size)
    try comprobar(AudioObjectGetPropertyData(objeto, &dir, 0, nil, &tamano, &valor), "leer una propiedad de audio")
    return valor
}

private func texto(_ objeto: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    var dir = direccion(selector)
    var valor: Unmanaged<CFString>?
    var tamano = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    try comprobar(AudioObjectGetPropertyData(objeto, &dir, 0, nil, &tamano, &valor), "leer el nombre de un dispositivo")
    guard let valor else { throw ErrorApp("Un dispositivo de audio no tiene nombre.") }
    return valor.takeRetainedValue() as String
}
