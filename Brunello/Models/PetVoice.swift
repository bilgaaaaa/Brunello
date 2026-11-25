import Foundation

/// Turns an entry into the sentence the pet says about it.
enum PetVoice {
    static let photoVoiceLine = "look at me! 📸"

    /// The pet's sentence, written so a nickname can go in front ("Mama, " + line).
    static func voiceLine(for entry: Entry) -> String {
        if entry.kind == .photo { return photoVoiceLine }
        return entry.kind.options.first { $0.detail == entry.detail }?.voiceLine ?? entry.kind.label
    }

    /// The same sentence standing alone, as shown in the diary.
    static func diaryMessage(for entry: Entry) -> String {
        let line = voiceLine(for: entry)
        return line.prefix(1).uppercased() + line.dropFirst()
    }
}
