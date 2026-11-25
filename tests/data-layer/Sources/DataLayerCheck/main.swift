import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Supabase

// End-to-end check of the app's data layer against the local stack started by tests/run.sh:
// real PostgREST with the real schema and rules, the real notify-parent handler, a fake Apple push server.

final class MemoryStorage: AuthLocalStorage, @unchecked Sendable {
    private var values: [String: Data] = [:]
    private let lock = NSLock()
    func store(key: String, value: Data) throws { lock.lock(); values[key] = value; lock.unlock() }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); values[key] = nil; lock.unlock() }
}

func makeService() -> DiaryService {
    DiaryService(client: SupabaseClient(
        supabaseURL: AppConfig.supabaseURL,
        supabaseKey: AppConfig.supabaseKey,
        options: SupabaseClientOptions(auth: .init(storage: MemoryStorage(), emitLocalSessionAsInitialSession: true))
    ))
}

setvbuf(stdout, nil, _IONBF, 0)
var passed = 0
func check(_ condition: Bool, _ label: String) {
    guard condition else { print("FAIL  \(label)"); exit(1) }
    passed += 1
    print("PASS  \(label)")
}

struct SentAlert: Decodable {
    let token: String
    let environment: String
    let title: String
    let body: String
    let result: String
}

func sentAlerts() async throws -> [SentAlert] {
    let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:54321/test/alerts")!)
    return try JSONDecoder().decode([SentAlert].self, from: data)
}

let sofia = makeService(), marco = makeService(), stranger = makeService()

// Sign-in
let sofiaID = try await sofia.signIn()
check(try await sofia.signIn() == sofiaID, "a second sign-in reuses the stored session")
let marcoID = try await marco.signIn()
let strangerID = try await stranger.signIn()
check(Set([sofiaID, marcoID, strangerID]).count == 3, "every phone gets its own account")
check(try await sofia.fetchFamily(userID: sofiaID) == nil, "no family before onboarding")

// Onboarding
try await sofia.createPet(name: "Bruno", species: .dog, currencyCode: "eur", parentName: "Sofia", parentNickname: "Mama")
var sofiaFamily = try await sofia.fetchFamily(userID: sofiaID)!
check(sofiaFamily.pet.name == "Bruno" && sofiaFamily.pet.species == .dog && sofiaFamily.pet.currencyCode == "EUR", "the pet is created with its currency")
check(sofiaFamily.me.name == "Sofia" && sofiaFamily.me.nickname == "Mama" && sofiaFamily.otherParent == nil, "the creator is the first parent")
check(NameRules.isValidInviteCode(sofiaFamily.pet.inviteCode), "the invite code has the expected shape")
do {
    try await sofia.createPet(name: "Rex", species: .dog, currencyCode: "EUR", parentName: "Sofia", parentNickname: "Mama")
    check(false, "a second pet is refused")
} catch let error as DiaryError {
    check(error == .alreadyInFamily, "a second pet is refused with a clear reason")
}
do {
    try await marco.joinPet(inviteCode: "ZZZZZZ", parentName: "Marco", parentNickname: "Papà")
    check(false, "a wrong code is refused")
} catch let error as DiaryError {
    check(error == .inviteNotFound, "a wrong code is refused with a clear reason")
}
try await marco.joinPet(inviteCode: sofiaFamily.pet.inviteCode.lowercased(), parentName: "Marco", parentNickname: "Papà")
var marcoFamily = try await marco.fetchFamily(userID: marcoID)!
check(marcoFamily.me.name == "Marco" && marcoFamily.otherParent?.name == "Sofia", "the second parent joins and sees the first")
do {
    try await stranger.joinPet(inviteCode: sofiaFamily.pet.inviteCode, parentName: "Eve", parentNickname: "Eve")
    check(false, "a third person is refused")
} catch let error as DiaryError {
    check(error == .familyFull, "a third person is refused with a clear reason")
}
sofiaFamily = try await sofia.fetchFamily(userID: sofiaID)!
check(sofiaFamily.otherParent?.nickname == "Papà", "the first parent now sees the second")

