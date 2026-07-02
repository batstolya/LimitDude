import AppKit
import ImageIO
import LimitDudeCore
import UniformTypeIdentifiers

@MainActor
enum ReadmeAssetRenderer {
    static func renderIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--render-readme-assets") else {
            return false
        }

        let outputDirectory = outputDirectoryURL()
        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try renderTaskDoneGIF(to: outputDirectory.appendingPathComponent("limitdude-task-done.gif"))
            try renderLimitsGIF(to: outputDirectory.appendingPathComponent("limitdude-limits.gif"))
            print("Rendered README GIF assets to \(outputDirectory.path)")
            return true
        } catch {
            fputs("Failed to render README assets: \(error)\n", stderr)
            Darwin.exit(1)
        }
    }

    private static func outputDirectoryURL() -> URL {
        if let index = CommandLine.arguments.firstIndex(of: "--readme-assets-dir"),
           CommandLine.arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/assets", isDirectory: true)
    }

    private static func renderTaskDoneGIF(to url: URL) throws {
        let reading = LimitReading.available(reason: "Task done. Можно кодить дальше.\nDuration: 42s")
        try renderGIF(
            to: url,
            frameCount: 132,
            framesPerSecond: 24
        ) { phase, view in
            view.mode = .recovery(reading)
            view.isShowingDetails = phase > 3.05
            view.detailRevealTime = Date().timeIntervalSinceReferenceDate - max(0, phase - 3.05)
        }
    }

    private static func renderLimitsGIF(to url: URL) throws {
        let reading = LimitReading.warning(
            reason: "Left: 18% 5h, weekly 42%. Reset: 2h 14m.",
            usagePercent: nil,
            resetText: "2h 14m"
        )
        try renderGIF(
            to: url,
            frameCount: 144,
            framesPerSecond: 24
        ) { phase, view in
            view.mode = .warning(reading)
            view.isShowingDetails = phase > 2.6
            view.detailRevealTime = Date().timeIntervalSinceReferenceDate - max(0, phase - 2.6)
        }
    }

    private static func renderGIF(
        to url: URL,
        frameCount: Int,
        framesPerSecond: Int,
        configure: (TimeInterval, PixelDudeView) -> Void
    ) throws {
        let viewSize = NSSize(width: 500, height: 230)
        let scale: CGFloat = 1.5
        let pixelSize = NSSize(width: viewSize.width * scale, height: viewSize.height * scale)
        let view = PixelDudeView(frame: NSRect(origin: .zero, size: viewSize))

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            frameCount,
            nil
        ) else {
            throw RenderError.cannotCreateDestination(url.path)
        }

        let fileProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)

        let frameDelay = 1.0 / Double(framesPerSecond)
        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frameDelay
            ]
        ]

        for frame in 0..<frameCount {
            let phase = TimeInterval(frame) * frameDelay
            view.phase = phase
            configure(phase, view)

            guard let image = renderedImage(from: view, viewSize: viewSize, pixelSize: pixelSize) else {
                throw RenderError.cannotRenderFrame(frame)
            }

            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw RenderError.cannotFinalize(url.path)
        }
    }

    private static func renderedImage(from view: PixelDudeView, viewSize: NSSize, pixelSize: NSSize) -> CGImage? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pixelSize.width),
            pixelsHigh: Int(pixelSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        guard let bitmap else { return nil }
        bitmap.size = viewSize

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            return nil
        }

        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        NSRect(origin: .zero, size: viewSize).fill()
        view.draw(view.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.cgImage
    }

    private enum RenderError: Error, CustomStringConvertible {
        case cannotCreateDestination(String)
        case cannotRenderFrame(Int)
        case cannotFinalize(String)

        var description: String {
            switch self {
            case .cannotCreateDestination(let path):
                return "could not create GIF destination at \(path)"
            case .cannotRenderFrame(let frame):
                return "could not render frame \(frame)"
            case .cannotFinalize(let path):
                return "could not finalize GIF at \(path)"
            }
        }
    }
}
