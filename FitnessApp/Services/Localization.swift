import SwiftUI

/// Език на интерфейса: български (по подразбиране) или английски.
/// Български текстове са ключове; английските са в `en.lproj/Localizable.strings`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case bg, en

    static let storageKey = "appLanguage"

    var id: String { rawValue }
    var label: String { self == .bg ? "Български" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "bg") ?? .bg
    }
}

private let englishBundle: Bundle = {
    if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let bundle = Bundle(path: path) {
        return bundle
    }
    return Bundle.main
}()

/// Превод на готов String (за места, където SwiftUI не превежда сам: променливи, enum заглавия).
func tr(_ key: String) -> String {
    guard AppLanguage.current == .en else { return key }
    return englishBundle.localizedString(forKey: key, value: key, table: nil)
}

/// Превод с форматиране: `trf("%lld седмици", n)`.
func trf(_ key: String, _ args: CVarArg...) -> String {
    String(format: tr(key), arguments: args)
}
