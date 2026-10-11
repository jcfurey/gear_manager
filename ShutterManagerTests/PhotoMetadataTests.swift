//
//  PhotoMetadataTests.swift
//  ShutterManagerTests
//
//  Reading camera and lens details from photo metadata, and what the import sheet offers.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit
import Testing
@testable import ShutterManager

@MainActor
struct PhotoMetadataTests {
    private func key(_ key: CFString) -> String { key as String }

    @Test func nikonMakerNotesGiveTheShutterCount() {
        let properties: [String: Any] = [
            key(kCGImagePropertyTIFFDictionary): [
                key(kCGImagePropertyTIFFMake): "NIKON CORPORATION",
                key(kCGImagePropertyTIFFModel): "NIKON Z 6_3",
                key(kCGImagePropertyTIFFSoftware): "Ver.01.10 "
            ],
            key(kCGImagePropertyExifDictionary): [
                key(kCGImagePropertyExifBodySerialNumber): "3001234\0",
                key(kCGImagePropertyExifLensModel): "NIKKOR Z 24-70mm f/2.8 S",
                key(kCGImagePropertyExifLensSpecification): [24, 70, 2.8, 2.8],
                key(kCGImagePropertyExifPixelXDimension): 6048,
                key(kCGImagePropertyExifPixelYDimension): 4032,
                key(kCGImagePropertyExifDateTimeOriginal): "2026:09:30 14:05:00"
            ],
            key(kCGImagePropertyMakerNikonDictionary): [
                key(kCGImagePropertyMakerNikonShutterCount): 18_543
            ]
        ]
        let metadata = CameraPhotoMetadata(properties: properties)
        #expect(metadata.cameraMake == "Nikon")
        #expect(metadata.cameraModel == "Z 6_3")
        #expect(metadata.bodySerialNumber == "3001234")
        #expect(metadata.firmware == "Ver.01.10")
        #expect(metadata.shutterCount == 18_543)
        #expect(metadata.lensModel == "NIKKOR Z 24-70mm f/2.8 S")
        #expect(metadata.lensFocalLengthMin == 24)
        #expect(metadata.lensFocalLengthMax == 70)
        #expect(metadata.lensMaxApertureWide == 2.8)
        #expect(metadata.pixelWidth == 6048)
        #expect(metadata.dateTaken != nil)
        #expect(metadata.hasCameraDetails)
        #expect(metadata.hasLensDetails)
    }

    @Test func canonMakerNotesFillTheGaps() {
        let properties: [String: Any] = [
            key(kCGImagePropertyTIFFDictionary): [
                key(kCGImagePropertyTIFFMake): "Canon",
                key(kCGImagePropertyTIFFModel): "Canon EOS R5"
            ],
            key(kCGImagePropertyMakerCanonDictionary): [
                key(kCGImagePropertyMakerCanonCameraSerialNumber): "012345678901",
                key(kCGImagePropertyMakerCanonFirmware): "Firmware Version 2.0.0",
                key(kCGImagePropertyMakerCanonLensModel): "RF24-105mm F4 L IS USM"
            ]
        ]
        let metadata = CameraPhotoMetadata(properties: properties)
        #expect(metadata.cameraMake == "Canon")
        #expect(metadata.cameraModel == "EOS R5")
        #expect(metadata.bodySerialNumber == "012345678901")
        #expect(metadata.firmware == "Firmware Version 2.0.0")
        #expect(metadata.lensModel == "RF24-105mm F4 L IS USM")
        #expect(metadata.shutterCount == nil, "Only Nikon's maker notes carry a shutter count ImageIO exposes")
    }

    @Test func unknownLensSpecificationValuesStayUnset() {
        let properties: [String: Any] = [
            key(kCGImagePropertyExifDictionary): [key(kCGImagePropertyExifLensSpecification): [35, 35, 0, 0]]
        ]
        let metadata = CameraPhotoMetadata(properties: properties)
        #expect(metadata.lensFocalLengthMin == 35)
        #expect(metadata.lensMaxApertureWide == nil)
    }

    @Test func emptyPropertiesAreEmpty() {
        #expect(CameraPhotoMetadata(properties: [:]).isEmpty)
    }

    @Test func brandsAreTidied() {
        #expect(CameraPhotoMetadata.displayMake("NIKON CORPORATION") == "Nikon")
        #expect(CameraPhotoMetadata.displayMake("FUJIFILM") == "Fujifilm")
        #expect(CameraPhotoMetadata.displayMake("OM Digital Solutions") == "OM System")
        #expect(CameraPhotoMetadata.displayMake("Zenit") == "Zenit")
        #expect(CameraPhotoMetadata.model("SONY ILCE-7M4", droppingMake: "SONY") == "ILCE-7M4")
        #expect(CameraPhotoMetadata.model("X-T5", droppingMake: "FUJIFILM") == "X-T5")
    }

    /// End to end through ImageIO: write a JPEG with EXIF, read it back.
    @Test func readsMetadataFromARealJPEG() throws {
        let data = try Self.jpeg(properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "FUJIFILM", kCGImagePropertyTIFFModel: "X-T5"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifBodySerialNumber: "5AB12345",
                                             kCGImagePropertyExifLensModel: "XF23mmF1.4 R LM WR"]
        ])
        let metadata = try #require(PhotoMetadataReader.read(data))
        #expect(metadata.cameraMake == "Fujifilm")
        #expect(metadata.cameraModel == "X-T5")
        #expect(metadata.bodySerialNumber == "5AB12345")
        #expect(metadata.lensModel == "XF23mmF1.4 R LM WR")
    }

    @Test func notAnImageReadsAsNil() {
        #expect(PhotoMetadataReader.read(Data("not an image".utf8)) == nil)
    }

    // MARK: - Applying to a draft

    @Test func cameraFindingsFillABody() {
        var metadata = CameraPhotoMetadata()
        metadata.cameraMake = "Nikon"
        metadata.cameraModel = "Z8"
        metadata.bodySerialNumber = "4000001"
        metadata.firmware = "2.01"
        metadata.pixelWidth = 8256
        metadata.pixelHeight = 5504
        metadata.shutterCount = 1234
        let item = GearItem(category: .other)
        let findings = PhotoMetadataImportView.findings(in: metadata, for: .camera)
        #expect(findings.map(\.id) == ["make", "model", "serial", "firmware", "resolution", "shutterCount"])
        findings.forEach { $0.apply(item) }
        #expect(item.make == "Nikon")
        #expect(item.model == "Z8")
        #expect(item.serialNumber == "4000001")
        #expect(item.firmwareVersion == "2.01")
        #expect(item.resolutionWidthPx == 8256)
    }

    @Test func lensFindingsFillALens() {
        var metadata = CameraPhotoMetadata()
        metadata.lensMake = "Sigma"
        metadata.lensModel = "18-50mm F2.8 DC DN | C"
        metadata.lensFocalLengthMin = 18
        metadata.lensFocalLengthMax = 50
        metadata.lensMaxApertureWide = 2.8
        let item = GearItem(category: .lens)
        let findings = PhotoMetadataImportView.findings(in: metadata, for: .lens)
        #expect(findings.map(\.id) == ["lensMake", "lensModel", "focal", "aperture"])
        findings.forEach { $0.apply(item) }
        #expect(item.make == "Sigma")
        #expect(item.focalLengthText == "18–50 mm")
        #expect(item.maxApertureText == "f/2.8")
    }

    static func jpeg(properties: [CFString: Any]) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let cgImage = try #require(image.cgImage)
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
