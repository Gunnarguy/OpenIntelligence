import Foundation

/// Office fixtures, synthesised rather than committed.
///
/// `.docx` and `.xlsx` are ZIP packages of XML, and the reader in `DocumentProcessor` accepts
/// entries stored uncompressed (`compressionMethod == 0`). So a store-only ZIP writer is enough to
/// build a real, parseable Office document in the test itself — no binary blobs, no
/// `project.pbxproj` change to make them bundle resources, and no dependency on LibreOffice being
/// installed on whichever machine runs the suite.
///
/// The XML here is the markup Word and Excel actually emit for a table, not a shape invented to
/// satisfy the parser. If the extractor's regexes change, these fixtures should break.
extension IngestionFixtureFactory {

    /// A `.docx` whose body is a caption paragraph, a real `<w:tbl>`, and the prose paragraphs.
    func docx(_ spec: TableSpec = IngestionFixtureFactory.serviceTable) throws -> URL {
        let rows = spec.allRows.map { row in
            let cells = row.map { cell in
                """
                <w:tc><w:tcPr><w:tcW w:w="2000" w:type="dxa"/></w:tcPr>\
                <w:p><w:r><w:t>\(Self.xmlEscaped(cell))</w:t></w:r></w:p></w:tc>
                """
            }.joined()
            return "<w:tr>\(cells)</w:tr>"
        }.joined()

        let proseParagraphs = spec.prose.map { line in
            "<w:p><w:r><w:t>\(Self.xmlEscaped(line))</w:t></w:r></w:p>"
        }.joined()

        let document = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        <w:body>
        <w:p><w:r><w:t>\(Self.xmlEscaped(spec.caption))</w:t></w:r></w:p>
        <w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/></w:tblPr>\(rows)</w:tbl>
        \(proseParagraphs)
        </w:body>
        </w:document>
        """

        let destination = fixtureURL("torque_specification.docx")
        try StoredZipWriter.write(
            entries: [
                .init(path: "[Content_Types].xml", contents: Self.wordContentTypes),
                .init(path: "_rels/.rels", contents: Self.packageRelationships(target: "word/document.xml")),
                .init(path: "word/document.xml", contents: document)
            ],
            to: destination
        )
        return destination
    }

    /// An `.xlsx` with one worksheet, text cells resolved through `xl/sharedStrings.xml`.
    func xlsx(_ spec: TableSpec = IngestionFixtureFactory.serviceTable) throws -> URL {
        // Every distinct cell string, in first-appearance order. Sheet cells reference these by
        // index, which is exactly how Excel stores text.
        var sharedStrings: [String] = []
        var indexOf: [String: Int] = [:]
        for cell in spec.allRows.flatMap({ $0 }) where indexOf[cell] == nil {
            indexOf[cell] = sharedStrings.count
            sharedStrings.append(cell)
        }

        let sst = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
        count="\(sharedStrings.count)" uniqueCount="\(sharedStrings.count)">\
        \(sharedStrings.map { "<si><t>\(Self.xmlEscaped($0))</t></si>" }.joined())\
        </sst>
        """

        let columnNames = ["A", "B", "C", "D", "E", "F"]
        let sheetRows = spec.allRows.enumerated().map { rowIndex, row in
            let cells = row.enumerated().map { columnIndex, cell in
                let reference = "\(columnNames[min(columnIndex, columnNames.count - 1)])\(rowIndex + 1)"
                return "<c r=\"\(reference)\" t=\"s\"><v>\(indexOf[cell] ?? 0)</v></c>"
            }.joined()
            return "<row r=\"\(rowIndex + 1)\">\(cells)</row>"
        }.joined()

        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetData>\(sheetRows)</sheetData>
        </worksheet>
        """

        let destination = fixtureURL("torque_specification.xlsx")
        try StoredZipWriter.write(
            entries: [
                .init(path: "[Content_Types].xml", contents: Self.excelContentTypes),
                .init(path: "_rels/.rels", contents: Self.packageRelationships(target: "xl/workbook.xml")),
                .init(path: "xl/sharedStrings.xml", contents: sst),
                .init(path: "xl/worksheets/sheet1.xml", contents: sheet)
            ],
            to: destination
        )
        return destination
    }

    // MARK: - Package boilerplate
    //
    // `DocumentProcessor` reads only the content parts, never these. They are here so the fixture is
    // a well-formed OOXML package rather than a ZIP that happens to contain one XML file.

    private static let wordContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/word/document.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let excelContentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/sharedStrings.xml" \
    ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
    </Types>
    """

    private static func packageRelationships(target: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Target="\(target)" \
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"/>
        </Relationships>
        """
    }

    static func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// Minimal ZIP writer that stores entries uncompressed.
///
/// Deliberately store-only. Deflating would add a compression dependency to the test target for no
/// benefit: `DocumentProcessor`'s reader handles `compressionMethod == 0` directly, and these
/// fixtures are a few kilobytes.
enum StoredZipWriter {

    struct Entry {
        let path: String
        let data: Data

        init(path: String, data: Data) {
            self.path = path
            self.data = data
        }

        init(path: String, contents: String) {
            self.init(path: path, data: Data(contents.utf8))
        }
    }

    static func write(entries: [Entry], to destination: URL) throws {
        var archive = Data()
        var directory = Data()
        var offsets: [UInt32] = []

        for entry in entries {
            offsets.append(UInt32(archive.count))
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)

            archive.append(le32: 0x0403_4B50)               // local file header signature
            archive.append(le16: 20)                        // version needed to extract
            archive.append(le16: 0)                         // general purpose flags
            archive.append(le16: 0)                         // method: stored
            archive.append(le16: 0)                         // modification time
            archive.append(le16: 0x21)                      // modification date: 1980-01-01
            archive.append(le32: crc)
            archive.append(le32: UInt32(entry.data.count))  // compressed size
            archive.append(le32: UInt32(entry.data.count))  // uncompressed size
            archive.append(le16: UInt16(name.count))
            archive.append(le16: 0)                         // extra field length
            archive.append(name)
            archive.append(entry.data)
        }

        for (index, entry) in entries.enumerated() {
            let name = Data(entry.path.utf8)
            directory.append(le32: 0x0201_4B50)             // central directory signature
            directory.append(le16: 20)                      // version made by
            directory.append(le16: 20)                      // version needed
            directory.append(le16: 0)                       // flags
            directory.append(le16: 0)                       // method: stored
            directory.append(le16: 0)                       // modification time
            directory.append(le16: 0x21)                    // modification date
            directory.append(le32: crc32(entry.data))
            directory.append(le32: UInt32(entry.data.count))
            directory.append(le32: UInt32(entry.data.count))
            directory.append(le16: UInt16(name.count))
            directory.append(le16: 0)                       // extra field length
            directory.append(le16: 0)                       // comment length
            directory.append(le16: 0)                       // disk number start
            directory.append(le16: 0)                       // internal attributes
            directory.append(le32: 0)                       // external attributes
            directory.append(le32: offsets[index])
            directory.append(name)
        }

        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.append(le32: 0x0605_4B50)                   // end of central directory signature
        archive.append(le16: 0)                             // this disk
        archive.append(le16: 0)                             // disk with central directory
        archive.append(le16: UInt16(entries.count))
        archive.append(le16: UInt16(entries.count))
        archive.append(le32: UInt32(directory.count))
        archive.append(le32: directoryOffset)
        archive.append(le16: 0)                             // comment length

        try archive.write(to: destination)
    }

    private static let crcTable: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        // Qualified: inside a `Data` extension, the bare name resolves to `Data.withUnsafeBytes`.
        append(contentsOf: Swift.withUnsafeBytes(of: value.littleEndian, Array.init))
    }

    mutating func append(le32 value: UInt32) {
        // Qualified: inside a `Data` extension, the bare name resolves to `Data.withUnsafeBytes`.
        append(contentsOf: Swift.withUnsafeBytes(of: value.littleEndian, Array.init))
    }
}
