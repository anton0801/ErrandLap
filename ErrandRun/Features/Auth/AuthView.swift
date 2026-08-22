//
//  AuthView.swift
//  ErrandRun
//
//  Sign in or make an account. Nothing else happens on this screen.
//

import SwiftUI

struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    enum Mode: String, CaseIterable, Hashable {
        case signIn = "Sign In"
        case register = "Create Account"
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var showPassword = false

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }

    private var canSubmit: Bool {
        !trimmedEmail.isEmpty && password.count >= (mode == .register ? 10 : 1) && !auth.isWorking
    }

    var body: some View {
        ERScreen(sparkSeed: 33) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    ERChipRow(items: Mode.allCases, title: { $0.rawValue }, selection: $mode)
                        .onChange(of: mode) { _, _ in
                            auth.errorMessage = nil
                            auth.fieldErrors = [:]
                        }

                    if mode == .register {
                        ERField("Your Name", hint: "Only used to greet you inside the app.") {
                            ERTextField(placeholder: "Anton", text: $displayName)
                                .textInputAutocapitalization(.words)
                        }
                    }

                    ERField("Email", hint: fieldHint("email")) {
                        ERTextField(placeholder: "you@example.com", text: $email, keyboard: .emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    ERField("Password", hint: passwordHint) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Group {
                                    if showPassword {
                                        TextField("", text: $password, prompt: Text("At least 10 characters")
                                            .foregroundColor(ER.charcoal.opacity(0.35)))
                                    } else {
                                        SecureField("", text: $password, prompt: Text("At least 10 characters")
                                            .foregroundColor(ER.charcoal.opacity(0.35)))
                                    }
                                }
                                .font(.erBody)
                                .foregroundStyle(ER.charcoal)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(mode == .register ? .newPassword : .password)
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background { BeveledRect(radius: 10, cap: 12).fill(ER.card) }
                                .overlay { BeveledRect(radius: 10, cap: 12).stroke(ER.charcoal, lineWidth: 2) }

                                ERIconButton(systemName: showPassword ? "eye.slash" : "eye") {
                                    showPassword.toggle()
                                }
                            }
                        }
                    }

                    if let message = auth.errorMessage {
                        ERCard(tone: .active) {
                            Text(message)
                                .font(.erBodyBold)
                                .foregroundStyle(ER.charcoal)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Button(mode == .signIn ? "Sign In" : "Create Account") {
                        Task { await submit() }
                    }
                    .buttonStyle(FireButtonStyle())
                    .disabled(!canSubmit)

                    if auth.isWorking {
                        ERLoadingState(text: mode == .signIn ? "Signing in" : "Creating the account")
                    }

                    ERCard(index: 1) {
                        VStack(alignment: .leading, spacing: 8) {
                            ERSectionHeader(text: "What Leaves This Phone")
                            bullet("Your errands, places and windows, so a new phone finds them.")
                            bullet("Nothing is shared with anyone else, ever.")
                            bullet("Every request is signed with a token that lives in the Keychain.")
                            bullet("Delete the account and the server keeps nothing.")
                        }
                    }

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, ERMetric.screenPadding)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            SparkField(seed: 34, count: 8)
                .frame(height: 70)
            ERScreenTitle(text: mode == .signIn ? "Welcome Back" : "Errand Run")
            Text(mode == .signIn
                 ? "Sign in and this phone picks up where the last one left off."
                 : "One account keeps your errands, places and measured times together.")
                .font(.erBody)
                .foregroundStyle(ER.charcoal.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var passwordHint: String? {
        if let field = auth.fieldErrors["password"] ?? auth.fieldErrors["new_password"] {
            return field
        }
        return mode == .register ? "At least 10 characters. A short sentence beats a clever word." : nil
    }

    private func fieldHint(_ key: String) -> String? {
        auth.fieldErrors[key]
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            DiamondShape()
                .fill(.fire)
                .frame(width: 8, height: 8)
                .padding(.top, 7)
            Text(text)
                .font(.erCaption)
                .foregroundStyle(ER.charcoal.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func submit() async {
        let ok: Bool
        if mode == .signIn {
            ok = await auth.signIn(email: trimmedEmail, password: password)
        } else {
            ok = await auth.register(email: trimmedEmail, password: password, displayName: displayName)
        }
        if ok {
            password = ""
        }
    }
}
