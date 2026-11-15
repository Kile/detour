import UIKit
import Vision
import CoreML

/// Blurs faces on the device, before a photo is ever sent to an AI provider or saved to history.
/// Uses Apple's Vision framework: face rectangles, plus a head-area fallback for people whose
/// face isn't detected (turned away, partly hidden).
enum FaceRedactor {
    struct Result {
        /// The redacted image, at the size it was given.
        var image: UIImage
        /// Every blurred region, in pixel coordinates (top-left origin).
        var regions: [CGRect]
        var faceCount: Int
        var personCount: Int
        /// Face detection couldn't run. Fail safe: the player must review the photo before sending.
        var detectionFailed = false

        var foundPeople: Bool { faceCount > 0 || personCount > 0 }
        var needsReview: Bool { foundPeople || detectionFailed }
    }

    /// Extra margin around a detected face so hair, ears and jawline are covered too.
    static let facePadding: CGFloat = 0.45

    /// Detects and blurs faces (and the heads of people whose faces weren't found).
    static func redact(_ image: UIImage, extraRegions: [CGRect] = []) -> Result {
        guard let cgImage = image.cgImage else {
            return Result(image: image, regions: [], faceCount: 0, personCount: 0)
        }
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let faceResults = detect(VNDetectFaceRectanglesRequest(), in: cgImage)
        let peopleRequest = VNDetectHumanRectanglesRequest()
        peopleRequest.upperBodyOnly = false
        let peopleResults = detect(peopleRequest, in: cgImage)
        let faces = (faceResults ?? []).map { pixelRect(fromNormalized: $0.boundingBox, in: size) }
        let people = (peopleResults ?? []).filter { $0.confidence > 0.3 }.map { pixelRect(fromNormalized: $0.boundingBox, in: size) }

        var regions = faces.map { padded($0, by: facePadding, within: size) }
        // A person with no detected face: blur the head area at the top of their body box.
        for person in people where !faces.contains(where: { $0.intersects(person) }) {
            let head = CGRect(x: person.minX + person.width * 0.15, y: person.minY,
                              width: person.width * 0.7, height: person.height * 0.42)
            regions.append(head.intersection(CGRect(origin: .zero, size: size)))
        }
        regions += extraRegions

        let redacted = regions.isEmpty ? cgImage : redact(cgImage, regions: regions)
        return Result(image: UIImage(cgImage: redacted), regions: regions, faceCount: faces.count, personCount: people.count,
                      detectionFailed: faceResults == nil)
    }

    /// A circular blur spot the player adds by tapping (for name badges or anything we missed).
    static func spot(at point: CGPoint, in size: CGSize) -> CGRect {
        let radius = max(size.width, size.height) * 0.07
        return CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
            .intersection(CGRect(origin: .zero, size: size))
    }

    // MARK: Detection (normalized Vision coordinates, bottom-left origin)

    static func detectFaces(in cgImage: CGImage) -> [CGRect] {
        (detect(VNDetectFaceRectanglesRequest(), in: cgImage) ?? []).map(\.boundingBox)
    }

    /// Runs a Vision request; returns nil if it couldn't run at all.
    /// The simulator (and occasionally a busy device) can't create the default GPU/Neural Engine
    /// context, so retry on the CPU before giving up.
    static func detect<Request: VNImageBasedRequest, Observation>(_ request: Request, in cgImage: CGImage) -> [Observation]?
        where Request: VNObservationsProviding, Request.ObservationType == Observation {
        if (try? VNImageRequestHandler(cgImage: cgImage).perform([request])) != nil {
            return request.typedResults
        }
        if let cpu = (try? request.supportedComputeStageDevices)?[.main]?.first(where: {
            if case .cpu = $0 { return true } else { return false }
        }) {
            request.setComputeDevice(cpu, for: .main)
            if (try? VNImageRequestHandler(cgImage: cgImage).perform([request])) != nil {
                return request.typedResults
            }
        }
        return nil
    }

    static func pixelRect(fromNormalized rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width, y: (1 - rect.maxY) * size.height,
               width: rect.width * size.width, height: rect.height * size.height)
    }

    static func padded(_ rect: CGRect, by fraction: CGFloat, within size: CGSize) -> CGRect {
        rect.insetBy(dx: -rect.width * fraction, dy: -rect.height * fraction)
            .intersection(CGRect(origin: .zero, size: size))
    }

    // MARK: Redaction

    /// Replaces each region with an irreversible smear: the region is shrunk to a few pixels and
    /// scaled back up, so no facial detail survives.
    static func redact(_ cgImage: CGImage, regions: [CGRect]) -> CGImage {
        let size = CGSize(width: cgImage.width, height: cgImage.height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let ctx = context.cgContext
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            for region in regions where region.width >= 2 && region.height >= 2 {
                let integral = region.integral
                guard let crop = cgImage.cropping(to: integral), let tiny = shrink(crop, longEdge: 6) else { continue }
                ctx.saveGState()
                let corner = min(integral.width, integral.height) * 0.3
                ctx.addPath(UIBezierPath(roundedRect: integral, cornerRadius: corner).cgPath)
                ctx.clip()
                ctx.interpolationQuality = .low
                UIImage(cgImage: tiny).draw(in: integral)
                ctx.restoreGState()
            }
        }
        return rendered.cgImage ?? cgImage
    }

    private static func shrink(_ image: CGImage, longEdge: Int) -> CGImage? {
        let scale = CGFloat(longEdge) / CGFloat(max(image.width, image.height))
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }
}

/// Typed access to a Vision request's observations.
protocol VNObservationsProviding {
    associatedtype ObservationType
    var typedResults: [ObservationType] { get }
}

extension VNDetectFaceRectanglesRequest: VNObservationsProviding {
    var typedResults: [VNFaceObservation] { results ?? [] }
}

extension VNDetectHumanRectanglesRequest: VNObservationsProviding {
    var typedResults: [VNHumanObservation] { results ?? [] }
}
