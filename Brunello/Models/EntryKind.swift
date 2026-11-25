import Foundation

/// What happened: the six buttons on the Today screen (walk for dogs, play for cats).
enum EntryKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, poo, pee, walk, play, health, photo

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .food: "🍗"
        case .poo: "💩"
        case .pee: "💦"
        case .walk: "🦮"
        case .play: "🧶"
        case .health: "💊"
        case .photo: "📸"
        }
    }

    var label: String {
        switch self {
        case .food: "Food"
        case .poo: "Poo"
        case .pee: "Pee"
        case .walk: "Walk"
        case .play: "Play"
        case .health: "Health"
        case .photo: "Photo"
        }
    }

    /// Label under the number in the day summary.
    var countLabel: String {
        switch self {
        case .food: "meals"
        case .poo: "poos"
        case .pee: "pees"
        case .walk: "walks"
        case .play: "plays"
        case .health: "notes"
        case .photo: "photos"
        }
    }

    /// Title of the sheet that asks how it went.
    func question(petName: String) -> String {
        switch self {
        case .food: "How much did \(petName) eat?"
        case .poo: "How was \(petName)'s poo?"
        case .pee: "How did the pee go?"
        case .walk: "How long was the walk?"
        case .play: "How long did \(petName) play?"
        case .health: "What happened?"
        case .photo: "Send a photo of \(petName)"
        }
    }

    /// The answers offered for this kind. Keep the voice lines in step with
    /// supabase/functions/notify-parent/petVoice.ts so the diary and the notification match.
    var options: [EntryOption] {
        switch self {
        case .food: [
            EntryOption(detail: .all, emoji: "😋", label: "Ate everything", voiceLine: "I ate everything! 😋"),
            EntryOption(detail: .half, emoji: "🍗", label: "Ate half", voiceLine: "I ate half of my food 🍗"),
            EntryOption(detail: .little, emoji: "🥺", label: "Just a little", voiceLine: "I only ate a little 🥺"),
            EntryOption(detail: .nothing, emoji: "😔", label: "Didn't eat", voiceLine: "I didn't want to eat 😔"),
        ]
        case .poo: [
            EntryOption(detail: .good, emoji: "✨", label: "Good", voiceLine: "I made a good poo! 💩✨"),
            EntryOption(detail: .soft, emoji: "🫠", label: "Soft", voiceLine: "my poo was a bit soft 💩"),
            EntryOption(detail: .hard, emoji: "🪨", label: "Hard", voiceLine: "my poo was a bit hard 💩"),
            EntryOption(detail: .runny, emoji: "😣", label: "Runny", voiceLine: "my tummy is upset, runny poo 😣"),
        ]
        case .pee: [
            EntryOption(detail: .normal, emoji: "💦", label: "All good", voiceLine: "I did a pee! 💦"),
            EntryOption(detail: .accident, emoji: "🙈", label: "Little accident", voiceLine: "oops, I had a little accident 🙈"),
        ]
        case .walk: [
            EntryOption(detail: .short, emoji: "🐾", label: "Short", hint: "about 15 minutes", voiceLine: "I went for a short walk 🐾"),
            EntryOption(detail: .medium, emoji: "🐾", label: "Medium", hint: "about 30 minutes", voiceLine: "I went for a nice walk 🐾"),
            EntryOption(detail: .long, emoji: "🌳", label: "Long", hint: "an hour or more", voiceLine: "I went for a long walk! 🌳"),
        ]
        case .play: [
            EntryOption(detail: .short, emoji: "🧶", label: "Short", hint: "a few minutes", voiceLine: "I played a little 🧶"),
            EntryOption(detail: .medium, emoji: "🧶", label: "Medium", hint: "about 15 minutes", voiceLine: "I had a good play 🧶"),
            EntryOption(detail: .long, emoji: "✨", label: "Long", hint: "half an hour or more", voiceLine: "I played a lot! 🧶✨"),
        ]
        case .health: [
            EntryOption(detail: .medicine, emoji: "💊", label: "Took medicine", voiceLine: "I took my medicine 💊"),
            EntryOption(detail: .vomit, emoji: "🤢", label: "Threw up", voiceLine: "I threw up 🤢"),
            EntryOption(detail: .vet, emoji: "🩺", label: "Vet visit", voiceLine: "I went to the vet 🩺"),
            EntryOption(detail: .unwell, emoji: "🤒", label: "Feeling unwell", voiceLine: "I'm not feeling great today 🤒"),
        ]
        case .photo: []
        }
    }
}

/// How it went. The raw values are the words stored in the database.
enum EntryDetail: String, Codable, Sendable {
    case all, half, little
    case nothing = "none"
    case good, soft, hard, runny
    case normal, accident
    case short, medium, long
    case medicine, vomit, vet, unwell
}

/// One tappable answer in the log sheet, with the sentence the pet says for it.
struct EntryOption: Identifiable, Equatable, Sendable {
    let detail: EntryDetail
    let emoji: String
    let label: String
    var hint: String?
    let voiceLine: String

    var id: EntryDetail { detail }
}
