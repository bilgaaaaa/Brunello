// The pet's voice for notifications. Keep in step with EntryKind.options in the iOS app
// (Brunello/Models/EntryKind.swift) so the diary and the notification say the same thing.

export const VOICE_LINES: Record<string, Record<string, string>> = {
  food: {
    all: "I ate everything! 😋",
    half: "I ate half of my food 🍗",
    little: "I only ate a little 🥺",
    none: "I didn't want to eat 😔",
  },
  poo: {
    good: "I made a good poo! 💩✨",
    soft: "my poo was a bit soft 💩",
    hard: "my poo was a bit hard 💩",
    runny: "my tummy is upset, runny poo 😣",
  },
  pee: {
    normal: "I did a pee! 💦",
    accident: "oops, I had a little accident 🙈",
  },
  walk: {
    short: "I went for a short walk 🐾",
    medium: "I went for a nice walk 🐾",
    long: "I went for a long walk! 🌳",
  },
  play: {
    short: "I played a little 🧶",
    medium: "I had a good play 🧶",
    long: "I played a lot! 🧶✨",
  },
  health: {
    medicine: "I took my medicine 💊",
    vomit: "I threw up 🤢",
    vet: "I went to the vet 🩺",
    unwell: "I'm not feeling great today 🤒",
  },
};

export const PHOTO_VOICE_LINE = "look at me! 📸";

const SPECIES_EMOJI: Record<string, string> = { dog: "🐶", cat: "🐱" };

/** The sentence the pet says for one entry, or null when the kind or detail is unknown. */
export function voiceLine(kind: string, detail: string | null): string | null {
  if (kind === "photo") return PHOTO_VOICE_LINE;
  return VOICE_LINES[kind]?.[detail ?? ""] ?? null;
}

/** Notification title, for example "Bruno 🐶". */
export function notificationTitle(petName: string, species: string): string {
  return `${petName} ${SPECIES_EMOJI[species] ?? "🐾"}`;
}

/** Notification text addressed to the receiving parent, for example "Mama, I made a good poo! 💩✨". */
export function notificationBody(nickname: string, line: string): string {
  return `${nickname}, ${line}`;
}
