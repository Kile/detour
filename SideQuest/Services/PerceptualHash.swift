import UIKit

/// 64-bit difference hash (dHash). Near-identical photos (re-saved, resized, slightly shifted)
/// land within a few bits of each other, so reused photos can be spotted cheaply on-device.
enum PerceptualHash {
    /// Photos within this many differing bits count as near-duplicates.
    static let duplicateThreshold = 6

    static func hash(_ image: UIImage) -> UInt64? {
        guard let cgImage = ImageProcessor.redraw(image, maxLongEdge: 256).cgImage else { return nil }
        return hash(cgImage)
    }

    static func hash(_ cgImage: CGImage) -> UInt64? {
        let width = 9, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var result: UInt64 = 0
        var bit: UInt64 = 0
        for row in 0..<height {
            for column in 0..<(width - 1) {
                if pixels[row * width + column] > pixels[row * width + column + 1] {
                    result |= (1 << bit)
                }
                bit += 1
            }
        }
        return result
    }

    static func distance(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    static func isNearDuplicate(_ hash: UInt64, of others: [UInt64], threshold: Int = duplicateThreshold) -> Bool {
        others.contains { distance(hash, $0) <= threshold }
    }
}
