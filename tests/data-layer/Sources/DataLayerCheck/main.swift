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

let bilge = makeService(), luigi = makeService(), stranger = makeService()

// Sign-in
let bilgeID = try await bilge.signIn()
check(try await bilge.signIn() == bilgeID, "a second sign-in reuses the stored session")
let luigiID = try await luigi.signIn()
let strangerID = try await stranger.signIn()
check(Set([bilgeID, luigiID, strangerID]).count == 3, "every phone gets its own account")
check(try await bilge.fetchFamily(userID: bilgeID) == nil, "no family before onboarding")

// Onboarding
try await bilge.createPet(name: "Bruno", species: .dog, currencyCode: "eur", parentName: "Bilge", parentNickname: "Mama")
var bilgeFamily = try await bilge.fetchFamily(userID: bilgeID)!
check(bilgeFamily.pet.name == "Bruno" && bilgeFamily.pet.species == .dog && bilgeFamily.pet.currencyCode == "EUR", "the pet is created with its currency")
check(bilgeFamily.me.name == "Bilge" && bilgeFamily.me.nickname == "Mama" && bilgeFamily.otherParent == nil, "the creator is the first parent")
check(NameRules.isValidInviteCode(bilgeFamily.pet.inviteCode), "the invite code has the expected shape")
do {
    try await bilge.createPet(name: "Rex", species: .dog, currencyCode: "EUR", parentName: "Bilge", parentNickname: "Mama")
    check(false, "a second pet is refused")
} catch let error as DiaryError {
    check(error == .alreadyInFamily, "a second pet is refused with a clear reason")
}
do {
    try await luigi.joinPet(inviteCode: "ZZZZZZ", parentName: "Luigi", parentNickname: "Papà")
    check(false, "a wrong code is refused")
} catch let error as DiaryError {
    check(error == .inviteNotFound, "a wrong code is refused with a clear reason")
}
try await luigi.joinPet(inviteCode: bilgeFamily.pet.inviteCode.lowercased(), parentName: "Luigi", parentNickname: "Papà")
var luigiFamily = try await luigi.fetchFamily(userID: luigiID)!
check(luigiFamily.me.name == "Luigi" && luigiFamily.otherParent?.name == "Bilge", "the second parent joins and sees the first")
do {
    try await stranger.joinPet(inviteCode: bilgeFamily.pet.inviteCode, parentName: "Eve", parentNickname: "Eve")
    check(false, "a third person is refused")
} catch let error as DiaryError {
    check(error == .familyFull, "a third person is refused with a clear reason")
}
bilgeFamily = try await bilge.fetchFamily(userID: bilgeID)!
check(bilgeFamily.otherParent?.nickname == "Papà", "the first parent now sees the second")

// Diary
let food = try await bilge.addEntry(NewEntry(petID: bilgeFamily.pet.id, parentID: bilgeFamily.me.id, kind: .food, detail: .nothing))
check(food.kind == .food && food.detail == .nothing && food.photoPath == nil, "an entry is saved and decoded")
let anHourAgo = Date(timeIntervalSinceNow: -3600)
let walk = try await luigi.addEntry(NewEntry(petID: luigiFamily.pet.id, parentID: luigiFamily.me.id, kind: .walk, detail: .long, occurredAt: anHourAgo))
check(abs(walk.occurredAt.timeIntervalSince(anHourAgo)) < 0.01, "the chosen time survives the round trip")
for kind in EntryKind.allCases {
    for option in kind.options {
        let entry = try await bilge.addEntry(NewEntry(petID: bilgeFamily.pet.id, parentID: bilgeFamily.me.id, kind: kind, detail: option.detail, occurredAt: Date(timeIntervalSinceNow: -7200)))
        guard entry.detail == option.detail, PetVoice.voiceLine(for: entry) == option.voiceLine else { check(false, "\(kind.rawValue)/\(option.detail.rawValue) is accepted"); break }
    }
}
check(true, "every kind and detail the app offers is accepted by the database")

// Photos
let photoBytes = Data((0..<4096).map { UInt8($0 % 251) })
let photoPath = try await bilge.uploadPhoto(photoBytes, petID: bilgeFamily.pet.id)
check(photoPath.hasPrefix(bilgeFamily.pet.id.uuidString.lowercased() + "/") && photoPath.hasSuffix(".jpg"), "photos go into the pet's folder")
let photo = try await bilge.addEntry(NewEntry(petID: bilgeFamily.pet.id, parentID: bilgeFamily.me.id, kind: .photo, photoPath: photoPath))
check(try await luigi.downloadPhoto(path: photoPath) == photoBytes, "the other parent downloads the same bytes")

