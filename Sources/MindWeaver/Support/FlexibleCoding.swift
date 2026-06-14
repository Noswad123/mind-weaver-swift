import Foundation

struct FlexibleCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func decodeFlexibleString(for keys: [String]) -> String? {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else { continue }

            if let value = try? decode(String.self, forKey: key), !value.isEmpty {
                return value
            }

            if let value = try? decode(Int.self, forKey: key) {
                return String(value)
            }
        }

        return nil
    }

    func decodeFlexibleStringArray(for keys: [String]) -> [String] {
        for keyName in keys {
            guard let key = FlexibleCodingKey(stringValue: keyName) else { continue }

            if let values = try? decode([String].self, forKey: key) {
                return values
            }

            if let value = try? decode(String.self, forKey: key), !value.isEmpty {
                return value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }

        return []
    }
}
