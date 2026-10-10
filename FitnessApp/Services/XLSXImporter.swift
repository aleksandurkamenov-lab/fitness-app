import Foundation
import Compression
import SwiftData

/// Внасяне на треньорски Excel (.xlsx) направо от телефона. Същата подредба като tools/xlsx_to_json.py.
enum XLSXImporter {
    enum ImportFailure: LocalizedError {
        case notAnXLSX
        case noWorkouts

        var errorDescription: String? {
            switch self {
            case .notAnXLSX: "Файлът не изглежда като Excel (.xlsx) или не мога да го прочета."
            case .noWorkouts: "Не намерих тренировки във файла. Подредбата трябва да е като при Meso 22."
            }
        }
    }

    @discardableResult
    static func importFile(at url: URL, in context: ModelContext) throws -> Mesocycle {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let sheet = try XLSXReader.firstSheet(from: data)
        let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        let payload = try convert(sheet, name: name)
        return try MesoImporter.importPayload(payload, in: context)
    }

    // MARK: Превръщане на листа в мезоцикъл

    private static let commentLabel = "Коментар по упражнението"
    private static let skipComments: Set<String> = ["Link", "Най - добри резултати до сега -->"]

    private static let muscleKeywords: [(String, [String])] = [
        ("calves", ["calves", "calf"]),
        ("glutes", ["hip thrust", "glute"]),
        ("hamstrings", ["rdl", "leg curl", "hamstring", "deadlift"]),
        ("quads", ["leg press", "squat", "leg extension", "lunge", "adductor"]),
        ("abs", ["crunch", "abs", "leg raise"]),
        ("biceps", ["curl", "biceps"]),
        ("triceps", ["tricep", "pushdown", "extension", "skull"]),
        ("shoulders", ["lateral", "overhead", "shoulder", "reverce", "reverse pec", "face pull", "rear delt"]),
        ("back", ["pulldown", "row", "pull-up", "pullup", "shrug", "lat "]),
        ("chest", ["bench", "chest", "pec", "fly", "push"]),
    ]

    private static func guessMuscle(_ name: String) -> String {
        let lowered = name.lowercased()
        for (muscle, words) in muscleKeywords where words.contains(where: { lowered.contains($0) }) {
            return muscle
        }
        return "chest"
    }

    private static func parseRange(_ text: String?) -> (Int, Int)? {
        guard let text else { return nil }
        let parts = text.replacingOccurrences(of: "–", with: "-").split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let low = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let high = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return (low, high)
    }

    private static func convert(_ sheet: XLSXSheet, name: String) throws -> MesoImporter.Payload {
        var workouts: [MesoImporter.Payload.Workout] = []
        let starts = (1...max(sheet.maxCol, 1)).filter { column in
            if let text = sheet.text(6, column) { return !text.trimmingCharacters(in: .whitespaces).isEmpty }
            return false
        }

        for start in starts {
            var exercises: [MesoImporter.Payload.Workout.Item] = []
            if sheet.maxRow >= 7 {
                for row in 7...sheet.maxRow {
                    guard let exerciseName = sheet.text(row, start)?.trimmingCharacters(in: .whitespaces),
                          !exerciseName.isEmpty,
                          sheet.text(row, start + 3)?.trimmingCharacters(in: .whitespaces) == commentLabel else { continue }

                    var sets: [SetTarget] = []
                    var offset = 5
                    while offset + 2 < sheet.maxCol - start + 1 {
                        guard let target = parseRange(sheet.text(row + 3, start + offset)) else { break }
                        sets.append(SetTarget(repMin: target.0, repMax: target.1,
                                              bestWeight: sheet.number(row + 2, start + offset + 1),
                                              bestReps: sheet.number(row + 2, start + offset + 2)))
                        offset += 3
                    }

                    var notes: [String] = []
                    for noteRow in (row + 1)...(row + 6) {
                        if let text = sheet.text(noteRow, start + 3)?.trimmingCharacters(in: .whitespaces),
                           !text.isEmpty, !skipComments.contains(text) {
                            notes.append(text)
                        }
                    }
                    exercises.append(.init(name: exerciseName, muscle: guessMuscle(exerciseName),
                                           note: notes.joined(separator: " · "), sets: sets))
                }
            }
            let title = sheet.text(6, start)?.trimmingCharacters(in: .whitespaces) ?? "Тренировка"
            workouts.append(.init(name: title, exercises: exercises))
        }

        guard workouts.contains(where: { !$0.exercises.isEmpty }) else { throw ImportFailure.noWorkouts }
        return MesoImporter.Payload(name: name, weeks: 4, workouts: workouts)
    }
}

// MARK: Четене на .xlsx

struct XLSXSheet {
    enum Cell {
        case text(String)
        case number(Double)
    }

    var cells: [Int: [Int: Cell]] = [:]
    var maxRow = 0
    var maxCol = 0

    func text(_ row: Int, _ column: Int) -> String? {
        if case .text(let value)? = cells[row]?[column] { return value }
        return nil
    }

    func number(_ row: Int, _ column: Int) -> Double? {
        if case .number(let value)? = cells[row]?[column] { return value }
        return nil
    }
}

enum XLSXReader {
    private struct Entry {
        var method: Int
        var compressedSize: Int
        var size: Int
        var offset: Int
    }

