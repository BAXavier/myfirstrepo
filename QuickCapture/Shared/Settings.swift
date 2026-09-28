import Foundation
import Security

/// Non-secret preferences live in UserDefaults (bound with @AppStorage in the UI); tokens live in the Keychain.
enum Pref {
    static let extractor = "extractor"            // ExtractorChoice.rawValue
    static let claudeModel = "claudeModel"
    static let useReminders = "useReminders"
    static let remindersList = "remindersList"
    static let useTodoist = "useTodoist"
    static let todoistProject = "todoistProject"
    static let useNotion = "useNotion"
    static let notionDatabase = "notionDatabase"
    static let notionTitleProp = "notionTitleProp"
    static let notionDueProp = "notionDueProp"
    static let silenceSeconds = "silenceSeconds"
    static let swirlEnabled = "swirlEnabled"      // macOS mouse swirl
    static let tripleOptionEnabled = "tripleOptionEnabled"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            extractor: ExtractorChoice.auto.rawValue,
            useReminders: true,
            silenceSeconds: 1.8,
            swirlEnabled: true,
            tripleOptionEnabled: true,
            notionTitleProp: "Name",
        ])
    }
}

enum ExtractorChoice: String, CaseIterable, Identifiable {
    case auto, apple, claude, simple
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: "Auto (on-device, then Claude)"
        case .apple: "Apple Intelligence (on-device)"
        case .claude: "Claude"
        case .simple: "No AI (one task per sentence)"
        }
    }
}

enum Secret: String {
    case anthropicKey, todoistToken, notionToken

    private static let service = "QuickCapture"

    var value: String {
        get {
            var out: AnyObject?
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: rawValue,
                                    kSecReturnData as String: true]
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
            return String(decoding: d, as: UTF8.self)
        }
        nonmutating set {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: Self.service,
                                    kSecAttrAccount as String: rawValue]
            SecItemDelete(q as CFDictionary)
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            var add = q
            add[kSecValueData as String] = Data(trimmed.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
