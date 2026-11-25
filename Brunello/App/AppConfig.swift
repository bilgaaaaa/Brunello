import Foundation

/// Project settings. Paste the two Supabase values from your project (Settings > API) before running.
enum AppConfig {
    static let supabaseURL = URL(string: "https://YOUR-PROJECT-REF.supabase.co")!
    static let supabaseKey = "YOUR-SUPABASE-ANON-KEY"

    static let photosBucket = "photos"
    /// How many diary entries the app keeps loaded (newest first).
    static let entriesLimit = 1000
    /// Longest side of an uploaded photo, in pixels.
    static let photoMaxDimension: CGFloat = 1600

    static var isConfigured: Bool {
        !supabaseKey.hasPrefix("YOUR-")
    }
}