    static func firstSheet(from data: Data) throws -> XLSXSheet {
        let bytes = [UInt8](data)
        let entries = try zipEntries(bytes)
        guard let sheetName = entries.keys.filter({ $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }).sorted().first,
              let sheetData = try extract(entries[sheetName]!, from: bytes) else {
            throw XLSXImporter.ImportFailure.notAnXLSX
        }
        var shared: [String] = []
        if let entry = entries["xl/sharedStrings.xml"], let stringsData = try extract(entry, from: bytes) {
            let parser = SharedStringsParser()
            let xml = XMLParser(data: stringsData)
            xml.delegate = parser
            xml.parse()
            shared = parser.strings
        }
        let parser = SheetXMLParser(shared: shared)
        let xml = XMLParser(data: sheetData)
        xml.delegate = parser
        xml.parse()
        return XLSXSheet(cells: parser.cells, maxRow: parser.maxRow, maxCol: parser.maxCol)
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
    private static func u32(_ b: [UInt8], _ o: Int) -> Int { u16(b, o) | u16(b, o + 2) << 16 }

    private static func zipEntries(_ b: [UInt8]) throws -> [String: Entry] {
        guard b.count > 22 else { throw XLSXImporter.ImportFailure.notAnXLSX }
        var eocd = -1
        var index = b.count - 22
        let lowest = max(0, b.count - 22 - 65_535)
        while index >= lowest {
            if b[index] == 0x50, b[index + 1] == 0x4B, b[index + 2] == 0x05, b[index + 3] == 0x06 { eocd = index; break }
            index -= 1
        }
        guard eocd >= 0 else { throw XLSXImporter.ImportFailure.notAnXLSX }
        let count = u16(b, eocd + 10)
        var position = u32(b, eocd + 16)
        var result: [String: Entry] = [:]
        for _ in 0..<count {
            guard position + 46 <= b.count, u32(b, position) == 0x0201_4B50 else { break }
            let method = u16(b, position + 10)
            let compressed = u32(b, position + 20)
            let size = u32(b, position + 24)
            let nameLength = u16(b, position + 28)
            let extraLength = u16(b, position + 30)
            let commentLength = u16(b, position + 32)
            let offset = u32(b, position + 42)
            guard position + 46 + nameLength <= b.count else { break }
            let name = String(decoding: b[(position + 46)..<(position + 46 + nameLength)], as: UTF8.self)
            result[name] = Entry(method: method, compressedSize: compressed, size: size, offset: offset)
            position += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    private static func extract(_ entry: Entry, from b: [UInt8]) throws -> Data? {
        guard entry.offset + 30 <= b.count, u32(b, entry.offset) == 0x0403_4B50 else { return nil }
        let start = entry.offset + 30 + u16(b, entry.offset + 26) + u16(b, entry.offset + 28)
        guard start + entry.compressedSize <= b.count else { return nil }
        let raw = Array(b[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0:
            return Data(raw)
        case 8:
            var output = [UInt8](repeating: 0, count: max(entry.size, 1))
            let written = raw.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { target in
                    compression_decode_buffer(target.baseAddress!, target.count, source.baseAddress!, source.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written > 0 else { return nil }
            return Data(output.prefix(written))
        default:
            return nil
        }
    }
}

nonisolated final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current = ""
    private var inText = false
    private var inPhonetic = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "si": current = ""
        case "t": inText = true
        case "rPh": inPhonetic = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText && !inPhonetic { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "t": inText = false
        case "rPh": inPhonetic = false
        case "si": strings.append(current)
        default: break
        }
    }
}

nonisolated final class SheetXMLParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var cells: [Int: [Int: XLSXSheet.Cell]] = [:]
    var maxRow = 0
    var maxCol = 0
    private var reference = ""
    private var type = ""
    private var value = ""
    private var inCell = false
    private var inValue = false
    private var inInlineText = false

    init(shared: [String]) { self.shared = shared }

    /// "BQ12" -> (колона 69, ред 12)
    private func position(_ reference: String) -> (column: Int, row: Int)? {
        var column = 0
        var digits = ""
        for character in reference.uppercased() {
            if let ascii = character.asciiValue, ascii >= 65, ascii <= 90, digits.isEmpty {
                column = column * 26 + Int(ascii) - 64
            } else if character.isNumber {
                digits.append(character)
            }
        }
        guard column > 0, let row = Int(digits) else { return nil }
        return (column, row)
    }

    private func store() {
        guard let place = position(reference) else { return }
        let cell: XLSXSheet.Cell
        switch type {
        case "s":
            guard let index = Int(value.trimmingCharacters(in: .whitespaces)), shared.indices.contains(index) else { return }
            cell = .text(shared[index])
        case "inlineStr", "str":
            guard !value.isEmpty else { return }
            cell = .text(value)
        case "b", "e":
            return
        default:
            guard let number = Double(value.trimmingCharacters(in: .whitespaces)) else { return }
            cell = .number(number)
        }
        cells[place.row, default: [:]][place.column] = cell
        maxRow = max(maxRow, place.row)
        maxCol = max(maxCol, place.column)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "c":
            reference = attributeDict["r"] ?? ""
            type = attributeDict["t"] ?? ""
            value = ""
            inCell = true
        case "v": inValue = true
        case "t": if inCell { inInlineText = true }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue || inInlineText { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "v": inValue = false
        case "t": inInlineText = false
        case "c":
            store()
            inCell = false
        default: break
        }
    }
}
