//
//  PhotoMetadataReader.swift
//  ShutterManager
//
//  Reads camera and lens details from a photo's metadata (EXIF, TIFF and maker notes).
//

import Foundation
import ImageIO

/// What a photo's metadata says about the camera and lens that took it.
///
/// Standard EXIF gives the body and lens identity. The shutter count is only in some makers'
/// notes, and ImageIO exposes it for Nikon; for other brands it's nil and is entered by hand.
/// Everything is optional: the user reviews what was found before any of it is used.
struct CameraPhotoMetadata: Equatable {
    var cameraMake: String?
    var cameraModel: String?
    var bodySerialNumber: String?
    var firmware: String?
    var lensMake: String?
    var lensModel: String?
    var lensSerialNumber: String?
    /// The lens's focal range and maximum apertures (wide end, long end) from its specification.
    var lensFocalLengthMin: Double?
    var lensFocalLengthMax: Double?
    var lensMaxApertureWide: Double?
    var lensMaxApertureTele: Double?
    var shutterCount: Int?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var dateTaken: Date?

    var hasCameraDetails: Bool {
        cameraModel != nil || bodySerialNumber != nil || firmware != nil || shutterCount != nil
    }

    var hasLensDetails: Bool {
        lensModel != nil || lensSerialNumber != nil || lensFocalLengthMin != nil || lensMaxApertureWide != nil
    }

    var isEmpty: Bool { !hasCameraDetails && !hasLensDetails && cameraMake == nil }

    init() {}

    // MARK: - Parsing

    /// Parses an image properties dictionary, as `CGImageSourceCopyPropertiesAtIndex` returns it.
    init(properties: [String: Any]) {
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let aux = properties[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]
        let nikon = properties[kCGImagePropertyMakerNikonDictionary as String] as? [String: Any] ?? [:]
        let canon = properties[kCGImagePropertyMakerCanonDictionary as String] as? [String: Any] ?? [:]

        let rawMake = Self.text(tiff[kCGImagePropertyTIFFMake as String])
        cameraMake = rawMake.map(Self.displayMake)
        cameraModel = Self.text(tiff[kCGImagePropertyTIFFModel as String]).map { Self.model($0, droppingMake: rawMake) }
        bodySerialNumber = Self.text(exif[kCGImagePropertyExifBodySerialNumber as String])
            ?? Self.text(aux[kCGImagePropertyExifAuxSerialNumber as String])
            ?? Self.text(nikon[kCGImagePropertyMakerNikonCameraSerialNumber as String])
            ?? Self.text(canon[kCGImagePropertyMakerCanonCameraSerialNumber as String])
        firmware = Self.text(aux[kCGImagePropertyExifAuxFirmware as String])
            ?? Self.text(canon[kCGImagePropertyMakerCanonFirmware as String])
            ?? Self.text(tiff[kCGImagePropertyTIFFSoftware as String])

        lensMake = Self.text(exif[kCGImagePropertyExifLensMake as String]).map(Self.displayMake)
        lensModel = Self.text(exif[kCGImagePropertyExifLensModel as String])
            ?? Self.text(aux[kCGImagePropertyExifAuxLensModel as String])
            ?? Self.text(canon[kCGImagePropertyMakerCanonLensModel as String])
        lensSerialNumber = Self.text(exif[kCGImagePropertyExifLensSerialNumber as String])
            ?? Self.text(aux[kCGImagePropertyExifAuxLensSerialNumber as String])

        // [shortest focal length, longest, max aperture at shortest, max aperture at longest];
        // 0 means unknown.
        let specification = Self.numbers(exif[kCGImagePropertyExifLensSpecification as String])
            ?? Self.numbers(aux[kCGImagePropertyExifAuxLensInfo as String]) ?? []
        if specification.count == 4 {
            lensFocalLengthMin = Self.positive(specification[0])
            lensFocalLengthMax = Self.positive(specification[1])
            lensMaxApertureWide = Self.positive(specification[2])
            lensMaxApertureTele = Self.positive(specification[3])
        }

        shutterCount = Self.number(nikon[kCGImagePropertyMakerNikonShutterCount as String])
            .flatMap { $0 > 0 && $0 <= Constants.DataLimits.maximumCount ? Int($0) : nil }

        pixelWidth = Self.number(exif[kCGImagePropertyExifPixelXDimension as String]).flatMap(Self.pixels)
            ?? Self.number(properties[kCGImagePropertyPixelWidth as String]).flatMap(Self.pixels)
        pixelHeight = Self.number(exif[kCGImagePropertyExifPixelYDimension as String]).flatMap(Self.pixels)
            ?? Self.number(properties[kCGImagePropertyPixelHeight as String]).flatMap(Self.pixels)
        dateTaken = Self.text(exif[kCGImagePropertyExifDateTimeOriginal as String]).flatMap(Self.exifDate)
    }

    /// A trimmed, non-empty string from a metadata value (EXIF text often ends in spaces or NULs).
    private static func text(_ value: Any?) -> String? {
        let raw: String?
        switch value {
        case let string as String: raw = string
        case let number as NSNumber: raw = number.stringValue
        default: raw = nil
        }
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue.isFinite ? number.doubleValue : nil
        case let string as String: return Double(string.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    private static func numbers(_ value: Any?) -> [Double]? {
        guard let array = value as? [Any] else { return nil }
        let values = array.compactMap(number)
        return values.count == array.count ? values : nil
    }

    private static func positive(_ value: Double) -> Double? {
        value > 0 && value <= Constants.DataLimits.maximumMeasurement ? value : nil
    }

    private static func pixels(_ value: Double) -> Int? {
        value > 0 && value <= 1_000_000 ? Int(value) : nil
    }

    private static func exifDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }

    /// Cameras write their maker's legal name ("NIKON CORPORATION"); show the brand.
    static func displayMake(_ make: String) -> String {
        let brands: [(prefix: String, name: String)] = [
            ("nikon", "Nikon"), ("canon", "Canon"), ("sony", "Sony"), ("fujifilm", "Fujifilm"),
            ("olympus", "Olympus"), ("om digital", "OM System"), ("panasonic", "Panasonic"),
            ("leica", "Leica"), ("ricoh", "Ricoh"), ("pentax", "Pentax"), ("hasselblad", "Hasselblad"),
            ("sigma", "Sigma"), ("tamron", "Tamron"), ("dji", "DJI"), ("apple", "Apple"), ("gopro", "GoPro")
        ]
        let lowered = make.lowercased()
        return brands.first { lowered.hasPrefix($0.prefix) }?.name ?? make
    }

    /// The model without a repeated brand: "Canon EOS R5" from make "Canon" becomes "EOS R5".
    static func model(_ model: String, droppingMake make: String?) -> String {
        guard let make else { return model }
        let brand = displayMake(make)
        for prefix in [make, brand] where !prefix.isEmpty {
            if model.lowercased().hasPrefix(prefix.lowercased() + " ") {
                return String(model.dropFirst(prefix.count + 1))
            }
        }
        return model
    }
}

/// Reads `CameraPhotoMetadata` from image data with ImageIO.
enum PhotoMetadataReader {
    /// The metadata in `data`, or nil when it isn't an image ImageIO can read. Must be given the
    /// picked original: `PhotoIngest` re-encodes photos for storage and drops their metadata.
    static func read(_ data: Data) -> CameraPhotoMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }
        return CameraPhotoMetadata(properties: properties)
    }
}
