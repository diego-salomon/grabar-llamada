// La tarjeta: reloj, un medidor por fuente y el botón rojo. Al detener,
// la misma tarjeta muestra los pasos hasta la transcripción.

import SwiftUI

extension Color {
    static let rojo = Color(red: 0.886, green: 0.294, blue: 0.290)   // #E24B4A, el del ícono
    static let verde = Color(red: 0.114, green: 0.620, blue: 0.459)  // #1D9E75
    static let coral = Color(red: 0.847, green: 0.353, blue: 0.188)  // #D85A30
}

struct Vista: View {
    @ObservedObject var sesion: Sesion

    var body: some View {
        Group {
            switch sesion.estado {
            case .preparando: ProgressView().controlSize(.small)
            case .grabando: grabando
            case .procesando(let paso): procesando(actual: paso)
            case .listo: procesando(actual: nil)
            case .fallo(let mensaje): fallo(mensaje)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)   // la barra de título es transparente; esto deja sitio a los botones
        .frame(width: 260, height: 290)
    }

    private var grabando: some View {
        VStack(spacing: 14) {
            Label("Grabando", systemImage: "circle.fill")
                .labelStyle(PuntoYTexto())
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.rojo)
            Reloj(segundos: sesion.segundos)
            VStack(spacing: 10) {
                Medidor(titulo: "Micrófono · \(sesion.nombreMicro)", nivel: sesion.nivelMicro, color: .verde)
                Medidor(titulo: "Audio del Mac", nivel: sesion.nivelMac, color: .coral)
            }
            Button(action: sesion.detener) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Color.rojo))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .help("Detener y transcribir (↩)")
            .accessibilityLabel("Detener")
            .padding(.top, 4)
        }
    }

    private func procesando(actual: Sesion.Paso?) -> some View {
        VStack(spacing: 22) {
            Reloj(segundos: sesion.segundos).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Sesion.Paso.allCases, id: \.self) { paso in
                    let hecho = actual.map { paso.rawValue < $0.rawValue } ?? true
                    FilaPaso(texto: texto(de: paso, hecho: hecho), hecho: hecho, enCurso: paso == actual)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func texto(de paso: Sesion.Paso, hecho: Bool) -> String {
        switch (paso, hecho) {
        case (.audio, true): "Audio guardado"
        case (.audio, false): "Guardando audio"
        case (.transcripcion, true): "Transcripción lista"
        case (.transcripcion, false): sesion.espera > 0 ? "Transcribiendo · " + String(format: "%d:%02d", sesion.espera / 60, sesion.espera % 60) : "Transcribiendo"
        }
    }

    private func fallo(_ mensaje: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(mensaje)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if sesion.faltaPermisoMicro {
                Button("Abrir Ajustes de Micrófono") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                }
            }
            Button("Cerrar") { NSApp.terminate(nil) }
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct Reloj: View {
    let segundos: Int

    var body: some View {
        let (h, m, s) = (segundos / 3600, segundos / 60 % 60, segundos % 60)
        Text(h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s))
            .font(.system(size: 44, weight: .medium, design: .rounded).monospacedDigit())
    }
}

private struct Medidor: View {
    let titulo: String
    let nivel: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            GeometryReader { espacio in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color).frame(width: max(6, espacio.size.width * nivel))
                }
            }
            .frame(height: 6)
            .animation(.linear(duration: 0.08), value: nivel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titulo)
        .accessibilityValue("\(Int(nivel * 100)) por ciento")
    }
}

private struct FilaPaso: View {
    let texto: String
    let hecho: Bool
    let enCurso: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if hecho {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.verde)
                } else if enCurso {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18, height: 18)
            Text(texto).foregroundStyle(hecho || enCurso ? .primary : .tertiary)
        }
        .font(.callout)
    }
}

/// Un punto que late a la izquierda del texto.
private struct PuntoYTexto: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7)).symbolEffect(.pulse)
            configuration.title
        }
    }
}
