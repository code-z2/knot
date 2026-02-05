import SwiftUI
import Transactions

struct ProfileView: View {
  let eoaAddress: String
  let accountService: AccountSetupService
  let ensService: ENSService
  let aaExecutionService: AAExecutionService
  let registrarControllerAddress: String
  var onBack: () -> Void = {}

  @State private var ensName = ""
  @State private var avatarURL = ""
  @State private var bio = ""
  @State private var isNameLocked = false
  @State private var isCheckingName = false
  @State private var lastQuotedName = ""
  @State private var nameInfoText: String?
  @State private var nameInfoTone: NameInfoTone = .info
  @State private var isSaving = false
  @State private var errorMessage: String?
  @State private var successMessage: String?
  @State private var preparedPayloads: Int = 0
  @State private var initialAvatarURL = ""
  @State private var initialBio = ""

  init(
    eoaAddress: String,
    accountService: AccountSetupService,
    ensService: ENSService,
    aaExecutionService: AAExecutionService,
    registrarControllerAddress: String = "0x253553366Da8546fC250F225fe3d25d0C782303b",
    onBack: @escaping () -> Void = {}
  ) {
    self.eoaAddress = eoaAddress
    self.accountService = accountService
    self.ensService = ensService
    self.aaExecutionService = aaExecutionService
    self.registrarControllerAddress = registrarControllerAddress
    self.onBack = onBack
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      AppThemeColor.fixedDarkSurface.ignoresSafeArea()

      BackNavigationButton(action: onBack)
        .offset(x: 20, y: 39)

      VStack(spacing: 0) {
        header
          .padding(.horizontal, 20)
          .padding(.top, 48)

        ScrollView(showsIndicators: false) {
          VStack(spacing: 20) {
            field(
              title: "ENS Name",
              text: $ensName,
              placeholder: "yourname.eth",
              isDisabled: isNameLocked
            )

            if let nameInfoText, !isNameLocked {
              infoText(nameInfoText, tone: nameInfoTone)
            }

            field(
              title: "Avatar URL (optional)",
              text: $avatarURL,
              placeholder: "https://..."
            )

            bioField
          }
          .padding(.horizontal, 20)
          .padding(.top, 36)
          .padding(.bottom, 60)
        }
      }

      if let errorMessage {
        toast(message: errorMessage, isError: true)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.horizontal, 20)
          .padding(.bottom, 24)
      }

