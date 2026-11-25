import Foundation

/// Project settings. The key is the project's publishable key: it is meant to ship inside the app,
/// and the database's access rules decide what each signed-in parent may see.
enum AppConfig {
    static let supabaseURL = URL(string: "https://zfzbuqfvdtgwzzjvyyji.supabase.co")!
    static let supabaseKey = "sb_publishable_5AWZgp6RKT7kQJCcE6DZrg_PqlyjWvo"

    static let photosBucket = "photos"
    /// How many diary entries the app keeps loaded (newest first).
    static let entriesLimit = 1000
    /// Longest side of an uploaded photo, in pixels.
    static let photoMaxDimension: CGFloat = 1600
}
