import LumenCore
import SwiftUI

/// Shown in place of a locked category's content.
struct LockedCategoryView: View {
    @Environment(AppModel.self) private var model
    let categoryID: String
    @State private var pin = ""
    @State private var failed = false
    @State private var failedAttempts = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("This category is locked").font(.title2.weight(.semibold))
            Text("Enter your PIN to view it. It locks again when Lumen quits, or with ⌘L.")
                .foregroundStyle(.secondary)
            HStack {
                SecureField("PIN", text: $pin)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .focused($focused)
                    .onSubmit(attempt)
                Button("Unlock", action: attempt).buttonStyle(.borderedProminent).disabled(pin.isEmpty)
            }
            .modifier(Shake(trigger: failedAttempts))
            if failed { Text("Wrong PIN").font(.callout).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
        .onChange(of: categoryID) { pin = ""; failed = false }
    }

    private func attempt() {
        if model.unlock(categoryID, pin: pin) {
            pin = ""
            failed = false
        } else {
            failed = true
            failedAttempts += 1
            pin = ""
        }
    }
}

/// Creates or verifies the parental PIN, then runs the request's continuation.
struct PINSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: PINRequest

    @State private var pin = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: "lock.shield").font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField("PIN", text: $pin).textFieldStyle(.roundedBorder)
            if case .create = request.mode {
                SecureField("Confirm PIN", text: $confirmation).textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Continue", action: submit).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(pin.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    private var title: String {
        if case .create = request.mode { return "Create a PIN" }
        return "Enter PIN"
    }

    private var message: String {
        switch request.mode {
        case .create: "Locked categories need this 4–8 digit PIN to open. Keep it somewhere safe."
        case .verify(let reason): reason
        }
    }

    private func submit() {
        switch request.mode {
        case .create:
            guard LibraryState.isValidPIN(pin) else { error = "Use 4 to 8 digits."; return }
            guard pin == confirmation else { error = "The PINs don't match."; return }
            model.setPIN(pin)
        case .verify:
            guard model.verifyPIN(pin) else { error = "Wrong PIN."; pin = ""; return }
        }
        let onSuccess = request.onSuccess
        dismiss()
        // Run after dismissal so a follow-up request (e.g. "change PIN") can present its own sheet.
        DispatchQueue.main.async(execute: onSuccess)
    }
}

/// Horizontal shake for a rejected PIN.
private struct Shake: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, offset in
            view.offset(x: offset)
        } keyframes: { _ in
            KeyframeTrack {
                for value in [10.0, -8, 6, -4, 0] { LinearKeyframe(value, duration: 0.06) }
            }
        }
    }
}