let luigiEntries = try await luigi.fetchEntries(petID: luigiFamily.pet.id)
let offeredCount = EntryKind.allCases.reduce(0) { $0 + $1.options.count }
check(luigiEntries.count == 3 + offeredCount, "both parents read the whole diary")
check(luigiEntries.first?.id == photo.id, "the newest entry comes first")
check(PetVoice.diaryMessage(for: food) == "I didn't want to eat 😔", "the diary speaks in the pet's voice")
check(PetVoice.diaryMessage(for: photo) == "Look at me! 📸", "diary lines start with a capital letter")
check(luigiFamily.authorLabel(for: food) == "Bilge" && luigiFamily.authorLabel(for: walk) == "you", "entries say who the pet was with")
check(try await stranger.fetchEntries(petID: bilgeFamily.pet.id).isEmpty, "a stranger reads nothing")
check(try await stranger.fetchFamily(userID: strangerID) == nil, "a stranger has no family")

// Push
await bilge.notifyParent(entryID: food.id)
check(try await sentAlerts().isEmpty, "no push is attempted before a phone has registered")
try await luigi.saveDeviceToken(String(repeating: "ab", count: 32), environment: "sandbox")
try await bilge.saveDeviceToken(String(repeating: "cd", count: 32), environment: "sandbox")
await bilge.notifyParent(entryID: food.id)
var alerts = try await sentAlerts()
check(alerts.count == 1 && alerts[0].token.hasPrefix("abab"), "only the other parent's phone is notified")
check(alerts[0].title == "Bruno 🐶" && alerts[0].body == "Papà, I didn't want to eat 😔", "the notification is in the pet's voice, by nickname")
await luigi.notifyParent(entryID: walk.id)
alerts = try await sentAlerts()
check(alerts.last?.body == "Mama, I went for a long walk! 🌳" && alerts.last?.token.hasPrefix("cdcd") == true, "it works in the other direction too")
await luigi.notifyParent(entryID: food.id)
check(try await sentAlerts().count == alerts.count, "only the author can announce an entry")
await bilge.notifyParent(entryID: photo.id)
check(try await sentAlerts().last?.body == "Papà, look at me! 📸", "photos are announced too")

// A token saved under the wrong environment is retried and corrected; a dead token is removed.
try await luigi.saveDeviceToken("bad0" + String(repeating: "ab", count: 30), environment: "sandbox")
try await luigi.saveDeviceToken("dead" + String(repeating: "ab", count: 30), environment: "production")
let beforeRetry = try await sentAlerts().count
await bilge.notifyParent(entryID: food.id)
alerts = Array(try await sentAlerts().dropFirst(beforeRetry))
check(alerts.filter { $0.token.hasPrefix("bad0") }.map(\.result) == ["BadDeviceToken", "ok"], "a wrong-environment token is retried on the other environment")
check(alerts.contains { $0.token.hasPrefix("dead") && $0.result == "Unregistered" }, "a dead token is reported by Apple")
let beforeCleanup = try await sentAlerts().count
await bilge.notifyParent(entryID: food.id)
alerts = Array(try await sentAlerts().dropFirst(beforeCleanup))
check(!alerts.contains { $0.token.hasPrefix("dead") }, "the dead token was removed")
check(alerts.filter { $0.token.hasPrefix("bad0") }.map(\.environment) == ["production"], "the corrected environment was remembered")

