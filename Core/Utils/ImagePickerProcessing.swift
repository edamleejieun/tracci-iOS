import Foundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

enum ImagePickerProcessingError: LocalizedError {
    case unableToReadImage
    case fileTooLarge(maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .unableToReadImage:
            return "无法读取所选图片，请重新选择"
        case .fileTooLarge(let maxBytes):
            return "图片不能超过 \(maxBytes / (1024 * 1024))MB"
        }
    }
}

struct ProcessedPickerImage {
    let data: Data
    let contentType: String
    let fileName: String
    let width: Int?
    let height: Int?
    let capturedAt: Date?
}

enum ImagePickerProcessing {
    static let maxFileSize = 5 * 1024 * 1024

    static func process(item: PhotosPickerItem, fileNamePrefix: String) async throws -> ProcessedPickerImage {
        guard let rawData = try await item.loadTransferable(type: Data.self) else {
            throw ImagePickerProcessingError.unableToReadImage
        }

        let originalContentType = contentType(from: item)
        let capturedAt = captureDate(from: rawData)
        let prepared = try prepareImageData(rawData, originalContentType: originalContentType)
        let dimensions = imageDimensions(from: prepared.data)

        return ProcessedPickerImage(
            data: prepared.data,
            contentType: prepared.contentType,
            fileName: fileName(prefix: fileNamePrefix, contentType: prepared.contentType),
            width: dimensions?.width,
            height: dimensions?.height,
            capturedAt: capturedAt
        )
    }

    /// Reads EXIF / TIFF capture time from image bytes **before** compression.
    static func captureDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }

        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
           let date = parseEXIFDate(raw) {
            return date
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let raw = tiff[kCGImagePropertyTIFFDateTime] as? String {
            return parseEXIFDate(raw)
        }
        return nil
    }

    static func parseEXIFDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // EXIF 的 DateTimeOriginal 是相机本地墙钟时间、不带时区。
        // 按业务日历（Asia/Shanghai）解释，否则 16:00 后拍摄的照片会被 startOfDay 归到次日。
        formatter.timeZone = TracciDateContext.timeZone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        if let date = formatter.date(from: raw) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: raw)
    }

    // MARK: - Private

    private struct PreparedImageData {
        let data: Data
        let contentType: String
    }

    private static func prepareImageData(_ data: Data, originalContentType: String) throws -> PreparedImageData {
        if data.count <= maxFileSize {
            return PreparedImageData(data: data, contentType: originalContentType)
        }

        let compressed = try compressToMaxSize(data, maxBytes: maxFileSize)
        guard compressed.count <= maxFileSize else {
            throw ImagePickerProcessingError.fileTooLarge(maxBytes: maxFileSize)
        }

        return PreparedImageData(data: compressed, contentType: "image/jpeg")
    }

    private static func contentType(from item: PhotosPickerItem) -> String {
        if let preferred = item.supportedContentTypes.first?.preferredMIMEType {
            return preferred
        }
        return "image/jpeg"
    }

    static func fileName(prefix: String, contentType: String) -> String {
        let fileExtension: String
        switch contentType {
        case "image/png":
            fileExtension = "png"
        case "image/webp":
            fileExtension = "webp"
        case "image/heic":
            fileExtension = "heic"
        case "image/heif":
            fileExtension = "heif"
        case "image/gif":
            fileExtension = "gif"
        case "image/bmp":
            fileExtension = "bmp"
        case "image/tiff":
            fileExtension = "tiff"
        case "image/avif":
            fileExtension = "avif"
        default:
            fileExtension = "jpg"
        }

        return "\(prefix)_\(UUID().uuidString.prefix(8)).\(fileExtension)"
    }

    static func imageDimensions(from data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue

        guard let width, let height else { return nil }
        return (width, height)
    }

    private static func compressToMaxSize(_ data: Data, maxBytes: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImagePickerProcessingError.unableToReadImage
        }

        var maxDimension = 2048
        var quality: CGFloat = 0.85

        while maxDimension >= 720 {
            let resized = resizedImage(image, maxDimension: maxDimension)
            var currentQuality = quality

            while currentQuality >= 0.4 {
                if let jpegData = jpegData(from: resized, quality: currentQuality),
                   jpegData.count <= maxBytes {
                    return jpegData
                }
                currentQuality -= 0.1
            }

            maxDimension = Int(Double(maxDimension) * 0.75)
            quality = 0.8
        }

        throw ImagePickerProcessingError.fileTooLarge(maxBytes: maxBytes)
    }

    private static func resizedImage(_ image: CGImage, maxDimension: Int) -> CGImage {
        let width = image.width
        let height = image.height
        let longest = max(width, height)

        guard longest > maxDimension else { return image }

        let scale = CGFloat(maxDimension) / CGFloat(longest)
        let newWidth = Int(CGFloat(width) * scale)
        let newHeight = Int(CGFloat(height) * scale)

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }

    private static func jpegData(from image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
