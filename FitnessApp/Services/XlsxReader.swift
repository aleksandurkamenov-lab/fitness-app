import Foundation
import Compression

/// Минимален четец на .xlsx (zip + XML) без външни библиотеки: стойностите на клетките от един лист.
final class XlsxWorkbook {
    enum Cell {
        case text(String)
        case number(Double)
    }

    struct Sheet {
        var cells: [Int: [Int: Cell]] = [:]
        var maxRow = 0
        var maxCol = 0

        func text(_ row: Int, _ col: Int) -> String? {
            if case .text(let value)? = cells[row]?[col] { return value }
            return nil
        }

        func number(_ row: Int, _ col: Int) -> Double? {
            if case .number(let value)? = cells[row]?[col] { return value }
            return nil
        }
    }

    enum ReadError: LocalizedError {
        case notXlsx
        case missingSheet

        var errorDescription: String? {
            switch self {
            case .notXlsx: "Файлът не е валиден .xlsx."
            case .missingSheet: "Не намирам този лист във файла."
            }
        }
    }

    private struct Entry {
        var method: Int
        var compressedSize: Int
        var size: Int
        var localOffset: Int
    }

    private let bytes: [UInt8]
    private var entries: [String: Entry] = [:]
    private var sheetPaths: [(name: String, path: String)] = []
    private var sharedStrings: [String] = []

    var sheetNames: [String] { sheetPaths.map(\.name) }

    init(url: URL) throws {
        bytes = [UInt8](try Data(contentsOf: url))
        try readDirectory()
        try readWorkbook()
    }

    // MARK: Zip

    private func u16(_ offset: Int) -> Int {
        Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
    }

    private func u32(_ offset: Int) -> Int {
        u16(offset) | u16(offset + 2) << 16
    }

    private func readDirectory() throws {
        guard bytes.count > 22 else { throw ReadError.notXlsx }
        var end = bytes.count - 22
        while end >= 0, u32(end) != 0x06054b50 { end -= 1 }
        guard end >= 0 else { throw ReadError.notXlsx }
        let count = u16(end + 10)
        var offset = u32(end + 16)
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(offset) == 0x02014b50 else { throw ReadError.notXlsx }
            let nameLength = u16(offset + 28)
            let extraLength = u16(offset + 30)
            let commentLength = u16(offset + 32)
            let nameBytes = bytes[(offset + 46)..<(offset + 46 + nameLength)]
            let name = String(decoding: nameBytes, as: UTF8.self)
            entries[name] = Entry(
                method: u16(offset + 10),
                compressedSize: u32(offset + 20),
                size: u32(offset + 24),
                localOffset: u32(offset + 42)
            )
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    private func file(_ name: String) -> Data? {
        guard let entry = entries[name], u32(entry.localOffset) == 0x04034b50 else { return nil }
        let start = entry.localOffset + 30 + u16(entry.localOffset + 26) + u16(entry.localOffset + 28)
        let end = start + entry.compressedSize
        guard end <= bytes.count else { return nil }
        let raw = bytes[start..<end]
        if entry.method == 0 { return Data(raw) }
        guard entry.method == 8 else { return nil }
        if entry.size == 0 { return Data() }
        var output = [UInt8](repeating: 0, count: entry.size)
        let written = raw.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { target in
                compression_decode_buffer(target.baseAddress!, entry.size, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == entry.size ? Data(output) : nil
    }

    // MARK: Workbook

    private func readWorkbook() throws {
        guard let workbook = file("xl/workbook.xml"), let rels = file("xl/_rels/workbook.xml.rels") else {
            throw ReadError.notXlsx
        }
        let targets = RelationshipParser.parse(rels)
        for sheet in SheetListParser.parse(workbook) {
            guard var path = targets[sheet.relId] else { continue }
            path = path.hasPrefix("/") ? String(path.dropFirst()) : "xl/" + path
            sheetPaths.append((sheet.name, path))
        }
        if let shared = file("xl/sharedStrings.xml") {
            sharedStrings = SharedStringsParser.parse(shared)
        }
    }

    func sheet(named name: String) throws -> Sheet {
        guard let path = sheetPaths.first(where: { $0.name == name })?.path, let data = file(path) else {
            throw ReadError.missingSheet
        }
        return CellsParser.parse(data, shared: sharedStrings)
    }
}

// MARK: XML parsers

private final class RelationshipParser: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelationshipParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.targets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
            targets[id] = target
        }
    }
}

private final class SheetListParser: NSObject, XMLParserDelegate {
    var sheets: [(name: String, relId: String)] = []

    static func parse(_ data: Data) -> [(name: String, relId: String)] {
        let delegate = SheetListParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.sheets
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "sheet", let name = attributes["name"], let relId = attributes["r:id"] {
            sheets.append((name, relId))
        }
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inText = false
    private var phoneticDepth = 0

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "si": current = ""
        case "rPh": phoneticDepth += 1
        case "t": inText = phoneticDepth == 0
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "t": inText = false
        case "rPh": phoneticDepth -= 1
        case "si": strings.append(current)
        default: break
        }
    }
}

private final class CellsParser: NSObject, XMLParserDelegate {
    private var sheet = XlsxWorkbook.Sheet()
    private let shared: [String]
    private var row = 0
    private var col = 0
    private var type = ""
    private var value = ""
    private var collecting = false

    init(shared: [String]) {
        self.shared = shared
    }

    static func parse(_ data: Data, shared: [String]) -> XlsxWorkbook.Sheet {
        let delegate = CellsParser(shared: shared)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.sheet
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "c":
            type = attributes["t"] ?? ""
            value = ""
            (row, col) = Self.position(attributes["r"] ?? "")
        case "v", "t":
            collecting = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collecting { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "v", "t":
            collecting = false
        case "c":
            guard row > 0, col > 0, !value.isEmpty else { return }
            let cell: XlsxWorkbook.Cell?
            switch type {
            case "s":
                cell = Int(value).flatMap { $0 < shared.count ? .text(shared[$0]) : nil }
            case "str", "inlineStr":
                cell = .text(value)
            case "b", "e":
                cell = nil
            default:
                cell = Double(value).map { .number($0) }
            }
            if let cell {
                sheet.cells[row, default: [:]][col] = cell
                sheet.maxRow = max(sheet.maxRow, row)
                sheet.maxCol = max(sheet.maxCol, col)
            }
        default: break
        }
    }

    /// "AB12" -> (ред 12, колона 28)
    private static func position(_ reference: String) -> (Int, Int) {
        var column = 0
        var rowDigits = ""
        for character in reference {
            if let ascii = character.asciiValue, ascii >= 65, ascii <= 90 {
                column = column * 26 + Int(ascii) - 64
            } else if character.isNumber {
                rowDigits.append(character)
            }
        }
        return (Int(rowDigits) ?? 0, column)
    }
}
