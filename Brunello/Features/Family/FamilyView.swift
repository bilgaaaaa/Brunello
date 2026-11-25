import SwiftUI
import UserNotifications

/// Settings for the pet, the two parents and notifications.
struct FamilyView: View {
    @Environment(AppState.self) private var appState
    let family: Family

    @State private var petName = ""
    @State private var species = Species.dog
    @State private var currencyCode = Money.fallbackCurrencyCode
    @State private var name = ""
    @State private var nickname = ""
    @State private var isChoosingPetPhoto = false
    @State private var notificationStatus = UNAuthorizationStatus.notDetermined

    private var isPetChanged: Bool {
        NameRules.clean(petName) != family.pet.name || species != family.pet.species || currencyCode != family.pet.currencyCode
    }

    private var isMeChanged: Bool {
        NameRules.clean(name) != family.me.name || NameRules.clean(nickname) != family.me.nickname
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Family")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                petCard
                SectionLabel("Parents (2 seats)")
                parentsCard
                if family.otherParent == nil {
                    InviteCard(pet: family.pet)
                }
                SectionLabel("My name")
                nameCard
                SectionLabel("\(family.pet.name) calls me")
                nicknameCard
                SectionLabel("Notifications")
                notificationsCard
                ruleCard
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .onAppear(perform: loadFields)
        .onChange(of: family) { _, _ in loadFields() }
        .task { notificationStatus = await PushService.status() }
        .photoSourcePicker(isPresented: $isChoosingPetPhoto, title: "A picture of \(family.pet.name)") { image in
            Task { await appState.updatePetPhoto(image) }
        }
    }

    // MARK: - Cards

    private var petCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    isChoosingPetPhoto = true
                } label: {
                    PetAvatar(pet: family.pet, size: 64)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.brand, Theme.card)
                        }
                }
                .accessibilityLabel("Change \(family.pet.name)'s picture")
                TextField("Pet name", text: $petName)
                    .textFieldStyle(FieldStyle())
                    .autocorrectionDisabled()
            }
            Picker("Kind of pet", selection: $species) {
                ForEach(Species.allCases) { choice in
                    Text("\(choice.emoji) \(choice.label)").tag(choice)
                }
            }
            .pickerStyle(.segmented)
            HStack {
                Text("Currency for expenses")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                Spacer(minLength: 8)
                Picker("Currency for expenses", selection: $currencyCode) {
                    ForEach(Money.currencyChoices(including: family.pet.currencyCode), id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
                .pickerStyle(.menu)
            }
            if isPetChanged {
                Button("Save") {
                    Task { await appState.updatePet(name: petName, species: species, currencyCode: currencyCode) }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!NameRules.isValidPetName(petName))
            }
        }
        .card()
    }

    private var parentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            parentRow(family.me, isMe: true)
            if let otherParent = family.otherParent {
                parentRow(otherParent, isMe: false)
            } else {
                Text("The second seat is empty. Send the invite code below.")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .card()
    }

    private func parentRow(_ parent: Parent, isMe: Bool) -> some View {
        HStack(spacing: 10) {
            Text(isMe ? "💜" : "🧡")
                .frame(width: 36, height: 36)
                .background(Theme.background, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(parent.name).font(.headline).foregroundStyle(Theme.ink)
                Text("\(family.pet.name) says \"\(parent.nickname)\"")
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
            if isMe {
                Text("you")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Theme.brand)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.brand.opacity(0.14), in: Capsule())
            }
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Your name", text: $name)
                .textFieldStyle(FieldStyle())
                .textContentType(.givenName)
                .autocorrectionDisabled()
            Text("The other parent sees this name in the diary.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            saveMeButton
        }
        .card()
    }

    private var nicknameCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            NicknameChips(nickname: $nickname)
            TextField("Or type your own", text: $nickname)
                .textFieldStyle(FieldStyle())
                .autocorrectionDisabled()
            Text("Your notifications start with it: \"\(NameRules.clean(nickname)), I made a good poo!\"")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            saveMeButton
        }
        .card()
    }

    @ViewBuilder
    private var saveMeButton: some View {
        if isMeChanged {
            Button("Save") {
                Task { await appState.updateMe(name: name, nickname: nickname) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!NameRules.isValidParentName(name) || !NameRules.isValidParentName(nickname))
        }
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch notificationStatus {
            case .notDetermined:
                Text("Hear from \(family.pet.name) the moment something is logged.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Button("Turn on notifications") {
                    Task {
                        await PushService.requestAuthorization()
                        notificationStatus = await PushService.status()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            case .denied:
                Text("Notifications are off for Brunello. Turn them on in Settings to hear from \(family.pet.name).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            default:
                Label("On. \(family.pet.name) will tell you right away.", systemImage: "bell.badge.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .card()
    }

    private var ruleCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No chat, on purpose.").font(.headline).foregroundStyle(Theme.ink)
            Text("Brunello only carries \(family.pet.name)'s updates. There is no message box anywhere in the app.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EntryKind.walk.tint, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    /// Fills the text fields from the saved family.
    private func loadFields() {
        petName = family.pet.name
        species = family.pet.species
        currencyCode = family.pet.currencyCode
        name = family.me.name
        nickname = family.me.nickname
    }
}
