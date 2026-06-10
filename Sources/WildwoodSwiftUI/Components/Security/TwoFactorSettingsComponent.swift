#if os(iOS)
// Two-factor enrollment and management UI — parity with
// TwoFactorSettingsComponent in the React Native package. Email and
// authenticator enrollment, recovery codes, trusted devices, primary method.

import SwiftUI
import CoreImage.CIFilterBuiltins
import WildwoodCore

public struct TwoFactorSettingsComponent: View {
    @Environment(\.wildwoodClient) private var client

    private let onStatusChanged: ((TwoFactorUserStatus) -> Void)?

    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var status: TwoFactorUserStatus?
    @State private var credentials: [TwoFactorCredential] = []
    @State private var trustedDevices: [TrustedDevice] = []

    // Email enrollment
    @State private var showEmailEnrollment = false
    @State private var enrollmentEmail = ""
    @State private var emailEnrollment: EmailEnrollmentResult?
    @State private var emailVerificationCode = ""

    // Authenticator enrollment
    @State private var showAuthenticatorEnrollment = false
    @State private var authenticatorEnrollment: AuthenticatorEnrollmentResult?
    @State private var authenticatorVerificationCode = ""

    // Recovery codes
    @State private var regeneratedCodes: [String] = []

    public init(onStatusChanged: ((TwoFactorUserStatus) -> Void)? = nil) {
        self.onStatusChanged = onStatusChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Two-Factor Authentication")
                .font(.title2.weight(.bold))

            if !errorMessage.isEmpty {
                ErrorBannerView(message: errorMessage) { errorMessage = "" }
            }

            if isLoading {
                LoadingSpinnerView(label: "Loading security settings…")
            } else {
                statusSection
                credentialsSection
                enrollmentButtons
                recoverySection
                trustedDevicesSection
            }
        }
        .task { await load() }
        .sheet(isPresented: $showEmailEnrollment) { emailEnrollmentSheet }
        .sheet(isPresented: $showAuthenticatorEnrollment) { authenticatorEnrollmentSheet }
    }

    // MARK: - Sections

    @ViewBuilder private var statusSection: some View {
        if let status {
            HStack {
                Image(systemName: status.isEnabled ? "lock.shield.fill" : "lock.open")
                    .foregroundStyle(status.isEnabled ? .green : .orange)
                VStack(alignment: .leading) {
                    Text(status.isEnabled ? "Two-factor is enabled" : "Two-factor is not enabled")
                        .font(.headline)
                    Text("\(status.methodCount) method(s) · \(status.recoveryCodesRemaining) recovery codes · \(status.trustedDevicesCount) trusted devices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder private var credentialsSection: some View {
        if !credentials.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Methods").font(.headline)
                ForEach(credentials) { credential in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(credential.displayName).font(.subheadline.weight(.medium))
                                if credential.isPrimary {
                                    Text("Primary")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15), in: Capsule())
                                }
                            }
                            if let maskedEmail = credential.maskedEmail {
                                Text(maskedEmail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Menu {
                            if !credential.isPrimary {
                                Button("Make primary") {
                                    Task {
                                        _ = await client?.twoFactor.setPrimaryCredential(credentialId: credential.id)
                                        await load()
                                    }
                                }
                            }
                            Button("Remove", role: .destructive) {
                                Task {
                                    _ = await client?.twoFactor.removeCredential(credentialId: credential.id)
                                    await load()
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder private var enrollmentButtons: some View {
        VStack(spacing: 8) {
            Button {
                enrollmentEmail = ""
                emailEnrollment = nil
                emailVerificationCode = ""
                showEmailEnrollment = true
            } label: {
                Label("Add email verification", systemImage: "envelope")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                authenticatorEnrollment = nil
                authenticatorVerificationCode = ""
                showAuthenticatorEnrollment = true
            } label: {
                Label("Add authenticator app", systemImage: "qrcode")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recovery Codes").font(.headline)
            if !regeneratedCodes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Store these codes somewhere safe — they are shown only once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(regeneratedCodes, id: \.self) { code in
                        Text(code).font(.body.monospaced())
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
            Button("Regenerate recovery codes") {
                Task {
                    guard let client else { return }
                    do {
                        let result = try await client.twoFactor.regenerateRecoveryCodes()
                        if result.success {
                            regeneratedCodes = result.codes
                            await load()
                        } else {
                            errorMessage = result.message ?? "Failed to regenerate recovery codes."
                        }
                    } catch {
                        errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
                    }
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder private var trustedDevicesSection: some View {
        if !trustedDevices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Trusted Devices").font(.headline)
                    Spacer()
                    Button("Revoke all", role: .destructive) {
                        Task {
                            _ = await client?.twoFactor.revokeAllTrustedDevices()
                            await load()
                        }
                    }
                    .font(.caption)
                }
                ForEach(trustedDevices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.deviceName).font(.subheadline)
                            if let lastUsedAt = device.lastUsedAt {
                                Text("Last used \(lastUsedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Revoke", role: .destructive) {
                            Task {
                                _ = await client?.twoFactor.revokeTrustedDevice(deviceId: device.id)
                                await load()
                            }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Email enrollment sheet

    @ViewBuilder private var emailEnrollmentSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let emailEnrollment {
                    Text("Enter the code sent to \(emailEnrollment.maskedEmail)")
                        .font(.callout)
                    TextField("Verification code", text: $emailVerificationCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    Button("Verify") {
                        Task {
                            guard let client else { return }
                            let ok = await client.twoFactor.verifyEmailEnrollment(
                                credentialId: emailEnrollment.credentialId,
                                code: emailVerificationCode
                            )
                            if ok {
                                showEmailEnrollment = false
                                await load()
                            } else {
                                errorMessage = "Email verification failed."
                                showEmailEnrollment = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(emailVerificationCode.isEmpty)
                } else {
                    TextField("Email (defaults to account email)", text: $enrollmentEmail)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Send Code") {
                        Task {
                            guard let client else { return }
                            do {
                                emailEnrollment = try await client.twoFactor.enrollEmail(
                                    email: enrollmentEmail.isEmpty ? nil : enrollmentEmail
                                )
                            } catch {
                                errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
                                showEmailEnrollment = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Email Verification")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Authenticator enrollment sheet

    @ViewBuilder private var authenticatorEnrollmentSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let enrollment = authenticatorEnrollment {
                    if let qrImage = QRCodeRenderer.image(for: enrollment) {
                        Image(decorative: qrImage, scale: 1)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .accessibilityLabel("Authenticator setup QR code")
                    }
                    Text("Scan with your authenticator app, or enter the key manually:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(enrollment.manualEntryKey)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    TextField("6-digit code", text: $authenticatorVerificationCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    Button("Verify") {
                        Task {
                            guard let client else { return }
                            let ok = await client.twoFactor.completeAuthenticatorEnrollment(
                                credentialId: enrollment.credentialId,
                                code: authenticatorVerificationCode
                            )
                            if ok {
                                showAuthenticatorEnrollment = false
                                await load()
                            } else {
                                errorMessage = "Authenticator verification failed."
                                showAuthenticatorEnrollment = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authenticatorVerificationCode.isEmpty)
                } else {
                    ProgressView("Preparing enrollment…")
                        .task {
                            guard let client else { return }
                            do {
                                authenticatorEnrollment = try await client.twoFactor.beginAuthenticatorEnrollment()
                            } catch {
                                errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
                                showAuthenticatorEnrollment = false
                            }
                        }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Authenticator App")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    // MARK: - Data

    private func load() async {
        guard let client = requireClient(client, component: "TwoFactorSettingsComponent") else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let loadedStatus = try await client.twoFactor.getStatus()
            status = loadedStatus
            onStatusChanged?(loadedStatus)
        } catch {
            errorMessage = (error as? WildwoodError)?.message ?? error.localizedDescription
        }
        credentials = await client.twoFactor.getCredentials()
        trustedDevices = await client.twoFactor.getTrustedDevices()
    }
}

/// Renders the enrollment QR: prefers the backend's data-URL PNG; falls back
/// to generating one locally from the otpauth URI with CoreImage.
enum QRCodeRenderer {
    static func image(for enrollment: AuthenticatorEnrollmentResult) -> CGImage? {
        if enrollment.qrCodeDataUrl.hasPrefix("data:"),
           let commaIndex = enrollment.qrCodeDataUrl.firstIndex(of: ","),
           let data = Data(base64Encoded: String(enrollment.qrCodeDataUrl[enrollment.qrCodeDataUrl.index(after: commaIndex)...])),
           let provider = CGDataProvider(data: data as CFData),
           let image = CGImage(
               pngDataProviderSource: provider,
               decode: nil,
               shouldInterpolate: false,
               intent: .defaultIntent
           ) {
            return image
        }

        guard let uri = enrollment.otpauthUri else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(uri.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
#endif
