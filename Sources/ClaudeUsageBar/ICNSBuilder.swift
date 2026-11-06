import Foundation

/// Packs an `.iconset` folder into an `.icns` file without `iconutil`.
enum ICNSBuilder {
    private static let representations: [(type: String, filename: String)] = [
        ("icp4", "icon_16x16.png"),
        ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png")
    ]

    static func create(from iconsetURL: URL, outputURL: URL) throws {
        var body = Data()

        for representation in representations {
            let image = try Data(contentsOf: iconsetURL.appendingPathComponent(representation.filename))
            guard let type = representation.type.data(using: .ascii), type.count == 4 else {
                throw UsageError.iconRender("invalid ICNS representation type")
            }
            body.append(type)
            body.appendBigEndian(UInt32(image.count + 8))
            body.append(image)
        }

        var file = Data("icns".utf8)
        file.appendBigEndian(UInt32(body.count + 8))
        file.append(body)
        try file.write(to: outputURL, options: .atomic)
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }
}
