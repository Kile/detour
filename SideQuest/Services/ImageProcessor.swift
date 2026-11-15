import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Prepares photos before they leave the device: resized to ~1,500 px on the long edge and
/// re-encoded from raw pixels, so no EXIF/GPS metadata from the camera survives.
enum ImageProcessor {
    static func targetSize(for size: CGSize, maxLongEdge: CGFloat) -> CGSize {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge, longEdge > 0 else {
            return CGSize(width: size.width.rounded(), height: size.height.rounded())
        }
        let scale = maxLongEdge / longEdge
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// Redraws the image (applying its orientation) into a fresh bitmap at the target size.
    static func redraw(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = targetSize(for: image.size, maxLongEdge: maxLongEdge)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// JPEG data with no metadata other than what ImageIO needs to describe the pixels.
    static func strippedJPEG(_ image: UIImage, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The upload payload for the vision model.
    static func prepareForUpload(_ image: UIImage) -> Data? {
        strippedJPEG(redraw(image, maxLongEdge: AIConfig.maxImageLongEdge), quality: AIConfig.jpegQuality)
    }

    /// Small JPEG for quest history.
    static func thumbnail(_ image: UIImage) -> Data? {
        strippedJPEG(redraw(image, maxLongEdge: AIConfig.thumbnailLongEdge), quality: 0.7)
    }

    /// True if the JPEG carries GPS or camera EXIF details (used by tests and the debug screen).
    static func containsSensitiveMetadata(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        if properties[kCGImagePropertyGPSDictionary] != nil { return true }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           tiff[kCGImagePropertyTIFFMake] != nil || tiff[kCGImagePropertyTIFFModel] != nil { return true }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           exif[kCGImagePropertyExifDateTimeOriginal] != nil || exif[kCGImagePropertyExifLensModel] != nil
            || exif[kCGImagePropertyExifUserComment] != nil { return true }
        return false
    }
}
