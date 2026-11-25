import OSLog
import SwiftUI

/// First launch: who you are, then either add your pet or join it with the other parent's invite code.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    private enum Step {
        case welcome, me, choice, create, join
    }

    @State private var step = Step.welcome
    @State private var name = ""
    @State private var nickname = ""
    @State private var petName = ""
    @State private var species = Species.dog
    @State private var inviteCode = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                switch step {
                case .welcome: welcomeStep
                case .me: meStep
                case .choice: choiceStep
                case .create: createStep
                case .join: joinStep
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .animation(.snappy, value: step)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        Group {
            header(emoji: "🐶🐱", title: "Welcome to Brunello")
            lead("One diary for your pet, shared by two parents. Food, poo, pee, walks and photos. Nothing else.")
            Button("Get started") { go(to: .me) }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var meStep: some View {
        Group {
            header(emoji: "💌", title: "Who are you?")
            TextField("Your name", text: $name)
                .textFieldStyle(FieldStyle())
                .textContentType(.givenName)
                .autocorrectionDisabled()
            lead("And what does your pet call you? Updates arrive in your pet's voice, like \"Mama, I made a good poo!\"")
            NicknameChips(nickname: $nickname)
            TextField("Or type your own", text: $nickname)
                .textFieldStyle(FieldStyle())
                .autocorrectionDisabled()
            Text("Letters only, up to \(NameRules.parentNameLimit).")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            Button("Continue") { go(to: .choice) }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!NameRules.isValidParentName(name) || !NameRules.isValidParentName(nickname))
        }
    }

    private var choiceStep: some View {
        Group {
            backButton(to: .me)
            header(emoji: "🏡", title: "Hi \(NameRules.clean(name))! Who are we looking after?")
            choiceButton(emoji: "🐾", title: "Add my pet", subtitle: "I am setting things up") { go(to: .create) }
            choiceButton(emoji: "🔑", title: "I have an invite code", subtitle: "The other parent already added our pet") { go(to: .join) }
        }
    }

    private var createStep: some View {
        Group {
            backButton(to: .choice)
            header(emoji: species.emoji, title: "Add your pet")
            TextField("Pet name", text: $petName)
                .textFieldStyle(FieldStyle())
                .autocorrectionDisabled()
            Picker("Kind of pet", selection: $species) {
                ForEach(Species.allCases) { choice in
                    Text("\(choice.emoji) \(choice.label)").tag(choice)
                }
            }
            .pickerStyle(.segmented)
            errorText
            Button(isWorking ? "Creating…" : "Create the diary") {
                run {
                    try await appState.createPet(name: petName, species: species, parentName: name, parentNickname: nickname)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking || !NameRules.isValidPetName(petName))
        }
    }

    private var joinStep: some View {
        Group {
            backButton(to: .choice)
            header(emoji: "🔑", title: "Enter your invite code")
            lead("The other parent finds it in the app after adding your pet.")
            TextField("ABC123", text: $inviteCode)
                .textFieldStyle(FieldStyle())
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            errorText
            Button(isWorking ? "Joining…" : "Join the family") {
                run {
                    try await appState.joinPet(inviteCode: inviteCode, parentName: name, parentNickname: nickname)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isWorking || !NameRules.isValidInviteCode(inviteCode))
        }
    }

    // MARK: - Pieces

    private func header(emoji: String, title: String) -> some View {
        VStack(spacing: 12) {
            Text(emoji).font(.system(size: 64))
            Text(title)
                .font(.title.bold())
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    private func lead(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
    }

    private func backButton(to previous: Step) -> some View {
        Button {
            go(to: previous)
        } label: {
            Label("Back", systemImage: "chevron.left").font(.subheadline.weight(.bold))
        }
        .foregroundStyle(Theme.inkSoft)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choiceButton(emoji: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji).font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .card(padding: 16)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var errorText: some View {
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.brand)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Actions

    private func go(to next: Step) {
        errorMessage = nil
        step = next
    }

    /// Runs a create or join call and shows a plain-words message when it fails.
    private func run(_ action: @escaping () async throws -> Void) {
        errorMessage = nil
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await action()
            } catch let error as DiaryError {
                errorMessage = error.errorDescription
            } catch {
                Logger.app.error("Onboarding failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = "Something went wrong. Check your connection and try again."
            }
        }
    }
}

/// Quick picks for what the pet calls this parent.
struct NicknameChips: View {
    @Binding var nickname: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NameRules.nicknameIdeas, id: \.self) { idea in
                    Button {
                        nickname = idea
                    } label: {
                        Text(idea)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(nickname == idea ? Theme.brand : Theme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.card, in: Capsule())
                            .overlay(Capsule().stroke(nickname == idea ? Theme.brand : Theme.line, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
        }
    }
}
