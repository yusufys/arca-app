import Foundation
import CoreFoundation

public struct CollectionDesignError: LocalizedError {
    public let errorDescription: String?
    public init(_ message: String) { errorDescription = message }
}

/// Version 2 is pinned to the field renderers shipped in this binary. The backend serves the same contract.
public enum CollectionBlueprint {
    public static let maximumReplyBytes = 262_144
    private typealias Rule = [String: Any]
    private static let rules: Rule? = {
        guard let url = Bundle.module.url(forResource: "collection-v2", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? Rule
    }()

    /// Extract one object without altering its strings or guessing which schema an assistant meant.
    public static func schema(fromReply text: String, spaceID: UUID) throws -> CollectionSchema {
        guard text.utf8.count <= maximumReplyBytes else { throw CollectionDesignError("The reply is too large. Ask for a smaller collection.") }
        // A fenced reply may include prose or Markdown links outside the JSON.
        let parts = text.components(separatedBy: "```")
        let source: String
        if parts.count == 3, !parts[0].contains("{"), !parts[2].contains("{"),
           let newline = parts[1].firstIndex(of: "\n"),
           ["", "json", "application/json"].contains(parts[1][..<newline].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            source = String(parts[1][parts[1].index(after: newline)...])
        } else {
            source = text
        }
        let bytes = Array(source.utf8)
        var start: Int?
        var end: Int?
        var depth = 0
        var quoted = false
        var escaped = false
        for (i, b) in bytes.enumerated() {
            if depth == 0 {
                if b == 91 || b == 93 || b == 125 { throw CollectionDesignError("Paste one collection object, without array brackets or extra JSON.") }
                guard b == 123 else { continue }
                guard start == nil else { throw CollectionDesignError("The reply has multiple objects. Paste just one collection.") }
                start = i
                depth = 1
            } else if quoted {
                if escaped { escaped = false }
                else if b == 92 { escaped = true }
                else if b == 34 { quoted = false }
            } else if b == 34 { quoted = true }
            else if b == 123 { depth += 1 }
            else if b == 125 { depth -= 1; if depth == 0 { end = i } }
        }
        guard let start, let end, depth == 0 else { throw CollectionDesignError("Paste the complete JSON object returned by your assistant.") }
        let data = Data(bytes[start...end])
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw CollectionDesignError("The reply contains invalid JSON. Ask the assistant to correct it and paste it again.")
        }
        return try schema(from: object, spaceID: spaceID)
    }

    public static func schema(from object: Any, spaceID: UUID) throws -> CollectionSchema {
        guard let rules else { throw CollectionDesignError("The collection rules could not be loaded.") }
        try validate(object, rule: rules, path: "Collection")
        let data = try JSONSerialization.data(withJSONObject: object)
        guard data.count <= maximumReplyBytes else { throw CollectionDesignError("The schema exceeds the supported size.") }
        let dto = try JSONDecoder().decode(OptionalCapabilityEngine.ImportedSchemaDTO.self, from: data)
        let fields = dto.fields.enumerated().map { index, item in
            FieldDefinition(label: item.label.trimmingCharacters(in: .whitespacesAndNewlines), type: item.type,
                            isRequired: item.isRequired ?? false, sortOrder: index,
                            options: (item.options ?? []).map { SelectOption(label: $0) },
                            isPrimaryTitle: item.isPrimaryTitle ?? false)
        }
        return CollectionSchema(spaceId: spaceID, name: dto.name.trimmingCharacters(in: .whitespacesAndNewlines),
            iconName: dto.iconName ?? "list.clipboard", colorHex: dto.colorHex ?? "#3A6B5C", fields: fields)
    }

    // Implements the keywords used in the bundled v1 contract, including its field-type conditions.
    private static func validate(_ value: Any, rule: Rule, path: String) throws {
        func error(_ reason: String) -> CollectionDesignError { CollectionDesignError("\(path): \(reason)") }
        let dictionary = value as? [String: Any]
        let string = value as? String
        let array = value as? [Any]
        let boolean = (value as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil }
        switch rule["type"] as? String {
        case "object" where dictionary == nil: throw error("expected an object.")
        case "string" where string == nil: throw error("expected text.")
        case "array" where array == nil: throw error("expected a list.")
        case "boolean" where boolean == nil: throw error("expected true or false.")
        default: break
        }
        if let expected = rule["const"] as? String, string != expected { throw error("expected \(expected).") }
        if let expected = rule["const"] as? Bool, boolean != expected { throw error("unexpected flag.") }
        if let values = rule["enum"] as? [String], !values.contains(string ?? "") { throw error("unsupported value.") }
        if let string {
            guard (rule["minLength"] as? Int ?? 0) <= string.unicodeScalars.count,
                  string.unicodeScalars.count <= (rule["maxLength"] as? Int ?? Int.max) else { throw error("text length is outside the allowed range.") }
            if let pattern = rule["pattern"] as? String, string.range(of: pattern, options: .regularExpression) == nil {
                throw error("text does not match the required format.")
            }
        }
        if let dictionary {
            for key in rule["required"] as? [String] ?? [] where dictionary[key] == nil { throw error("missing \(key).") }
            if let properties = rule["properties"] as? [String: Rule] {
                for (key, item) in dictionary {
                    if let property = properties[key] { try validate(item, rule: property, path: "\(path).\(key)") }
                    else if rule["additionalProperties"] as? Bool == false { throw error("unsupported property \(key).") }
                }
            }
        }
        if let array {
            guard array.count >= (rule["minItems"] as? Int ?? 0), array.count <= (rule["maxItems"] as? Int ?? Int.max) else { throw error("incorrect number of items.") }
            if rule["uniqueItems"] as? Bool == true, let strings = array as? [String], Set(strings).count != strings.count { throw error("options must be unique.") }
            if let items = rule["items"] as? Rule {
                for (index, item) in array.enumerated() { try validate(item, rule: items, path: "\(path)[\(index + 1)]") }
            }
            if let predicate = rule["contains"] as? Rule, let maximum = rule["maxContains"] as? Int {
                let matches = array.filter { (try? validate($0, rule: predicate, path: path)) != nil }
                if matches.count > maximum { throw error("choose only one primary title.") }
            }
        }
        for condition in rule["allOf"] as? [Rule] ?? [] {
            guard let test = condition["if"] as? Rule else { continue }
            let matched = (try? validate(value, rule: test, path: path)) != nil
            if let branch = condition[matched ? "then" : "else"] as? Rule { try validate(value, rule: branch, path: path) }
        }
    }
}
