import SwiftUI

/// Shown while the second parent has not joined yet: the invite code and a way to send it.
struct InviteCard: View {
    let pet: Pet

    @State private var isCopied = false

    private var shareText: String {
        "Join \(pet.name)'s diary on Brunello with this invite code: \(pet.inviteCode)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Invite the other parent").font(.headline).foregroundStyle(Theme.ink)
            Text("Only someone with this code can join \(pet.name)'s diary. It works once.")
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
            Text(pet.inviteCode)
                .font(.system(.title, design: .rounded, weight: .bold))
                .kerning(8)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .textSelection(.enabled)
                .accessibilityLabel("Invite code \(pet.inviteCode.map(String.init).joined(separator: " "))")
            HStack(spacing: 8) {
                ShareLink(item: shareText) {
                    Label("Send the code", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    UIPasteboard.general.string = pet.inviteCode
                    isCopied = true
                } label: {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14)
        .background(EntryKind.photo.tint, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
