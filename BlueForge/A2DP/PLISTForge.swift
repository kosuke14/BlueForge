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
    /// false when the original leaf is a type we cannot round-trip (Data/Date).
    let editable: Bool

    init(id: UUID = UUID(), components: [String], originalText: String,
         editedText: String? = nil, editable: Bool = true) {
        self.id = id
        self.components = components
        self.originalText = originalText
        self.editedText = editedText ?? originalText
        self.editable = editable
    }

    var display: String { components.joined(separator: " → ") }
    var untouched: Bool { editedText == originalText }
    var ignored: Bool { !editable || untouched }
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
        if value is Bool { return (value as! Bool) ? "true" : "false" }
        if let number = value as? NSNumber { return number.stringValue }
        if let str = value as? String { return str }
        if let data = value as? Data { return "(\(data.count) bytes)" }
        if let date = value as? Date { return date.description }
        return String(describing: value)
    }

    /// Whether a leaf's type survives text round-tripping.
    static func isEditableLeaf(_ value: Any) -> Bool {
        !(value is Data || value is Date)
    }

    /// Canonical form of user-text after parsing (for readback verification).
    static func canonical(_ text: String) -> String {
        describeLeaf(parseValue(text))
    }

    /// Resolve a leaf value by components (dict keys + "[n]" array indices).
    static func value(in root: Any, at components: [String]) -> Any? {
        var current = root
        for component in components {
            if component.hasPrefix("["), component.hasSuffix("]"),
               let index = Int(component.dropFirst().dropLast()),
               let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dict = current as? [String: Any], let next = dict[component] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    /// Compare two plist leaves semantically (numbers cross-type, bools, strings).
    static func leavesEqual(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case (let s1 as String, let s2 as String): return s1 == s2
        case (let n1 as NSNumber, let n2 as NSNumber): return n1 == n2
        case (let d1 as Data, let d2 as Data): return d1 == d2
        case (let d1 as Date, let d2 as Date): return d1 == d2
        default: return false
        }
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
        for edit in edits where !edit.ignored {
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
            ForgeKeyValue(components: leaf.components,
                          originalText: describeLeaf(leaf.value),
                          editable: isEditableLeaf(leaf.value))
        }
    }
}