// Money
check(Money.cents(from: "12") == 1200 && Money.cents(from: "12,5") == 1250 && Money.cents(from: " 0.05 ") == 5 && Money.cents(from: "100000") == 10_000_000, "typed amounts are read as cents")
check(Money.cents(from: "5.") == 500, "a trailing separator is tolerated")
check(["12.345", "abc", "0", "0.00", "1.2.3", ".5", "-3", "100000.01", "", "١٢"].allSatisfy { Money.cents(from: $0) == nil }, "unusable amounts are refused")
let vet = try await bilge.addExpense(NewExpense(petID: bilgeFamily.pet.id, parentID: bilgeFamily.me.id, category: .vet, amountCents: 8050))
check(vet.category == .vet && vet.amountCents == 8050, "an expense is saved and decoded")
_ = try await luigi.addExpense(NewExpense(petID: luigiFamily.pet.id, parentID: luigiFamily.me.id, category: .toys, amountCents: 1000))
var allExpenses = try await luigi.fetchExpenses(petID: luigiFamily.pet.id)
check(allExpenses.count == 2, "both parents read the expenses")
check(Money.balanceCents(expenses: allExpenses, myParentID: bilgeFamily.me.id) == 3525, "the parent who paid more is owed half the difference")
check(Money.balanceCents(expenses: allExpenses, myParentID: luigiFamily.me.id) == -3525, "the other parent sees the same amount as a debt")
check(luigiFamily.payerLabel(for: vet) == "Bilge" && bilgeFamily.payerLabel(for: vet) == "you", "expenses say who paid")
await bilge.notifyParent(expenseID: vet.id)
check(try await sentAlerts().last?.body == "Papà, Bilge paid the vet for me (€80.50) 🩺", "an expense is announced in the pet's voice")
let payback = try await luigi.addExpense(NewExpense(petID: luigiFamily.pet.id, parentID: luigiFamily.me.id, category: .settleUp, amountCents: 3525))
await luigi.notifyParent(expenseID: payback.id)
check(try await sentAlerts().last?.body == "Mama, Luigi paid you back €35.25 🤝", "a payback is announced too")
allExpenses = try await bilge.fetchExpenses(petID: bilgeFamily.pet.id)
check(Money.balanceCents(expenses: allExpenses, myParentID: bilgeFamily.me.id) == 0, "paying back settles the balance")
check(Money.spending(in: allExpenses, monthOf: .now) == [CategoryTotal(category: .vet, amountCents: 8050), CategoryTotal(category: .toys, amountCents: 1000)], "the month summary lists spending, largest first, without paybacks")
check(Money.spending(in: allExpenses, monthOf: Date(timeIntervalSinceNow: -90 * 86400)).isEmpty, "other months are not mixed in")
for category in ExpenseCategory.allCases {
    _ = try await bilge.addExpense(NewExpense(petID: bilgeFamily.pet.id, parentID: bilgeFamily.me.id, category: category, amountCents: 100, spentAt: Date(timeIntervalSinceNow: -200 * 86400)))
}
check(true, "every category the app offers is accepted by the database")
check(try await stranger.fetchExpenses(petID: bilgeFamily.pet.id).isEmpty, "a stranger reads no expenses")
try await luigi.deleteExpense(vet)
check(try await bilge.fetchExpenses(petID: bilgeFamily.pet.id).contains { $0.id == vet.id }, "a parent cannot delete the other parent's expense")
try await bilge.deleteExpense(vet)
check(!(try await luigi.fetchExpenses(petID: luigiFamily.pet.id)).contains { $0.id == vet.id }, "a parent can delete their own expense")
check(Money.format(cents: 8050, currencyCode: "EUR").contains("80") && Money.format(cents: 5, currencyCode: "EUR").contains("05"), "amounts are formatted as money")

// Family settings
try await luigi.updateParent(id: luigiFamily.me.id, name: "Luigi", nickname: "Daddy")
try await bilge.updatePet(id: bilgeFamily.pet.id, name: "Brunello", species: .cat, currencyCode: "GBP")
try await bilge.updatePetPhoto(id: bilgeFamily.pet.id, photoPath: photoPath)
luigiFamily = try await luigi.fetchFamily(userID: luigiID)!
check(luigiFamily.me.nickname == "Daddy" && luigiFamily.pet.name == "Brunello" && luigiFamily.pet.species == .cat && luigiFamily.pet.currencyCode == "GBP" && luigiFamily.pet.photoPath == photoPath, "names, species, currency and the pet photo can be changed")
try await stranger.updatePet(id: bilgeFamily.pet.id, name: "Hacked", species: .dog, currencyCode: "USD")
check(try await bilge.fetchFamily(userID: bilgeID)?.pet.name == "Brunello", "a stranger cannot rename the pet")

// Deleting
try await luigi.deleteEntry(food)
check(try await bilge.fetchEntries(petID: bilgeFamily.pet.id).contains { $0.id == food.id }, "a parent cannot delete the other parent's entry")
try await bilge.deleteEntry(photo)
check(!(try await luigi.fetchEntries(petID: luigiFamily.pet.id)).contains { $0.id == photo.id }, "a parent can delete their own entry")
do {
    _ = try await luigi.downloadPhoto(path: photoPath)
    check(false, "a deleted photo is gone")
} catch {
    check(true, "a deleted photo is gone")
}

print("\nALL \(passed) DATA LAYER CHECKS PASSED")