      if let successMessage {
        toast(message: successMessage, isError: false)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.horizontal, 20)
          .padding(.bottom, 24)
      }
    }
    .task {
      await loadProfile()
    }
    .onChange(of: ensName) { _, newValue in
      guard !isNameLocked else { return }
      Task { await quoteENSNameIfNeeded(input: newValue) }
    }
  }

  private var header: some View {
    HStack {
      Spacer()
      Text("Profile")
        .font(.custom("Inter-Bold", size: 22))
        .foregroundStyle(AppThemeColor.labelSecondary)
      Spacer()
    }
    .overlay(alignment: .trailing) {
      Button(action: { Task { await saveProfile() } }) {
        Text(isSaving ? "Saving" : "Save")
          .font(.custom("Roboto-Bold", size: 14))
          .foregroundStyle(AppThemeColor.accentBrown)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(AppThemeColor.accentBrown, lineWidth: 1.5)
          )
      }
      .buttonStyle(.plain)
      .disabled(isSaving || isCheckingName)
      .opacity(isSaving ? 0.6 : 1)
    }
  }

  private func field(
    title: String,
    text: Binding<String>,
    placeholder: String,
    isDisabled: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.custom("RobotoMono-Medium", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)

      TextField(placeholder, text: text)
        .font(.custom("Roboto-Regular", size: 15))
        .foregroundStyle(AppThemeColor.labelPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .disabled(isDisabled)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppThemeColor.fillPrimary)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppThemeColor.fillSecondary, lineWidth: 1)
        )
        .opacity(isDisabled ? 0.65 : 1)
    }
  }

  private func infoText(_ value: String, tone: NameInfoTone) -> some View {
    Text(value)
      .font(.custom("Roboto-Regular", size: 12))
      .foregroundStyle(color(for: tone))
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var bioField: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Bio (optional)")
        .font(.custom("RobotoMono-Medium", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)

      TextEditor(text: $bio)
        .font(.custom("Roboto-Regular", size: 15))
        .foregroundStyle(AppThemeColor.labelPrimary)
        .padding(8)
        .frame(minHeight: 132)
        .scrollContentBackground(.hidden)
        .background(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(AppThemeColor.fillPrimary)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(AppThemeColor.fillSecondary, lineWidth: 1)
        )
    }
  }

  @MainActor
  private func loadProfile() async {
    do {
      let resolvedName = try await ensService.reverseAddress(address: eoaAddress)
      if !resolvedName.isEmpty {
        ensName = resolvedName
        isNameLocked = true
        nameInfoText = nil
        lastQuotedName = resolvedName
      }
    } catch {
      // No reverse name yet is a normal state.
      nameInfoText = "Enter a name to check availability and registration cost."
      nameInfoTone = .info
      isNameLocked = false
    }
    initialAvatarURL = avatarURL
    initialBio = bio
  }

  @MainActor
  private func quoteENSNameIfNeeded(input: String) async {
    let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else {
      nameInfoText = "Enter a name to check availability and registration cost."
      nameInfoTone = .info
      lastQuotedName = ""
      return
    }
    guard normalized != lastQuotedName else { return }
    try? await Task.sleep(for: .milliseconds(320))
    let latest = ensName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard latest == normalized else { return }

    isCheckingName = true
    defer { isCheckingName = false }

    do {
      let quote = try await ensService.quoteName(
        registrarControllerAddress: registrarControllerAddress,
        name: normalized
      )
      lastQuotedName = quote.normalizedName
      ensName = quote.normalizedName

      if quote.available {
        let eth = TokenFormatters.weiToEthString(quote.rentPriceWei)
        nameInfoText = "This name is available for \(eth) ETH."
        nameInfoTone = .success
      } else {
        nameInfoText = "This name is not available."
        nameInfoTone = .error
      }
    } catch {
      nameInfoText = error.localizedDescription
      nameInfoTone = .error
    }
  }

  @MainActor
  private func saveProfile() async {
    guard !isSaving else { return }
    isSaving = true
    preparedPayloads = 0
    defer { isSaving = false }

    do {
      let normalizedName = ensName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if normalizedName.isEmpty && !isNameLocked {
        throw ENSServiceError.actionFailed(NSError(domain: "ENS", code: 1, userInfo: [NSLocalizedDescriptionKey: "ENS name is required."]))
      }

      var allCalls: [Call] = []

      if !isNameLocked {
        if normalizedName != lastQuotedName || nameInfoTone != .success {
          throw ENSServiceError.actionFailed(
            NSError(
              domain: "ENS",
              code: 2,
              userInfo: [NSLocalizedDescriptionKey: "Please use an available ENS name before saving."]
            )
          )
        }
        let registerPayloads = try await ensService.registerNamePayloads(
          registrarControllerAddress: registrarControllerAddress,
          name: normalizedName,
          ownerAddress: eoaAddress
        )
        allCalls.append(contentsOf: registerPayloads)
        preparedPayloads += registerPayloads.count
        isNameLocked = true
      }

      let avatar = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
      if !avatar.isEmpty, avatar != initialAvatarURL {
        let avatarPayload = try await ensService.updateRecordPayload(
          name: normalizedName,
          key: "avatar",
          value: avatar
        )
        allCalls.append(avatarPayload)
        preparedPayloads += 1
      }

      let description = bio.trimmingCharacters(in: .whitespacesAndNewlines)
      if !description.isEmpty, description != initialBio {
        let bioPayload = try await ensService.updateRecordPayload(
          name: normalizedName,
          key: "description",
          value: description
        )
        allCalls.append(bioPayload)
        preparedPayloads += 1
      }

      guard !allCalls.isEmpty else {
        showSuccess("No ENS changes to save")
        return
      }

      let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
      _ = try await aaExecutionService.executeCalls(
        accountService: accountService,
        account: sessionAccount,
        chainId: 1,
        calls: allCalls
      )

      initialAvatarURL = avatarURL
      initialBio = bio
      showSuccess("Saved \(preparedPayloads) ENS change(s)")
    } catch {
      showError(error)
    }
  }

  private func color(for tone: NameInfoTone) -> Color {
    switch tone {
    case .info:
      return AppThemeColor.labelSecondary
    case .success:
      return AppThemeColor.accentGreen
    case .warning:
      return AppThemeColor.accentBrown
    case .error:
      return AppThemeColor.accentRed
    }
  }

  @MainActor
  private func showError(_ error: Error) {
    successMessage = nil
    errorMessage = error.localizedDescription
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2.8))
      if errorMessage == error.localizedDescription { errorMessage = nil }
    }
  }

  @MainActor
  private func showSuccess(_ message: String) {
    errorMessage = nil
    successMessage = message
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2.0))
      if successMessage == message { successMessage = nil }
    }
  }

  private func toast(message: String, isError: Bool) -> some View {
    Text(message)
      .font(.custom("RobotoMono-Medium", size: 12))
      .foregroundStyle(isError ? AppThemeColor.accentRed : AppThemeColor.accentGreen)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(AppThemeColor.fillPrimary)
      )
  }
}

private enum NameInfoTone {
  case info
  case success
  case warning
  case error
}

#Preview {
  ProfileView(
    eoaAddress: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193",
    accountService: AccountSetupService(),
    ensService: ENSService(), aaExecutionService: AAExecutionService()
  )
}
