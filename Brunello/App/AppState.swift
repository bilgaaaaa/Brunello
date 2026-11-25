import OSLog
import SwiftUI

/// The app's single source of truth: who is signed in, their family and the pet's diary.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case loading
        case setupNeeded
        case failed
        case onboarding
        case ready
    }

    private(set) var phase: Phase = .loading
    /// The technical reason the last start failed, shown in small print to help with setup problems.
    private(set) var startErrorDetail: String?
    private(set) var family: Family?
    private(set) var entries: [Entry] = []
    private(set) var expenses: [Expense] = []
    private(set) var toast: Toast?
    private(set) var isSendingPhoto = false

    private let service = DiaryService.shared
    private var userID: UUID?
    private var changesTask: Task<Void, Never>?
    private var isRefreshing = false
    private var isRefreshQueued = false

    // MARK: - Starting up

    /// Signs in and loads the family; also used by the "Try again" button.
    func start() async {
        guard AppConfig.isConfigured else {
            phase = .setupNeeded
            return
        }
        phase = .loading
        startErrorDetail = nil
        do {
            userID = try await service.signIn()
            try await loadFamily()
        } catch {
            Logger.app.error("Start failed: \(error.localizedDescription, privacy: .public)")
            startErrorDetail = error.localizedDescription
            phase = .failed
        }
    }

    /// Called whenever the app comes to the front.
    func appBecameActive() async {
        guard phase == .ready else { return }
        startObservingChanges()
        await refresh()
    }

    private func loadFamily() async throws {
        guard let userID else { return }
        guard let family = try await service.fetchFamily(userID: userID) else {
            self.family = nil
            entries = []
            expenses = []
            phase = .onboarding
            return
        }
        try await loadDiary(for: family)
        phase = .ready
        Logger.app.info("Family loaded: \(self.entries.count) entries, \(self.expenses.count) expenses")
        startObservingChanges()
        await PushService.registerIfAuthorized()
    }

    /// Fetches the diary and the expenses together and shows them with the given family.
    private func loadDiary(for family: Family) async throws {
        async let loadedEntries = service.fetchEntries(petID: family.pet.id)
        async let loadedExpenses = service.fetchExpenses(petID: family.pet.id)
        let (newEntries, newExpenses) = try await (loadedEntries, loadedExpenses)
        self.family = family
        entries = newEntries
        expenses = newExpenses
    }

    // MARK: - Onboarding

    func createPet(name: String, species: Species, parentName: String, parentNickname: String) async throws {
        try await service.createPet(
            name: NameRules.clean(name),
            species: species,
            currencyCode: Money.deviceCurrencyCode,
            parentName: NameRules.clean(parentName),
            parentNickname: NameRules.clean(parentNickname)
        )
        Logger.app.info("Pet created")
        try await finishOnboarding()
    }

    func joinPet(inviteCode: String, parentName: String, parentNickname: String) async throws {
        try await service.joinPet(
            inviteCode: NameRules.cleanInviteCode(inviteCode),
            parentName: NameRules.clean(parentName),
            parentNickname: NameRules.clean(parentNickname)
        )
        Logger.app.info("Joined a pet's family")
        try await finishOnboarding()
    }

    private func finishOnboarding() async throws {
        try await loadFamily()
        await PushService.requestAuthorization()
    }

    // MARK: - Diary

    /// Reloads the family and the diary. Safe to call often: overlapping calls are folded into one more pass.
    func refresh() async {
        guard phase == .ready, let userID else { return }
        if isRefreshing {
            isRefreshQueued = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            isRefreshQueued = false
            do {
                guard let family = try await service.fetchFamily(userID: userID) else { return }
                try await loadDiary(for: family)
                Logger.diary.debug("Refreshed: \(self.entries.count) entries, \(self.expenses.count) expenses")
            } catch {
                Logger.diary.error("Refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        } while isRefreshQueued
    }

    func logEntry(kind: EntryKind, detail: EntryDetail, occurredAt: Date) async {
        guard let family else { return }
        let newEntry = NewEntry(petID: family.pet.id, parentID: family.me.id, kind: kind, detail: detail, occurredAt: occurredAt)
        await addEntry(newEntry, family: family)
    }

    func sendPhoto(_ image: UIImage) async {
        guard let family, !isSendingPhoto else { return }
        guard let data = image.jpegDataForUpload(), let uploadedImage = UIImage(data: data) else {
            showToast("That picture could not be read")
            return
        }
        isSendingPhoto = true
        defer { isSendingPhoto = false }
        do {
            let photoPath = try await service.uploadPhoto(data, petID: family.pet.id)
            await PhotoStore.shared.store(uploadedImage, data: data, for: photoPath)
            let newEntry = NewEntry(petID: family.pet.id, parentID: family.me.id, kind: .photo, photoPath: photoPath)
            await addEntry(newEntry, family: family)
        } catch {
            Logger.photos.error("Photo upload failed: \(error.localizedDescription, privacy: .public)")
            showToast("Could not send the photo. Check your connection.")
        }
    }

    func deleteEntry(_ entry: Entry) async {
        do {
            try await service.deleteEntry(entry)
            entries.removeAll { $0.id == entry.id }
            Logger.diary.info("Entry deleted")
            showToast("Removed from the diary")
        } catch {
            Logger.diary.error("Delete failed: \(error.localizedDescription, privacy: .public)")
            showToast("Could not remove it. Check your connection.")
        }
    }

    /// Saves the entry, shows it in the diary and asks the server to tell the other parent.
    private func addEntry(_ newEntry: NewEntry, family: Family) async {
        do {
            let entry = try await service.addEntry(newEntry)
            if !entries.contains(where: { $0.id == entry.id }) {
                entries.append(entry)
                entries.sort { $0.occurredAt > $1.occurredAt }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Logger.diary.info("Entry saved: \(entry.kind.rawValue, privacy: .public)")
            if let otherParent = family.otherParent {
                showToast("Sent to \(otherParent.name) 💌")
                Task { await service.notifyParent(entryID: entry.id) }
            } else {
                showToast("Saved in the diary ✓")
            }
        } catch {
            Logger.diary.error("Saving an entry failed: \(error.localizedDescription, privacy: .public)")
            showToast("Could not save. Check your connection.")
        }
    }

    // MARK: - Money

    func addExpense(category: ExpenseCategory, amountCents: Int, spentAt: Date) async {
        guard let family else { return }
        let newExpense = NewExpense(petID: family.pet.id, parentID: family.me.id, category: category, amountCents: amountCents, spentAt: spentAt)
        do {
            let expense = try await service.addExpense(newExpense)
            if !expenses.contains(where: { $0.id == expense.id }) {
                expenses.append(expense)
                expenses.sort { $0.spentAt > $1.spentAt }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Logger.diary.info("Expense saved: \(expense.category.rawValue, privacy: .public)")
            if let otherParent = family.otherParent {
                showToast("Sent to \(otherParent.name) 💌")
                Task { await service.notifyParent(expenseID: expense.id) }
            } else {
                showToast("Saved ✓")
            }
        } catch {
            Logger.diary.error("Saving an expense failed: \(error.localizedDescription, privacy: .public)")
            showToast("Could not save. Check your connection.")
        }
    }

    /// Records that I paid the other parent back.
    func settleUp(amountCents: Int) async {
        await addExpense(category: .settleUp, amountCents: amountCents, spentAt: .now)
    }

    func deleteExpense(_ expense: Expense) async {
        do {
            try await service.deleteExpense(expense)
            expenses.removeAll { $0.id == expense.id }
            Logger.diary.info("Expense deleted")
            showToast("Removed")
        } catch {
            Logger.diary.error("Deleting an expense failed: \(error.localizedDescription, privacy: .public)")
            showToast("Could not remove it. Check your connection.")
        }
    }

    // MARK: - Family settings

    func updatePet(name: String, species: Species, currencyCode: String) async {
        guard let family else { return }
        do {
            try await service.updatePet(id: family.pet.id, name: NameRules.clean(name), species: species, currencyCode: currencyCode)
            await refresh()
            showToast("Saved ✓")
        } catch {
            Logger.app.error("Updating the pet failed: \(error.localizedDescription, privacy: .public)")
            showToast("Could not save. Check your connection.")
        }
    }

    func updatePetPhoto(_ image: UIImage) async {
        guard let family else { return }
        guard let data = image.jpegDataForUpload(maxDimension: 600), let uploadedImage = UIImage(data: data) else {
            showToast("That picture could not be read")
            return
        }
        do {
            let photoPath = try await service.uploadPhoto(data, petID: family.pet.id)
            await PhotoStore.shared.store(uploadedImage, data: data, for: photoPath)
            try await service.updatePetPhoto(id: family.pet.id, photoPath: photoPath)
            await refresh()
            showToast("New picture saved ✓")
        } catch {
            Logger.photos.error("Updating the pet photo failed: \(error.localizedDescription, privacy: .public)")
            showToast("Could not save the picture. Check your connection.")
        }
    }

    func updateMe(name: String, nickname: String) async {
        guard let family else { return }
        do {
            try await service.updateParent(id: family.me.id, name: NameRules.clean(name), nickname: NameRules.clean(nickname))
            await refresh()
            showToast("Saved ✓")
        } catch {
            Logger.app.error("Updating my name failed: \(error.localizedDescription, privacy: .public)")
            showToast("Could not save. Check your connection.")
        }
    }

    // MARK: - Toast

    func showToast(_ text: String) {
        toast = Toast(text: text)
    }

    func clearToast(_ shown: Toast) {
        if toast == shown { toast = nil }
    }

    // MARK: - Live updates

    /// Keeps one live connection open; it is restarted the next time the app comes to the front if it drops.
    private func startObservingChanges() {
        guard changesTask == nil else { return }
        changesTask = Task { [weak self, service] in
            await service.observeChanges { [weak self] in await self?.refresh() }
            self?.changesTask = nil
        }
    }
}
