// Grabar Llamada: doble clic, graba la llamada, y al detenerla deja la
// transcripción completa en ~/Documents/Llamadas.

import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class Delegado: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let sesion = Sesion()
    var ventana: NSWindow?

    func applicationDidFinishLaunching(_ aviso: Notification) {
        // Si macOS abrió la app porque tocaste una de sus notificaciones,
        // no grabamos: abrimos la última transcripción y salimos.
        if aviso.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == false {
            Llamada.abrirUltima()
            return NSApp.terminate(nil)
        }

        let ventana = NSWindow(contentViewController: NSHostingController(rootView: Vista(sesion: sesion)))
        ventana.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        ventana.titlebarAppearsTransparent = true
        ventana.titleVisibility = .hidden
        ventana.title = "Grabar Llamada"
        ventana.isMovableByWindowBackground = true
        ventana.delegate = self
        // La primera vez, centrada; después, donde la dejaste.
        if !ventana.setFrameUsingName("Tarjeta") { ventana.center() }
        ventana.setFrameAutosaveName("Tarjeta")
        ventana.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.ventana = ventana

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        sesion.empezar()
    }

    // Cerrar la ventana equivale a Cmd+Q; las reglas están en un solo sitio.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    // Mientras graba, salir = Detener. Mientras procesa, preguntamos,
    // porque salir ahí deja la llamada sin su archivo en Llamadas.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if sesion.grabando {
            sesion.detener()
            return .terminateCancel
        }
        guard sesion.procesando else { return .terminateNow }
        let alerta = NSAlert()
        alerta.messageText = "¿Salir antes de terminar?"
        alerta.informativeText = "El audio ya está guardado y se transcribirá igual en Diario/Transcripciones, pero no quedará la copia en Llamadas."
        alerta.addButton(withTitle: "Esperar")
        alerta.addButton(withTitle: "Salir")
        return alerta.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}

// El código de arriba del todo ya corre en el hilo principal; se lo decimos a Swift.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegado = Delegado()
    app.delegate = delegado
    app.setActivationPolicy(.regular)

    let menu = NSMenu()
    let itemApp = NSMenuItem()
    itemApp.submenu = NSMenu()
    itemApp.submenu?.addItem(withTitle: "Salir de Grabar Llamada", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(itemApp)
    app.mainMenu = menu

    app.run()
}