// Diary
let food = try await sofia.addEntry(NewEntry(petID: sofiaFamily.pet.id, parentID: sofiaFamily.me.id, kind: .food, detail: .nothing))
check(food.kind == .food && food.detail == .nothing && food.photoPath == nil, "an entry is saved and decoded")
let anHourAgo = Date(timeIntervalSinceNow: -3600)
let walk = try await marco.addEntry(NewEntry(petID: marcoFamily.pet.id, parentID: marcoFamily.me.id, kind: .walk, detail: .long, occurredAt: anHourAgo))
check(abs(walk.occurredAt.timeIntervalSince(anHourAgo)) < 0.01, "the chosen time survives the round trip")
for kind in EntryKind.allCases {
    for option in kind.options {
        let entry = try await sofia.addEntry(NewEntry(petID: sofiaFamily.pet.id, parentID: sofiaFamily.me.id, kind: kind, detail: option.detail, occurredAt: Date(timeIntervalSinceNow: -7200)))
        guard entry.detail == option.detail, PetVoice.voiceLine(for: entry) == option.voiceLine else { check(false, "\(kind.rawValue)/\(option.detail.rawValue) is accepted"); break }
    }
}
check(true, "every kind and detail the app offers is accepted by the database")

// Photos
let photoBytes = Data((0..<4096).map { UInt8($0 % 251) })
let photoPath = try await sofia.uploadPhoto(photoBytes, petID: sofiaFamily.pet.id)
check(photoPath.hasPrefix(sofiaFamily.pet.id.uuidString.lowercased() + "/") && photoPath.hasSuffix(".jpg"), "photos go into the pet's folder")
let photo = try await sofia.addEntry(NewEntry(petID: sofiaFamily.pet.id, parentID: sofiaFamily.me.id, kind: .photo, photoPath: photoPath))
check(try await marco.downloadPhoto(path: photoPath) == photoBytes, "the other parent downloads the same bytes")

let marcoEntries = try await marco.fetchEntries(petID: marcoFamily.pet.id)
let offeredCount = EntryKind.allCases.reduce(0) { $0 + $1.options.count }
check(marcoEntries.count == 3 + offeredCount, "both parents read the whole diary")
check(marcoEntries.first?.id == photo.id, "the newest entry comes first")
check(PetVoice.diaryMessage(for: food) == "I didn't want to eat 😔", "the diary speaks in the pet's voice")
check(PetVoice.diaryMessage(for: photo) == "Look at me! 📸", "diary lines start with a capital letter")
check(marcoFamily.authorLabel(for: food) == "Sofia" && marcoFamily.authorLabel(for: walk) == "you", "entries say who the pet was with")
check(try await stranger.fetchEntries(petID: sofiaFamily.pet.id).isEmpty, "a stranger reads nothing")
check(try await stranger.fetchFamily(userID: strangerID) == nil, "a stranger has no family")

// Push
await sofia.notifyParent(entryID: food.id)
check(try await sentAlerts().isEmpty, "no push is attempted before a phone has registered")
try await marco.saveDeviceToken(String(repeating: "ab", count: 32), environment: "sandbox")
try await sofia.saveDeviceToken(String(repeating: "cd", count: 32), environment: "sandbox")
await sofia.notifyParent(entryID: food.id)
var alerts = try await sentAlerts()
check(alerts.count == 1 && alerts[0].token.hasPrefix("abab"), "only the other parent's phone is notified")
check(alerts[0].title == "Bruno 🐶" && alerts[0].body == "Papà, I didn't want to eat 😔", "the notification is in the pet's voice, by nickname")
await marco.notifyParent(entryID: walk.id)
alerts = try await sentAlerts()
check(alerts.last?.body == "Mama, I went for a long walk! 🌳" && alerts.last?.token.hasPrefix("cdcd") == true, "it works in the other direction too")
await marco.notifyParent(entryID: food.id)
check(try await sentAlerts().count == alerts.count, "only the author can announce an entry")
await sofia.notifyParent(entryID: photo.id)
check(try await sentAlerts().last?.body == "Papà, look at me! 📸", "photos are announced too")

// A token saved under the wrong environment is retried and corrected; a dead token is removed.
try await marco.saveDeviceToken("bad0" + String(repeating: "ab", count: 30), environment: "sandbox")
try await marco.saveDeviceToken("dead" + String(repeating: "ab", count: 30), environment: "production")
let beforeRetry = try await sentAlerts().count
await sofia.notifyParent(entryID: food.id)
alerts = Array(try await sentAlerts().dropFirst(beforeRetry))
check(alerts.filter { $0.token.hasPrefix("bad0") }.map(\.result) == ["BadDeviceToken", "ok"], "a wrong-environment token is retried on the other environment")
check(alerts.contains { $0.token.hasPrefix("dead") && $0.result == "Unregistered" }, "a dead token is reported by Apple")
let beforeCleanup = try await sentAlerts().count
await sofia.notifyParent(entryID: food.id)
alerts = Array(try await sentAlerts().dropFirst(beforeCleanup))
check(!alerts.contains { $0.token.hasPrefix("dead") }, "the dead token was removed")
check(alerts.filter { $0.token.hasPrefix("bad0") }.map(\.environment) == ["production"], "the corrected environment was remembered")

