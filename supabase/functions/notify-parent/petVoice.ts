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

// What the pet says when a parent spends money on it, by expense category.
// Keep the categories in step with ExpenseCategory in the iOS app (Brunello/Models/Expense.swift).
const EXPENSE_VOICE_LINES: Record<string, (payerName: string, amount: string) => string> = {
  food: (payerName, amount) => `${payerName} bought my food (${amount}) 🍖`,
  vet: (payerName, amount) => `${payerName} paid the vet for me (${amount}) 🩺`,
  medicine: (payerName, amount) => `${payerName} bought my medicine (${amount}) 💊`,
  grooming: (payerName, amount) => `${payerName} paid for my grooming (${amount}) ✂️`,
  toys: (payerName, amount) => `${payerName} bought me toys (${amount}) 🧸`,
  other: (payerName, amount) => `${payerName} bought something for me (${amount}) 🛍️`,
  settle_up: (payerName, amount) => `${payerName} paid you back ${amount} 🤝`,
};

/** Money as people read it, for example "€25.00". */
export function formatAmount(amountCents: number, currencyCode: string): string {
  return new Intl.NumberFormat("en", { style: "currency", currency: currencyCode }).format(amountCents / 100);
}

/** The sentence the pet says about an expense, or null when the category is unknown. */
export function expenseVoiceLine(category: string, payerName: string, amountCents: number, currencyCode: string): string | null {
  const line = EXPENSE_VOICE_LINES[category];
  return line ? line(payerName, formatAmount(amountCents, currencyCode)) : null;
}

/** Notification title, for example "Bruno 🐶". */
export function notificationTitle(petName: string, species: string): string {
  return `${petName} ${SPECIES_EMOJI[species] ?? "🐾"}`;
}

/** Notification text addressed to the receiving parent, for example "Mama, I made a good poo! 💩✨". */
export function notificationBody(nickname: string, line: string): string {
  return `${nickname}, ${line}`;
}
