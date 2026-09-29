import AppKit
import Core

/// Slices a grid-layout PNG sprite sheet into individual CGImage frames.
/// Frames are read left-to-right, top-to-bottom, `frameWidth`x`frameHeight`
/// each, wrapping to the next row once a row is exhausted.
public enum SpriteSheetLoader {
    public static func loadFrames(fileURL: URL, frameWidth: Int, frameHeight: Int, frameCount: Int) -> [CGImage] {
        guard
            frameWidth > 0, frameHeight > 0, frameCount > 0,
            let data = try? Data(contentsOf: fileURL),
            let dataProvider = CGDataProvider(data: data as CFData),
            let sheet = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            return []
        }

        let columns = max(1, sheet.width / frameWidth)
        var frames: [CGImage] = []
        frames.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            let column = index % columns
            let row = index / columns
            let rect = CGRect(
                x: column * frameWidth,
                y: row * frameHeight,
                width: frameWidth,
                height: frameHeight
            )
            if let cropped = sheet.cropping(to: rect) {
                frames.append(cropped)
            }
        }
        return frames
    }

    /// A single opaque 1x1 pixel, used for `SafeDefaultCharacter` so the
    /// fallback path never depends on a sprite file existing on disk.
    public static func safeDefaultFrame() -> CGImage {
        let width = 1
        let height = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(NSColor.systemPink.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    public static func loadFramesOrSafeDefault(
        fileURL: URL,
        frameWidth: Int,
        frameHeight: Int,
        frameCount: Int,
        isSafeDefault: Bool
    ) -> [CGImage] {
        if isSafeDefault {
            return [safeDefaultFrame()]
        }
        let frames = loadFrames(fileURL: fileURL, frameWidth: frameWidth, frameHeight: frameHeight, frameCount: frameCount)
        return frames.isEmpty ? [safeDefaultFrame()] : frames
    }
}
