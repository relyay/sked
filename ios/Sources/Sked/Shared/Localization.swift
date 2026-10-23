import Foundation

/// Localized string from this package's bundle. SwiftUI's `Text("key")` looks
/// in the main bundle, but xtool packages strings into the module bundle.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