// Money
check(Money.cents(from: "12") == 1200 && Money.cents(from: "12,5") == 1250 && Money.cents(from: " 0.05 ") == 5 && Money.cents(from: "100000") == 10_000_000, "typed amounts are read as cents")
check(Money.cents(from: "5.") == 500, "a trailing separator is tolerated")
check(["12.345", "abc", "0", "0.00", "1.2.3", ".5", "-3", "100000.01", "", "١٢"].allSatisfy { Money.cents(from: $0) == nil }, "unusable amounts are refused")
check(ExpenseSplit.half.owedCents(amountCents: 8051, customOwedCents: nil) == 4025, "half each rounds down so the payer keeps the odd cent")
check(ExpenseSplit.otherPaysAll.owedCents(amountCents: 900, customOwedCents: nil) == 900 && ExpenseSplit.notShared.owedCents(amountCents: 900, customOwedCents: nil) == 0, "all or nothing can be owed")
check(ExpenseSplit.custom.owedCents(amountCents: 900, customOwedCents: 300) == 300 && ExpenseSplit.custom.owedCents(amountCents: 900, customOwedCents: 901) == nil && ExpenseSplit.custom.owedCents(amountCents: 900, customOwedCents: nil) == nil, "a custom part must fit inside the amount")

// Sofia pays the vet and shares it in half; Marco buys toys without sharing; Sofia buys food that Marco owes in full.
let vetExpense = try await sofia.addExpense(NewExpense(petID: sofiaFamily.pet.id, parentID: sofiaFamily.me.id, category: .vet, amountCents: 8050, owedCents: 4025))
check(vetExpense.category == .vet && vetExpense.amountCents == 8050 && vetExpense.owedCents == 4025, "an expense is saved and decoded")
let toysExpense = try await marco.addExpense(NewExpense(petID: marcoFamily.pet.id, parentID: marcoFamily.me.id, category: .toys, amountCents: 1000, owedCents: 0))
let foodExpense = try await sofia.addExpense(NewExpense(petID: sofiaFamily.pet.id, parentID: sofiaFamily.me.id, category: .food, amountCents: 2000, owedCents: 2000))
let groomingExpense = try await marco.addExpense(NewExpense(petID: marcoFamily.pet.id, parentID: marcoFamily.me.id, category: .grooming, amountCents: 3000, owedCents: 500))
var allExpenses = try await marco.fetchExpenses(petID: marcoFamily.pet.id)
check(allExpenses.count == 4, "both parents read the expenses")
check(Money.balanceCents(expenses: allExpenses, myParentID: sofiaFamily.me.id) == 5525, "the balance adds up what each expense says is owed")
check(Money.balanceCents(expenses: allExpenses, myParentID: marcoFamily.me.id) == -5525, "the other parent sees the same amount as a debt")
let parts = Money.parts(in: allExpenses, monthOf: .now, myParentID: sofiaFamily.me.id)
check(parts.mine == 4525 && parts.other == 9525 && parts.mine + parts.other == 14050, "each parent's part of the month adds up to the total")
check(marcoFamily.payerLabel(for: vetExpense) == "Sofia" && sofiaFamily.payerLabel(for: vetExpense) == "you", "expenses say who paid")
check(sofiaFamily.shareLabel(for: vetExpense)?.hasPrefix("Marco owes") == true && marcoFamily.shareLabel(for: vetExpense)?.hasPrefix("you owe") == true, "expenses say who owes what")
check(sofiaFamily.shareLabel(for: toysExpense) == "not shared", "an unshared expense says so")
await sofia.notifyParent(expenseID: vetExpense.id)
check(try await sentAlerts().last?.body == "Papà, Sofia paid the vet for me (€80.50) 🩺 Your part is €40.25.", "an expense is announced with the receiver's part")
await marco.notifyParent(expenseID: toysExpense.id)
check(try await sentAlerts().last?.body == "Mama, Marco bought me toys (€10.00) 🧸", "an unshared expense is announced without a part")
await sofia.notifyParent(expenseID: foodExpense.id)
check(try await sentAlerts().last?.body == "Papà, Sofia bought my food (€20.00) 🍖 Your part is €20.00.", "an expense owed in full says so")
await marco.notifyParent(expenseID: groomingExpense.id)
check(try await sentAlerts().last?.body == "Mama, Marco paid for my grooming (€30.00) ✂️ Your part is €5.00.", "a custom part is announced")
let payback = try await marco.addExpense(NewExpense(petID: marcoFamily.pet.id, parentID: marcoFamily.me.id, category: .settleUp, amountCents: 5525, owedCents: 5525))
check(marcoFamily.shareLabel(for: payback) == nil, "a payback has no share line")
await marco.notifyParent(expenseID: payback.id)
check(try await sentAlerts().last?.body == "Mama, Marco paid you back €55.25 🤝", "a payback is announced too")
allExpenses = try await sofia.fetchExpenses(petID: sofiaFamily.pet.id)
check(Money.balanceCents(expenses: allExpenses, myParentID: sofiaFamily.me.id) == 0, "paying back settles the balance")
check(Money.spending(in: allExpenses, monthOf: .now) == [CategoryTotal(category: .vet, amountCents: 8050), CategoryTotal(category: .grooming, amountCents: 3000), CategoryTotal(category: .food, amountCents: 2000), CategoryTotal(category: .toys, amountCents: 1000)], "the month summary lists spending, largest first, without paybacks")
check(Money.spending(in: allExpenses, monthOf: Date(timeIntervalSinceNow: -90 * 86400)).isEmpty, "other months are not mixed in")
for category in ExpenseCategory.allCases {
    _ = try await sofia.addExpense(NewExpense(petID: sofiaFamily.pet.id, parentID: sofiaFamily.me.id, category: category, amountCents: 100, owedCents: 100, spentAt: Date(timeIntervalSinceNow: -200 * 86400)))
}
check(true, "every category the app offers is accepted by the database")
do {
    _ = try await sofia.addExpense(NewExpense(petID: sofiaFamily.pet.id, parentID: sofiaFamily.me.id, category: .food, amountCents: 100, owedCents: 101))
    check(false, "the database refuses a part bigger than the amount")
} catch {
    check(true, "the database refuses a part bigger than the amount")
}
check(try await stranger.fetchExpenses(petID: sofiaFamily.pet.id).isEmpty, "a stranger reads no expenses")
try await marco.deleteExpense(vetExpense)
check(try await sofia.fetchExpenses(petID: sofiaFamily.pet.id).contains { $0.id == vetExpense.id }, "a parent cannot delete the other parent's expense")
try await sofia.deleteExpense(vetExpense)
check(!(try await marco.fetchExpenses(petID: marcoFamily.pet.id)).contains { $0.id == vetExpense.id }, "a parent can delete their own expense")
check(Money.format(cents: 8050, currencyCode: "EUR").contains("80") && Money.format(cents: 5, currencyCode: "EUR").contains("05"), "amounts are formatted as money")

