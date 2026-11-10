//
//  PLISTForge.swift
//  BlueForge
//
//  Pure helpers to parse, edit and re-serialise property lists found by the
//  A2DP probe. Kept free of side effects so it is unit-testable.
//

import Foundation

enum PLISTForgeError: Error, LocalizedError {
    case notADictionary
    case serializationFailed

    var errorDescription: String? {
        switch self {
        case .notADictionary: return "Plist root is not a dictionary."
        case .serializationFailed: return "Could not re-serialise plist."
        }
    }
}

struct ForgeKeyValue: Identifiable, Equatable {
    let id: UUID
    let components: [String]
    let originalText: String
    var editedText: String

    init(id: UUID = UUID(), components: [String], originalText: String, editedText: String? = nil) {
        self.id = id
        self.components = components
        self.originalText = originalText
        self.editedText = editedText ?? originalText
    }

    var display: String { components.joined(separator: " → ") }
    var untouched: Bool { editedText == originalText }
}

enum PLISTForge {
    typealias PlistFormat = PropertyListSerialization.PropertyListFormat

    static func parse(_ data: Data) throws -> (root: Any, format: PlistFormat) {
        var format = PlistFormat.xml
        let root = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        return (root, format)
    }

    static func serialise(_ root: Any, format: PlistFormat) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: root, format: format, options: 0)
    }

    /// Depth-first walk collecting scalar leaves as (path components, value).
    static func walk(_ obj: Any, path: [String] = [], into collected: inout [(components: [String], value: Any)]) {
        if let dict = obj as? [String: Any] {
            for key in dict.keys.sorted() {
                var next = path
                next.append(key)
                walk(dict[key]!, path: next, into: &collected)
            }
        } else if let array = obj as? [Any] {
            for (index, element) in array.prefix(64).enumerated() {
                var next = path
                next.append("[\(index)]")
                walk(element, path: next, into: &collected)
            }
        } else {
            collected.append((path, obj))
        }
    }

    /// Leaves whose key text or leaf value mentions one of the codec keywords.
    static func codecLeaves(in root: Any, keywords: [String] = A2DPIntrospection.codecKeywords)
        -> [(components: [String], value: Any)] {
        var leaves: [(components: [String], value: Any)] = []
        walk(root, into: &leaves)
        return leaves.filter { leaf in
            let keyText = leaf.components.joined(separator: ".").lowercased()
            let valueText = describeLeaf(leaf.value).lowercased()
            return keywords.contains { keyText.contains($0) || valueText.contains($0) }
        }
    }

    static func describeLeaf(_ value: Any) -> String {
        if let number = value as? NSNumber { return number.stringValue }
        if let str = value as? String { return str }
        return String(describing: value)
    }

    /// User-typed text back to a plist value (heuristic: bool/int/double then string).
    static func parseValue(_ text: String) -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "true" { return NSNumber(value: true) }
        if trimmed == "false" { return NSNumber(value: false) }
        if let intVal = Int(trimmed), abs(Double(intVal)) < 4_611_686_018_427_387_904 { return NSNumber(value: intVal) }
        if trimmed.contains("."), let doubleVal = Double(trimmed) { return NSNumber(value: doubleVal) }
        return trimmed
    }

    /// Set a nested key path. Bracket index components (`[3]`) are not writable;
    /// pass a path with dictionary keys only.
    @discardableResult
    static func setPath(_ dict: inout [String: Any], path: [String], value: Any) -> Bool {
        guard let first = path.first, !first.hasPrefix("[") else { return false }
        if path.count == 1 {
            dict[first] = value
            return true
        }
        guard var sub = dict[first] as? [String: Any] else { return false }
        let ok = setPath(&sub, path: Array(path.dropFirst()), value: value)
        if ok { dict[first] = sub }
        return ok
    }

    /// Apply edited values; returns the components that were actually changed
    /// (skipping index paths and untouched rows).
    static func apply(_ root: inout Any, edits: [ForgeKeyValue]) -> Set<[String]> {
        var changed: Set<[String]> = []
        guard var dict = root as? [String: Any] else { return changed }
        for edit in edits where !edit.untouched {
            let path = edit.components.filter { !$0.hasPrefix("[") }
            guard path.count == edit.components.count else { continue }
            if setPath(&dict, path: path, value: parseValue(edit.editedText)) {
                changed.insert(edit.components)
            }
        }
        if !changed.isEmpty {
            root = dict
        }
        return changed
    }

    /// Build editable rows from a parsed plist (all keys, or codec-flavoured only).
    static func keyValues(root: Any, codecOnly: Bool) -> [ForgeKeyValue] {
        let leaves = codecOnly ? codecLeaves(in: root) : {
            var all: [(components: [String], value: Any)] = []
            walk(root, into: &all)
            return all
        }()
        return leaves.map { leaf in
            ForgeKeyValue(components: leaf.components, originalText: describeLeaf(leaf.value))
        }
    }
}
