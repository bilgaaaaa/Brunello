import Foundation
import OSLog
import Supabase

/// Every server call in one place: sign-in, the family, diary entries, photos and push.
struct DiaryService: Sendable {
    static let shared = DiaryService(
        client: SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseKey,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    )

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Sign-in

    /// Returns the signed-in person's id. The first launch quietly creates an anonymous account on this phone.
    func signIn() async throws -> UUID {
        if client.auth.currentSession != nil {
            return try await client.auth.session.user.id
        }
        let session = try await client.auth.signInAnonymously()
        Logger.app.info("Created a new account for this phone")
        return session.user.id
    }

    // MARK: - Family

    /// Loads the pet and its parents, or nil when this person has not created or joined a pet yet.
    func fetchFamily(userID: UUID) async throws -> Family? {
        let pets: [Pet] = try await client.from("pets").select().limit(1).execute().value
        guard let pet = pets.first else { return nil }

        let parents: [Parent] = try await client.from("parents")
            .select()
            .eq("pet_id", value: pet.id)
            .order("created_at")
            .execute()
            .value
        guard let me = parents.first(where: { $0.userID == userID }) else { return nil }
        return Family(pet: pet, me: me, otherParent: parents.first { $0.userID != userID })
    }

    func createPet(name: String, species: Species, currencyCode: String, parentName: String, parentNickname: String) async throws {
        try await callFamilyAction("create_pet", params: [
            "pet_name": name,
            "pet_species": species.rawValue,
            "pet_currency_code": currencyCode,
            "parent_name": parentName,
            "parent_nickname": parentNickname,
        ])
    }

    func joinPet(inviteCode: String, parentName: String, parentNickname: String) async throws {
        try await callFamilyAction("join_pet", params: [
            "code": inviteCode,
            "parent_name": parentName,
            "parent_nickname": parentNickname,
        ])
    }

    func updatePet(id: UUID, name: String, species: Species, currencyCode: String) async throws {
        try await client.from("pets")
            .update(["name": name, "species": species.rawValue, "currency_code": currencyCode])
            .eq("id", value: id)
            .execute()
    }

    func updatePetPhoto(id: UUID, photoPath: String) async throws {
        try await client.from("pets")
            .update(["photo_path": photoPath])
            .eq("id", value: id)
            .execute()
    }

    func updateParent(id: UUID, name: String, nickname: String) async throws {
        try await client.from("parents")
            .update(["name": name, "nickname": nickname])
            .eq("id", value: id)
            .execute()
    }

    /// Runs a database function and turns its known error words into `DiaryError`.
    private func callFamilyAction(_ function: String, params: [String: String]) async throws {
        do {
            try await client.rpc(function, params: params).execute()
        } catch let error as PostgrestError {
            if let diaryError = DiaryError(serverMessage: error.message) { throw diaryError }
            throw error
        }
    }

    // MARK: - Diary

    /// The newest entries first, up to `AppConfig.entriesLimit`.
    func fetchEntries(petID: UUID) async throws -> [Entry] {
        try await client.from("entries")
            .select()
            .eq("pet_id", value: petID)
            .order("occurred_at", ascending: false)
            .limit(AppConfig.entriesLimit)
            .execute()
            .value
    }

    func addEntry(_ newEntry: NewEntry) async throws -> Entry {
        try await client.from("entries")
            .insert(newEntry)
            .select()
            .single()
            .execute()
            .value
    }

    /// Removes an entry, and its picture when it is a photo.
    func deleteEntry(_ entry: Entry) async throws {
        try await client.from("entries").delete().eq("id", value: entry.id).execute()
        guard let photoPath = entry.photoPath else { return }
        do {
            try await client.storage.from(AppConfig.photosBucket).remove(paths: [photoPath])
        } catch {
            Logger.photos.error("Entry deleted but its photo stayed behind: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Money

    /// The newest expenses first, up to `AppConfig.entriesLimit`.
    func fetchExpenses(petID: UUID) async throws -> [Expense] {
        try await client.from("expenses")
            .select()
            .eq("pet_id", value: petID)
            .order("spent_at", ascending: false)
            .limit(AppConfig.entriesLimit)
            .execute()
            .value
    }

    func addExpense(_ newExpense: NewExpense) async throws -> Expense {
        try await client.from("expenses")
            .insert(newExpense)
            .select()
            .single()
            .execute()
            .value
    }

    func deleteExpense(_ expense: Expense) async throws {
        try await client.from("expenses").delete().eq("id", value: expense.id).execute()
    }

    // MARK: - Photos

    /// Uploads a JPEG into the pet's folder and returns its path.
    func uploadPhoto(_ data: Data, petID: UUID) async throws -> String {
        let path = "\(petID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        try await client.storage.from(AppConfig.photosBucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg"))
        return path
    }

    func downloadPhoto(path: String) async throws -> Data {
        try await client.storage.from(AppConfig.photosBucket).download(path: path)
    }

    // MARK: - Push

    func saveDeviceToken(_ token: String, environment: String) async throws {
        try await client.rpc("save_device_token", params: [
            "device_token": token,
            "device_environment": environment,
        ]).execute()
    }

    /// Asks the server to tell the other parent about a new entry. A failed push never blocks the diary.
    func notifyParent(entryID: UUID) async {
        await notifyParent(body: ["entry_id": entryID.uuidString.lowercased()])
    }

    /// Asks the server to tell the other parent about a new expense or payback.
    func notifyParent(expenseID: UUID) async {
        await notifyParent(body: ["expense_id": expenseID.uuidString.lowercased()])
    }

    private func notifyParent(body: [String: String]) async {
        do {
            try await client.functions.invoke("notify-parent", options: FunctionInvokeOptions(body: body))
        } catch {
            Logger.push.error("Could not notify the other parent: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Live updates

    /// Calls `onChange` each time the diary or the family changes on the server, until the task is cancelled.
    func observeChanges(onChange: @escaping @Sendable () async -> Void) async {
        let channel = client.channel("brunello-changes")
        let changes = channel.postgresChange(AnyAction.self, schema: "public")
        do {
            try await channel.subscribeWithError()
            Logger.diary.info("Live updates connected")
            for await _ in changes {
                await onChange()
            }
        } catch {
            Logger.diary.error("Live updates stopped: \(error.localizedDescription, privacy: .public)")
        }
        await client.removeChannel(channel)
    }
}
