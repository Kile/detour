import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import SideQuest

final class KeychainStoreTests: XCTestCase {
    let store = KeychainStore(service: "dev.sidequest.tests.\(UUID().uuidString)")

    override func tearDown() {
        try? store.delete(account: "key")
        super.tearDown()
    }

    func testSetGetUpdateDelete() throws {
        XCTAssertNil(try store.get(account: "key"))
        try store.set("sk-ant-first", account: "key")
        XCTAssertEqual(try store.get(account: "key"), "sk-ant-first")
        try store.set("sk-ant-second", account: "key")
        XCTAssertEqual(try store.get(account: "key"), "sk-ant-second")
        try store.delete(account: "key")
        XCTAssertNil(try store.get(account: "key"))
        XCTAssertNoThrow(try store.delete(account: "key"))  // deleting twice is fine
    }

    func testServicesAreIsolated() throws {
        let other = KeychainStore(service: store.service + ".other")
        try store.set("a", account: "key")
        XCTAssertNil(try other.get(account: "key"))
    }

    func testKeyFormatAndMasking() {
        XCTAssertTrue(APIKeyStore.looksLikeClaudeKey("sk-ant-api03-abcdefghijklmnop"))
        XCTAssertTrue(APIKeyStore.looksLikeClaudeKey("  sk-ant-api03-abcdefghijklmnop\n"))
        XCTAssertFalse(APIKeyStore.looksLikeClaudeKey("sk-1234567890abcdefghij"))
        XCTAssertFalse(APIKeyStore.looksLikeClaudeKey("sk-ant-"))
        XCTAssertFalse(APIKeyStore.looksLikeClaudeKey("sk-ant-has a space in it 123"))
        XCTAssertEqual(APIKeyStore.masked("sk-ant-api03-abcdefghijWXYZ"), "sk-ant-…WXYZ")
    }

    func testAPIKeyIsNotInUserDefaults() {
        let everything = UserDefaults.standard.dictionaryRepresentation().values.compactMap { $0 as? String }
        XCTAssertFalse(everything.contains { $0.hasPrefix("sk-ant-") })
    }
}

final class ImageProcessingTests: XCTestCase {
    func makeImage(width: Int, height: Int, pattern: Int = 0) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let colors: [UIColor] = pattern == 0 ? [.red, .blue, .green, .orange] : [.black, .yellow, .purple, .cyan]
            for (i, color) in colors.enumerated() {
                color.setFill()
                let w = CGFloat(width) / 4
                let rect = pattern == 0
                    ? CGRect(x: CGFloat(i) * w, y: CGFloat(i) * CGFloat(height) / 8, width: w, height: CGFloat(height) / 2)
                    : CGRect(x: CGFloat(width) - CGFloat(i + 1) * w, y: CGFloat(height) / 2, width: w * 0.6, height: CGFloat(height) / 3)
                context.fill(rect)
            }
        }
    }

    /// A JPEG carrying GPS coordinates and camera EXIF, like a real phone photo.
    func jpegWithLocation(_ image: UIImage) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5194, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 0.1270, kCGImagePropertyGPSLongitudeRef: "W"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:14 12:00:00"],
        ]
        CGImageDestinationAddImage(destination, image.cgImage!, properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    func testTargetSize() {
        XCTAssertEqual(ImageProcessor.targetSize(for: CGSize(width: 4032, height: 3024), maxLongEdge: 1500), CGSize(width: 1500, height: 1125))
        XCTAssertEqual(ImageProcessor.targetSize(for: CGSize(width: 3024, height: 4032), maxLongEdge: 1500), CGSize(width: 1125, height: 1500))
        XCTAssertEqual(ImageProcessor.targetSize(for: CGSize(width: 800, height: 600), maxLongEdge: 1500), CGSize(width: 800, height: 600))
    }

    func testUploadIsResizedAndStrippedOfLocation() throws {
        let original = jpegWithLocation(makeImage(width: 4032, height: 3024))
        XCTAssertTrue(ImageProcessor.containsSensitiveMetadata(original), "Fixture should carry GPS/EXIF")

        let image = try XCTUnwrap(UIImage(data: original))
        let upload = try XCTUnwrap(ImageProcessor.prepareForUpload(image))
        XCTAssertFalse(ImageProcessor.containsSensitiveMetadata(upload))

        let source = try XCTUnwrap(CGImageSourceCreateWithData(upload as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 1500)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 1125)
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.jpeg.identifier)
    }

    func testThumbnailIsSmall() throws {
        let thumb = try XCTUnwrap(ImageProcessor.thumbnail(makeImage(width: 3000, height: 2000)))
        let image = try XCTUnwrap(UIImage(data: thumb))
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), AIConfig.thumbnailLongEdge)
    }
}

final class PerceptualHashTests: XCTestCase {
    let helper = ImageProcessingTests()

    func testSameImageHashesIdentically() throws {
        let image = helper.makeImage(width: 800, height: 600)
        let a = try XCTUnwrap(PerceptualHash.hash(image))
        let b = try XCTUnwrap(PerceptualHash.hash(image))
        XCTAssertEqual(PerceptualHash.distance(a, b), 0)
    }

    func testResizedRecompressedCopyIsNearDuplicate() throws {
        let image = helper.makeImage(width: 1600, height: 1200)
        let copy = try XCTUnwrap(UIImage(data: try XCTUnwrap(ImageProcessor.strippedJPEG(ImageProcessor.redraw(image, maxLongEdge: 500), quality: 0.4))))
        let a = try XCTUnwrap(PerceptualHash.hash(image))
        let b = try XCTUnwrap(PerceptualHash.hash(copy))
        XCTAssertTrue(PerceptualHash.isNearDuplicate(b, of: [a]), "distance \(PerceptualHash.distance(a, b))")
    }

    func testDifferentImagesAreNotDuplicates() throws {
        let a = try XCTUnwrap(PerceptualHash.hash(helper.makeImage(width: 800, height: 600, pattern: 0)))
        let b = try XCTUnwrap(PerceptualHash.hash(helper.makeImage(width: 800, height: 600, pattern: 1)))
        XCTAssertFalse(PerceptualHash.isNearDuplicate(b, of: [a]), "distance \(PerceptualHash.distance(a, b))")
    }

    func testBundledTestPhotosAreDistinct() throws {
        let hashes = try TestPhotoPicker.samples.map { sample -> UInt64 in
            let image = try XCTUnwrap(UIImage(named: sample.file), "Missing \(sample.file)")
            return try XCTUnwrap(PerceptualHash.hash(image))
        }
        for i in hashes.indices {
            for j in hashes.indices where j > i {
                XCTAssertGreaterThan(PerceptualHash.distance(hashes[i], hashes[j]), PerceptualHash.duplicateThreshold)
            }
        }
    }
}
