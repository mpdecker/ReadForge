import SwiftUI

extension View {
    /// Shared error-alert presentation, driven by a `Binding<String>` that's empty when there's
    /// nothing to show. Replaces a pattern that was copy-pasted across many views
    /// (`ProfileView`, `SignInView`, `SignUpView`, `PasswordResetView`, ...): each used
    /// `.alert("Error", isPresented: .constant(!errorMessage.isEmpty))`, which binds to a
    /// `.constant()` — SwiftUI has no way to write back through that, so swiping the alert away
    /// or tapping outside it (iPad) never actually cleared `errorMessage`, leaving it silently
    /// stuck non-empty. This binds a real, two-way `isPresented`, so any dismissal path clears
    /// the message correctly.
    func errorAlert(_ message: Binding<String>, title: String = "Error") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { !message.wrappedValue.isEmpty },
                set: { isPresented in if !isPresented { message.wrappedValue = "" } }
            )
        ) {
            Button("OK") { message.wrappedValue = "" }
        } message: {
            Text(message.wrappedValue)
        }
    }

    /// Same as above, for view models that model "no error" as `nil` rather than `""`
    /// (`LibraryViewModel`, `PlayerViewModel`) — same `.constant()` dismissal bug applied there
    /// too.
    func errorAlert(_ message: Binding<String?>, title: String = "Error") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in if !isPresented { message.wrappedValue = nil } }
            )
        ) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }

    /// Shared "delete your account" confirmation — was copy-pasted verbatim into `ProfileView`
    /// and `DataStorageView` with a drift bug (DataStorageView's copy didn't dismiss the screen
    /// afterward). One definition now backs both call sites.
    func deleteAccountConfirmation(isPresented: Binding<Bool>, onDelete: @escaping () -> Void) -> some View {
        confirmationDialog(
            "Delete your account? This removes your account and sign-in — your library, documents, and progress are not affected.",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}
