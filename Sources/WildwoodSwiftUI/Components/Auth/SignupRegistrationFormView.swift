#if os(iOS)
// The account form both signup screens collect their details with.
//
// It was the `accountForm` inside ``SignupWithSubscriptionComponent`` and is now its own view,
// lifted out rather than copied, for the same reason ``SignupAccountCreator`` was: the old wizard
// and the new ``RegistrationSubscriptionSignupView`` must not be able to drift on what a
// registration asks for or on when it is allowed to be submitted. One set of fields, one
// "passwords do not match" rule, one submit gate.
//
// The React stacks reach the same place differently: there the form IS a component
// (`TokenRegistrationComponent` with `deferSubmission`), because the web's token registration
// screen already collected exactly these fields. This package's ``TokenRegistrationComponent``
// registers the account itself and has no deferred mode, so the shared piece is this view instead
// — the fields and the validation, with the submission left to whoever mounted it.
//
// The one behaviour the extraction tightened: when a token is the ONLY way in, the submit button
// now waits for a token. The wizard used to let the form through with an empty one and have the
// server refuse it.
//
// Every input and the submit carry an accessibility identifier from
// ``RegistrationSubscriptionTestID`` rather than leaving a suite to find them by their placeholder
// copy. The copy is English, it is a caller-supplied parameter in the submit's case, and it is meant
// to be localised — a locator keyed on it stops finding the field the day it is translated.
//
// It collects and hands back; it never calls a server. Everything it knows about the app's
// registration settings arrives as two booleans, so the caller — the wizard from its
// `AuthenticationConfiguration`, the signup view from its ``SignupRegistrationMode`` — owns that
// decision where it already lives.

import SwiftUI
import WildwoodCore

public struct SignupRegistrationFormView: View {
    /// A previous attempt's values, or the invitation's email. Applied once, on first appearance.
    private let initialFormData: RegistrationFormData?
    /// Whether the registration-token field is on screen at all.
    private let showTokenField: Bool
    /// Whether a token is the only way in, which makes the field required and drops "(optional)"
    /// from its placeholder.
    private let tokenRequired: Bool
    /// What the submit button says. "Continue" while a plan step is still ahead, otherwise the
    /// account is the next thing that happens.
    private let submitTitle: String
    /// Disables submission while the caller is working.
    private let isBusy: Bool
    /// Said when the two password fields disagree.
    private let mismatchMessage: String
    /// Offers a way out. Omitted, no cancel is rendered.
    private let cancelTitle: String?
    private let onSubmit: (RegistrationFormData) -> Void
    private let onCancel: (() -> Void)?

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var registrationToken: String = ""
    @State private var validationMessage: String = ""
    /// The initial values are applied ONCE: a re-appearance (a step back and forward again) must
    /// not throw away what the visitor has typed since.
    @State private var seeded: Bool = false

    public init(
        initialFormData: RegistrationFormData? = nil,
        showTokenField: Bool = true,
        tokenRequired: Bool = false,
        submitTitle: String = "Continue",
        isBusy: Bool = false,
        mismatchMessage: String = "Passwords do not match",
        cancelTitle: String? = nil,
        onSubmit: @escaping (RegistrationFormData) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.initialFormData = initialFormData
        self.showTokenField = showTokenField
        self.tokenRequired = tokenRequired
        self.submitTitle = submitTitle
        self.isBusy = isBusy
        self.mismatchMessage = mismatchMessage
        self.cancelTitle = cancelTitle
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 12) {
            if !validationMessage.isEmpty {
                ErrorBannerView(message: validationMessage) { validationMessage = "" }
            }

            TextField("First name", text: $firstName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.field(.firstName))
            TextField("Last name", text: $lastName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.familyName)
                .accessibilityIdentifier(RegistrationSubscriptionTestID.field(.lastName))
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(RegistrationSubscriptionTestID.field(.email))
            TextField("Username (optional)", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(RegistrationSubscriptionTestID.field(.username))
            // The identifier goes THROUGH the control rather than onto it: the reveal button is a
            // second accessibility element inside, and an identifier applied out here would reach
            // it too.
            WildwoodSecureField(
                "Password",
                text: $password,
                contentType: .newPassword,
                identifier: RegistrationSubscriptionTestID.field(.password)
            )
            WildwoodSecureField(
                "Confirm password",
                text: $confirmPassword,
                contentType: .newPassword,
                identifier: RegistrationSubscriptionTestID.field(.confirmPassword)
            )

            if showTokenField {
                TextField(tokenPlaceholder, text: $registrationToken)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier(RegistrationSubscriptionTestID.field(.registrationToken))
            }

            Button {
                submit()
            } label: {
                Text(submitTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || !canSubmit)
            .accessibilityIdentifier(RegistrationSubscriptionTestID.submitRegister)

            if let onCancel, let cancelTitle, !cancelTitle.isEmpty {
                Button(cancelTitle) { onCancel() }
                    .font(.footnote)
            }
        }
        .onAppear { seed() }
    }

    // MARK: - Pieces

    private var tokenPlaceholder: String {
        tokenRequired ? "Registration token" : "Registration token (optional)"
    }

    /// The wizard's own gate, unchanged apart from the required-token case: a first name, an email
    /// and a password, because those three are what the server insists on.
    private var canSubmit: Bool {
        if firstName.isEmpty || email.isEmpty || password.isEmpty { return false }
        if tokenRequired && registrationToken.isEmpty { return false }
        return true
    }

    private func seed() {
        if seeded { return }
        seeded = true
        guard let initialFormData else { return }
        firstName = initialFormData.firstName
        lastName = initialFormData.lastName
        email = initialFormData.email
        username = initialFormData.username
        password = initialFormData.password
        registrationToken = initialFormData.registrationToken ?? ""
    }

    private func submit() {
        guard password == confirmPassword else {
            validationMessage = mismatchMessage
            return
        }
        validationMessage = ""
        let token: String = registrationToken.trimmingCharacters(in: .whitespacesAndNewlines)
        onSubmit(
            RegistrationFormData(
                firstName: firstName,
                lastName: lastName,
                username: username,
                email: email,
                password: password,
                registrationToken: token.isEmpty ? nil : token,
                // What the visitor actually typed decides, not what the screen offered: an
                // optional field left blank is an ordinary registration.
                useToken: !token.isEmpty
            )
        )
    }
}
#endif
