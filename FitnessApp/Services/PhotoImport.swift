import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Внос на снимки: дата от EXIF и смаляване до ~1600 px JPEG.
enum PhotoImport {
    static func prepare(_ data: Data, fallbackDate: Date) -> (data: Data, thumb: Data, date: Date)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let date = exifDate(source) ?? fallbackDate
        guard let jpeg = scaled(source, maxPixels: 1600, quality: 0.8),
              let thumb = scaled(source, maxPixels: 400, quality: 0.7) else { return nil }
        return (jpeg, thumb, date)
    }

    /// Смалена версия за изпращане към AI.
    static func downscaled(_ data: Data, maxPixels: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return scaled(source, maxPixels: maxPixels, quality: 0.7)
    }

    private static func scaled(_ source: CGImageSource, maxPixels: Int, quality: CGFloat) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }

    private static func exifDate(_ source: CGImageSource) -> Date? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        guard let text = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
                ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    /// Всички снимки в папка (и подпапки) с дата на файла като резерва.
    static func filesInFolder(_ folder: URL) -> [(url: URL, created: Date)] {
        let keys: [URLResourceKey] = [.contentTypeKey, .creationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return [] }
        var result: [(url: URL, created: Date)] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let type = values.contentType, type.conforms(to: .image) else { continue }
            result.append((url: url, created: values.creationDate ?? .now))
        }
        return result
    }
}
