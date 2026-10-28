// Convierte icono.svg en las imágenes que necesita un .icns.
// Uso: swift icono.swift icono.svg carpeta.iconset
import AppKit

let svg = NSImage(contentsOfFile: CommandLine.arguments[1])!
let destino = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)

for lado in [16, 32, 128, 256, 512] {
    for escala in [1, 2] {
        let px = lado * escala
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let nombre = escala == 1 ? "icon_\(lado)x\(lado).png" : "icon_\(lado)x\(lado)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: destino.appendingPathComponent(nombre))
    }
}
