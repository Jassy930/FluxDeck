import Foundation

enum AppLanguage: String, CaseIterable, Equatable, Identifiable {
    case system
    case english
    case simplifiedChinese

    var id: String { storageValue }

    var storageValue: String {
        switch self {
        case .system:
            return "system"
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .system:
            return Locale.autoupdatingCurrent.identifier
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var resolvedLocale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    static func from(storageValue: String) -> AppLanguage {
        switch storageValue {
        case AppLanguage.english.storageValue:
            return .english
        case AppLanguage.simplifiedChinese.storageValue:
            return .simplifiedChinese
        default:
            return .system
        }
    }
}