// Family settings
try await marco.updateParent(id: marcoFamily.me.id, name: "Marco", nickname: "Daddy")
try await sofia.updatePet(id: sofiaFamily.pet.id, name: "Brunello", species: .cat, currencyCode: "GBP")
try await sofia.updatePetPhoto(id: sofiaFamily.pet.id, photoPath: photoPath)
marcoFamily = try await marco.fetchFamily(userID: marcoID)!
check(marcoFamily.me.nickname == "Daddy" && marcoFamily.pet.name == "Brunello" && marcoFamily.pet.species == .cat && marcoFamily.pet.currencyCode == "GBP" && marcoFamily.pet.photoPath == photoPath, "names, species, currency and the pet photo can be changed")
try await stranger.updatePet(id: sofiaFamily.pet.id, name: "Hacked", species: .dog, currencyCode: "USD")
check(try await sofia.fetchFamily(userID: sofiaID)?.pet.name == "Brunello", "a stranger cannot rename the pet")

// Deleting
try await marco.deleteEntry(food)
check(try await sofia.fetchEntries(petID: sofiaFamily.pet.id).contains { $0.id == food.id }, "a parent cannot delete the other parent's entry")
try await sofia.deleteEntry(photo)
check(!(try await marco.fetchEntries(petID: marcoFamily.pet.id)).contains { $0.id == photo.id }, "a parent can delete their own entry")
do {
    _ = try await marco.downloadPhoto(path: photoPath)
    check(false, "a deleted photo is gone")
} catch {
    check(true, "a deleted photo is gone")
}

print("\nALL \(passed) DATA LAYER CHECKS PASSED")
