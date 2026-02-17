import ENS
import PhotosUI
import SwiftUI
import Transactions
import UIKit
import UniformTypeIdentifiers

struct ProfileView: View {
  private enum FocusedField: Hashable {
    case ensName
    case bio
  }

  let eoaAddress: String
  let accountService: AccountSetupService
  let ensService: ENSService
  let aaExecutionService: AAExecutionService
  let imageStorageService: ProfileImageStorageService
  let commitRevealStore: ENSCommitRevealStore
  var onBack: () -> Void = {}

  @State private var ensName = ""
  @State private var avatarURL = ""
  @State private var bio = ""
  @State private var isEditingProfile = false
  @State private var isNameLocked = false
  @State private var isCheckingName = false
  @State private var lastQuotedName = ""
  @State private var nameInfoText: String?
  @State private var nameInfoTone: NameInfoTone = .info
  @State private var isSaving = false
  @State private var isUploadingAvatar = false
  @State private var errorMessage: String?
  @State private var successMessage: String?
  @State private var preparedPayloads = 0
  @State private var initialENSName = ""
  @State private var initialAvatarURL = ""
  @State private var initialBio = ""
  @State private var localAvatarImage: UIImage?
  @State private var pendingAvatarUpload: PendingAvatarUpload?
  @State private var showPhotoSourceDialog = false
  @State private var showPhotoPicker = false
  @State private var showFileImporter = false
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var quoteTask: Task<Void, Never>?
  @State private var avatarUploadTask: Task<Void, Never>?
  @FocusState private var focusedField: FocusedField?
  private let quoteWorker: ENSQuoteWorker

  init(
    eoaAddress: String,
    accountService: AccountSetupService,
    ensService: ENSService,
    aaExecutionService: AAExecutionService,
    imageStorageService: ProfileImageStorageService = ProfileImageStorageService(),
    commitRevealStore: ENSCommitRevealStore = ENSCommitRevealStore(),
    onBack: @escaping () -> Void = {}
  ) {
    self.eoaAddress = eoaAddress
    self.accountService = accountService
    self.ensService = ensService
    self.aaExecutionService = aaExecutionService
    self.imageStorageService = imageStorageService
    self.commitRevealStore = commitRevealStore
    self.quoteWorker = ENSQuoteWorker(configuration: ensService.configuration)
    self.onBack = onBack
  }

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      ScrollView {
        VStack(spacing: 0) {
          avatarSection
            .padding(.top, 46)
            .padding(.bottom, 44)

          if let nameInfoText, !isNameLocked, isEditingProfile {
            infoText(nameInfoText, tone: nameInfoTone)
              .padding(.horizontal, 20)
              .padding(.bottom, 12)
          }

          formSection
        }
      }
      .scrollIndicators(.hidden)
      .scrollDismissesKeyboard(.interactively)
      .simultaneousGesture(
        TapGesture().onEnded {
          focusedField = nil
        }
      )
      .padding(.top, AppHeaderMetrics.contentTopPadding)

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
    .safeAreaInset(edge: .top, spacing: 0) { profileHeader }
    .task {
      await loadProfile()
      await resumePendingCommitRevealIfNeeded()
    }
    .onChange(of: ensName) { _, newValue in
      guard !isNameLocked, isEditingProfile else { return }
      scheduleQuoteLookup(for: newValue)
    }
    .onChange(of: selectedPhotoItem) { _, newItem in
      guard let newItem else { return }
      Task { await importPhotoItem(newItem) }
    }
    .confirmationDialog(
      String(localized: "profile_change_photo_title"),
      isPresented: $showPhotoSourceDialog,
      titleVisibility: .visible
    ) {
      Button(String(localized: "profile_photo_library")) { showPhotoPicker = true }
      Button(String(localized: "profile_files")) { showFileImporter = true }
      if localAvatarImage != nil || !avatarURL.isEmpty {
        Button(String(localized: "profile_remove_photo"), role: .destructive) {
          clearAvatarSelection()
        }
      }
      Button(String(localized: "profile_cancel"), role: .cancel) {}
    }
    .photosPicker(
      isPresented: $showPhotoPicker,
      selection: $selectedPhotoItem,
      matching: .images,
      preferredItemEncoding: .automatic
    )
    .fileImporter(
      isPresented: $showFileImporter,
      allowedContentTypes: [.image],
      allowsMultipleSelection: false
    ) { result in
      Task { await importFile(result) }
    }
    .onDisappear {
      quoteTask?.cancel()
      quoteTask = nil
      avatarUploadTask?.cancel()
      avatarUploadTask = nil
    }
  }

  private var profileHeader: some View {
    ZStack {
      Text("profile_title")
        .font(.custom("Roboto-Bold", size: 22))
        .foregroundStyle(AppThemeColor.labelSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)

      HStack(spacing: 0) {
        if isEditingProfile {
          cancelButton
        } else {
          BackNavigationButton(tint: AppThemeColor.labelSecondary, action: onBack)
        }
        Spacer(minLength: 0)
        profileActionButton
      }
    }
    .frame(height: AppHeaderMetrics.height)
    .padding(.horizontal, 16)
  }

  private var cancelButton: some View {
    Button(action: {
      cancelEditing()
    }) {
      Text("profile_cancel")
        .font(.custom("Roboto-Medium", size: 15))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)

    }
    .foregroundStyle(AppThemeColor.labelPrimary)
    .modifier(ProfileGlassCapsuleButtonModifier())
  }

  private var avatarSection: some View {
    VStack(spacing: 0) {
      VStack(spacing: 14) {
        avatarPreview
          .frame(width: 104, height: 104)
          .clipShape(Circle())
          .overlay(
            Circle().stroke(AppThemeColor.separatorOpaque, lineWidth: 1.5)
          )

        Button {
          showPhotoSourceDialog = true
        } label: {
          Text("Edit Photo")
            .font(.custom("Roboto-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(!canEditProfileFields)
        .opacity(canEditProfileFields ? 1 : 0.55)
        .background(AppThemeColor.fillSecondary)
        .clipShape(Capsule())
      }
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  private var avatarPreview: some View {
    if let localAvatarImage {
      Image(uiImage: localAvatarImage)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else if let remoteAvatarURL, !avatarURL.isEmpty {
      AsyncImage(url: remoteAvatarURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        case .empty, .failure:
          avatarPlaceholder
        @unknown default:
          avatarPlaceholder
        }
      }
    } else {
      avatarPlaceholder
    }
  }

  private var avatarPlaceholder: some View {
    Circle()
      .fill(AppThemeColor.backgroundPrimary)
      .overlay {
        Image(systemName: "person")
          .font(.system(size: 24, weight: .medium))
          .frame(width: 24, height: 24)
          .foregroundStyle(AppThemeColor.separatorOpaque)
      }
  }

  private var formSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 10) {
            TextField(
              "",
              text: $ensName,
              prompt: Text("profile_enter_name_placeholder")
                .font(.custom("Roboto-Medium", size: 14))
                .foregroundStyle(AppThemeColor.labelSecondary)
            )
            .font(.custom("Roboto-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .focused($focusedField, equals: .ensName)
            .disabled(nameFieldIsLocked)
            .opacity(nameFieldIsLocked ? 0.72 : 1)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
              Text(".eth")
                .font(.custom("Roboto-Medium", size: 14))
                .foregroundStyle(AppThemeColor.labelPrimary)

              if isNameLocked {
                Image(systemName: "lock")
                  .font(.system(size: 14, weight: .medium))
                  .frame(width: 14, height: 14)
                  .foregroundStyle(AppThemeColor.accentBrown)
              }
            }
          }
        }
        .padding(16)

        Rectangle()
          .fill(AppThemeColor.separatorOpaque.opacity(0.7))
          .frame(height: 1)
          .padding(.horizontal, 12)

        VStack(alignment: .leading, spacing: 8) {
          ZStack(alignment: .topLeading) {
            TextEditor(text: $bio)
              .font(.custom("Roboto-Medium", size: 14))
              .foregroundStyle(AppThemeColor.labelPrimary)
              .focused($focusedField, equals: .bio)
              .scrollContentBackground(.hidden)
              .disabled(!canEditProfileFields)
              .opacity(canEditProfileFields ? 1 : 0.72)

            if bio.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              Text("profile_bio_optional")
                .font(.custom("Roboto-Medium", size: 14))
                .foregroundStyle(AppThemeColor.labelSecondary)
                .padding(.top, 8)
                .padding(.leading, 4)
                .allowsHitTesting(false)
                .opacity(canEditProfileFields ? 1 : 0.72)
            }
          }
        }
        .padding(16)
      }
      .background(AppThemeColor.backgroundSecondary)
      .clipShape(.rect(cornerRadius: 16))

      Text(
        "Your ENS name is visible on the blockchain. Including your text records, i.e photo and bio."
      )
      .font(.custom("Roboto-Regular", size: 12))
      .foregroundStyle(AppThemeColor.labelSecondary)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 12)
    }
    .padding(.horizontal, 20)
    .padding(.top, 24)
  }

  private var canEditProfileFields: Bool {
    isEditingProfile && !isSaving
  }

  private var nameFieldIsLocked: Bool {
    !isEditingProfile || isNameLocked
  }

  private var profileActionButton: some View {
    Group {
      if isEditingProfile {
        saveButton
      } else {
        editButton
      }
    }
  }

  private var editButton: some View {
    Button(action: {
      enterEditMode()
    }) {
      Text("Edit")
        .font(.custom("Roboto-Medium", size: 15))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    .foregroundStyle(AppThemeColor.labelPrimary)
    .disabled(isSaving)
    .opacity(isSaving ? 0.45 : 1)
    .modifier(ProfileGlassCapsuleButtonModifier())
  }

  private var saveButton: some View {
    Button(action: {
      Task { await saveProfile() }
    }) {
      Text(isSaving ? "profile_saving" : "profile_save")
        .font(.custom("Roboto-Medium", size: 15))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
    .disabled(!canSave)
    .opacity(canSave ? 1 : 0.45)
    .modifier(ProfileProminentActionButtonModifier())
  }

  private var canSave: Bool {
    guard isEditingProfile, !isSaving, !isCheckingName else { return false }
    return hasSavableChanges
  }

  private var hasSavableChanges: Bool {
    if isNameLocked {
      return hasProfileRecordChanges
    }

    // While name is unlocked, we only allow save once the current name quote
    // is validated as available and matches the latest normalized input.
    return hasReadyNameRegistration
  }

  private var hasReadyNameRegistration: Bool {
    let normalizedName = normalizeENSLabel(ensName)
    return !normalizedName.isEmpty
      && normalizedName == lastQuotedName
      && nameInfoTone == .success
  }

  private var hasProfileRecordChanges: Bool {
    let avatar = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
    let description = bio.trimmingCharacters(in: .whitespacesAndNewlines)
    return pendingAvatarUpload != nil || avatar != initialAvatarURL || description != initialBio
  }

  private var remoteAvatarURL: URL? {
    URL(string: avatarURL.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private func infoText(_ value: String, tone: NameInfoTone) -> some View {
    Text(value)
      .font(.custom("Roboto-Regular", size: 12))
      .foregroundStyle(color(for: tone))
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
  }

  @MainActor
  private func loadProfile() async {
    do {
      let resolvedName = try await ensService.reverseAddress(address: eoaAddress)
      let normalizedName = normalizeENSLabel(resolvedName)
      if !normalizedName.isEmpty {
        ensName = normalizedName
        isNameLocked = true
        nameInfoText = nil
        lastQuotedName = normalizedName

        let fullName = "\(normalizedName).eth"

        if let avatarRecord = try? await ensService.textRecord(
          name: fullName,
          key: "avatar"
        ) {
          avatarURL = avatarRecord.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let descriptionRecord = try? await ensService.textRecord(
          name: fullName,
          key: "description"
        ) {
          bio = descriptionRecord
        }
      }
    } catch {
      isNameLocked = false
      nameInfoText = nil
    }

    isEditingProfile = false
    initialENSName = ensName
    initialAvatarURL = avatarURL
    initialBio = bio
  }

  @MainActor
  private func scheduleQuoteLookup(for input: String) {
    quoteTask?.cancel()

    let normalized = normalizeENSLabel(input)
    guard !normalized.isEmpty else {
      isCheckingName = false
      nameInfoText = nil
      nameInfoTone = .info
      lastQuotedName = ""
      return
    }
    guard normalized != lastQuotedName else { return }

    let quoteWorker = quoteWorker
    quoteTask = Task(priority: .utility) { [normalized] in
      do {
        try await Task.sleep(for: .milliseconds(420))
        try Task.checkCancellation()

        let shouldContinue =
          !self.isNameLocked
          && self.isEditingProfile
          && self.normalizeENSLabel(self.ensName) == normalized
        guard shouldContinue else { return }

        self.isCheckingName = true
        defer {
          if self.normalizeENSLabel(self.ensName) == normalized {
            self.isCheckingName = false
          }
        }

        let quote = try await quoteWorker.quote(name: normalized)
        try Task.checkCancellation()

        guard !self.isNameLocked else { return }
        guard self.normalizeENSLabel(self.ensName) == normalized else { return }

        self.lastQuotedName = quote.normalizedName
        self.ensName = quote.normalizedName

        if quote.available {
          let eth = TokenFormatters.weiToEthString(quote.rentPriceWei)
          self.nameInfoText = String.localizedStringWithFormat(
            NSLocalizedString("profile_name_available_for_price", comment: ""),
            quote.normalizedName,
            eth
          )
          self.nameInfoTone = .success
        } else {
          self.nameInfoText = String(localized: "profile_name_unavailable")
          self.nameInfoTone = .error
        }
      } catch is CancellationError {
        return
      } catch {
        guard self.normalizeENSLabel(self.ensName) == normalized else { return }
        self.nameInfoText = error.localizedDescription
        self.nameInfoTone = .error
        self.isCheckingName = false
      }
    }
  }

  @MainActor
  private func saveProfile() async {
    guard !isSaving else { return }
    isSaving = true
    preparedPayloads = 0
    defer { isSaving = false }

    do {
      try await ensureAvatarUploadCompletedIfNeeded()

      let normalizedName = normalizeENSLabel(ensName)
      if normalizedName.isEmpty {
        throw ENSServiceError.actionFailed(
          NSError(
            domain: "ENS",
            code: 3,
            userInfo: [
              NSLocalizedDescriptionKey: NSLocalizedString(
                "profile_error_name_required", comment: "")
            ]
          )
        )
      }
      var commitCall: Call?
      var postCommitCalls: [Call] = []
      var minCommitmentAgeSeconds: UInt64 = 60
      let avatar = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
      let description = bio.trimmingCharacters(in: .whitespacesAndNewlines)
      var embeddedRecordKeys = Set<String>()

      if !isNameLocked {
        if normalizedName != lastQuotedName || nameInfoTone != .success {
          throw ENSServiceError.actionFailed(
            NSError(
              domain: "ENS",
              code: 2,
              userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString(
                  "profile_error_use_available_name", comment: "")
              ]
            )
          )
        }
        var initialRecords: [ENSRecordDraft] = []
        if !avatar.isEmpty, avatar != initialAvatarURL {
          initialRecords.append(ENSRecordDraft(key: "avatar", value: avatar))
          embeddedRecordKeys.insert("avatar")
        }
        if !description.isEmpty, description != initialBio {
          initialRecords.append(ENSRecordDraft(key: "description", value: description))
          embeddedRecordKeys.insert("description")
        }
        let registrationPayloads = try await ensService.registerNamePayloads(
          name: normalizedName,
          ownerAddress: eoaAddress,
          initialRecords: initialRecords
        )
        commitCall = registrationPayloads.commitCall
        postCommitCalls.append(registrationPayloads.registerCall)
        minCommitmentAgeSeconds = max(1, registrationPayloads.minCommitmentAgeSeconds)
        preparedPayloads += registrationPayloads.calls.count
      }

      if avatar != initialAvatarURL, !embeddedRecordKeys.contains("avatar") {
        let avatarPayload = try await ensService.updateRecordPayload(
          name: normalizedName,
          key: "avatar",
          value: avatar
        )
        postCommitCalls.append(avatarPayload)
        preparedPayloads += 1
      }

      if description != initialBio, !embeddedRecordKeys.contains("description") {
        let bioPayload = try await ensService.updateRecordPayload(
          name: normalizedName,
          key: "description",
          value: description
        )
        postCommitCalls.append(bioPayload)
        preparedPayloads += 1
      }

      guard commitCall != nil || !postCommitCalls.isEmpty else {
        showSuccess(String(localized: "profile_no_changes_to_save"))
        isEditingProfile = false
        return
      }

      let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
      if let commitCall {
        let commitSubmissionHash = try await aaExecutionService.executeCalls(
          accountService: accountService,
          account: sessionAccount,
          chainId: ensService.chainID,
          calls: [commitCall]
        )
        var pendingJob = PendingENSRevealJob(
          eoaAddress: eoaAddress,
          name: normalizedName,
          chainId: ensService.chainID,
          submissionHash: commitSubmissionHash,
          minCommitmentAgeSeconds: minCommitmentAgeSeconds,
          revealNotBeforeUnix: 0,
          postCommitCalls: postCommitCalls,
          preparedPayloadCount: preparedPayloads
        )
        commitRevealStore.saveJob(pendingJob)
        showSuccess(String(localized: "profile_commit_submitted_progress"))

        let revealNotBefore = try await waitForRevealWindowStart(for: pendingJob)
        pendingJob = PendingENSRevealJob(
          eoaAddress: pendingJob.eoaAddress,
          name: pendingJob.name,
          chainId: pendingJob.chainId,
          submissionHash: pendingJob.submissionHash,
          minCommitmentAgeSeconds: pendingJob.minCommitmentAgeSeconds,
          revealNotBeforeUnix: revealNotBefore.timeIntervalSince1970,
          postCommitCalls: pendingJob.postCommitCalls,
          preparedPayloadCount: pendingJob.preparedPayloadCount
        )
        commitRevealStore.saveJob(pendingJob)

        let delay = max(0, revealNotBefore.timeIntervalSinceNow)
        if delay > 0 {
          try await Task.sleep(for: .seconds(delay))
        }
      }

      if !postCommitCalls.isEmpty {
        _ = try await aaExecutionService.executeCalls(
          accountService: accountService,
          account: sessionAccount,
          chainId: ensService.chainID,
          calls: postCommitCalls
        )
      }

      if commitCall != nil {
        isNameLocked = true
        commitRevealStore.clearJob(for: eoaAddress)
      }

      initialAvatarURL = avatarURL
      initialBio = bio
      initialENSName = ensName
      let message = String.localizedStringWithFormat(
        NSLocalizedString("profile_saved_changes", comment: ""),
        preparedPayloads
      )
      showSuccess(message)
      isEditingProfile = false
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func importPhotoItem(_ item: PhotosPickerItem) async {
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else {
        throw URLError(.cannotDecodeRawData)
      }
      try preparePendingAvatarUpload(from: data)
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func importFile(_ result: Result<[URL], any Error>) async {
    do {
      guard let fileURL = try result.get().first else { return }
      let didStart = fileURL.startAccessingSecurityScopedResource()
      defer {
        if didStart { fileURL.stopAccessingSecurityScopedResource() }
      }

      let data = try Data(contentsOf: fileURL)
      try preparePendingAvatarUpload(from: data)
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func preparePendingAvatarUpload(from imageData: Data) throws {
    guard let image = UIImage(data: imageData),
      let jpegData = image.jpegData(compressionQuality: 0.86)
    else {
      throw URLError(.cannotDecodeRawData)
    }

    let fileName = "avatar-\(UUID().uuidString.lowercased()).jpg"
    _ = try imageStorageService.persistLocally(
      data: jpegData,
      eoaAddress: eoaAddress,
      fileName: fileName
    )

    localAvatarImage = image
    pendingAvatarUpload = PendingAvatarUpload(
      id: UUID(),
      data: jpegData,
      mimeType: "image/jpeg",
      fileName: fileName
    )
    startAvatarUploadIfNeeded()
  }

  @MainActor
  private func ensureAvatarUploadCompletedIfNeeded() async throws {
    guard pendingAvatarUpload != nil else { return }

    if !isUploadingAvatar {
      startAvatarUploadIfNeeded()
    }
    await avatarUploadTask?.value

    if pendingAvatarUpload != nil {
      throw ProfileImageStorageError.pendingUpload
    }
  }

  @MainActor
  private func startAvatarUploadIfNeeded() {
    guard let pendingAvatarUpload else { return }

    avatarUploadTask?.cancel()
    avatarUploadTask = Task {
      await runAvatarUpload(for: pendingAvatarUpload)
    }
  }

  @MainActor
  private func runAvatarUpload(for pending: PendingAvatarUpload) async {
    isUploadingAvatar = true
    defer {
      if pendingAvatarUpload?.id == pending.id || pendingAvatarUpload == nil {
        isUploadingAvatar = false
      }
    }

    do {
      let uploadedURL = try await imageStorageService.uploadAvatar(
        data: pending.data,
        eoaAddress: eoaAddress,
        fileName: pending.fileName,
        mimeType: pending.mimeType
      )

      guard pendingAvatarUpload?.id == pending.id else { return }
      avatarURL = uploadedURL.absoluteString
      self.pendingAvatarUpload = nil
    } catch is CancellationError {
      return
    } catch {
      guard pendingAvatarUpload?.id == pending.id else { return }
      showError(error)
    }
  }

  @MainActor
  private func clearAvatarSelection() {
    avatarUploadTask?.cancel()
    avatarUploadTask = nil
    isUploadingAvatar = false
    avatarURL = ""
    localAvatarImage = nil
    pendingAvatarUpload = nil
  }

  private func normalizeENSLabel(_ rawValue: String) -> String {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.hasSuffix(".eth") {
      return String(trimmed.dropLast(4))
    }
    return trimmed
  }

  private func color(for tone: NameInfoTone) -> Color {
    switch tone {
    case .info:
      return AppThemeColor.labelSecondary
    case .success:
      return AppThemeColor.accentGreen
    case .error:
      return AppThemeColor.accentRed
    }
  }

  @MainActor
  private func enterEditMode() {
    guard !isSaving else { return }
    isEditingProfile = true
    errorMessage = nil
    successMessage = nil

    if !isNameLocked {
      scheduleQuoteLookup(for: ensName)
    }
  }

  @MainActor
  private func cancelEditing() {
    quoteTask?.cancel()
    quoteTask = nil
    avatarUploadTask?.cancel()
    avatarUploadTask = nil
    isUploadingAvatar = false

    ensName = initialENSName
    avatarURL = initialAvatarURL
    bio = initialBio
    localAvatarImage = nil
    pendingAvatarUpload = nil
    selectedPhotoItem = nil

    isCheckingName = false
    nameInfoText = nil
    nameInfoTone = .info
    lastQuotedName = normalizeENSLabel(initialENSName)
    isEditingProfile = false
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

  @MainActor
  private func resumePendingCommitRevealIfNeeded() async {
    guard let pendingJob = commitRevealStore.loadJob(for: eoaAddress) else { return }

    do {
      showSuccess(String(localized: "profile_commit_submitted_progress"))

      var effectiveJob = pendingJob
      let revealNotBefore: Date
      if pendingJob.revealNotBeforeUnix > 0 {
        revealNotBefore = Date(timeIntervalSince1970: pendingJob.revealNotBeforeUnix)
      } else {
        let computed = try await waitForRevealWindowStart(for: pendingJob)
        revealNotBefore = computed
        effectiveJob = PendingENSRevealJob(
          eoaAddress: pendingJob.eoaAddress,
          name: pendingJob.name,
          chainId: pendingJob.chainId,
          submissionHash: pendingJob.submissionHash,
          minCommitmentAgeSeconds: pendingJob.minCommitmentAgeSeconds,
          revealNotBeforeUnix: computed.timeIntervalSince1970,
          postCommitCalls: pendingJob.postCommitCalls,
          preparedPayloadCount: pendingJob.preparedPayloadCount
        )
        commitRevealStore.saveJob(effectiveJob)
      }

      let delay = max(0, revealNotBefore.timeIntervalSinceNow)
      if delay > 0 {
        try await Task.sleep(for: .seconds(delay))
      }

      let sessionAccount = try await accountService.restoreSession(eoaAddress: eoaAddress)
      if !effectiveJob.postCommitCalls.isEmpty {
        _ = try await aaExecutionService.executeCalls(
          accountService: accountService,
          account: sessionAccount,
          chainId: effectiveJob.chainId,
          calls: effectiveJob.postCommitCalls
        )
      }

      isNameLocked = true
      commitRevealStore.clearJob(for: eoaAddress)
      let message = String.localizedStringWithFormat(
        NSLocalizedString("profile_saved_changes", comment: ""),
        effectiveJob.preparedPayloadCount
      )
      showSuccess(message)
    } catch {
      showError(error)
    }
  }

  private func waitForRevealWindowStart(for job: PendingENSRevealJob) async throws -> Date {
    let commitIncludedAt = try await aaExecutionService.waitForRelayInclusion(
      chainId: job.chainId,
      relayTaskID: job.submissionHash
    )
    return commitIncludedAt.addingTimeInterval(TimeInterval(job.minCommitmentAgeSeconds))
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

private actor ENSQuoteWorker {
  private let client: ENSClient

  init(configuration: ENSConfiguration) {
    client = ENSClient(configuration: configuration)
  }

  func quote(name: String) async throws -> ENSNameQuote {
    let quote = try await client.quoteRegistration(
      RegisterNameRequest(
        name: name,
        ownerAddress: "0x0000000000000000000000000000000000000000",
        duration: 31_536_000
      )
    )
    return ENSNameQuote(
      normalizedName: quote.normalizedName,
      available: quote.available,
      rentPriceWei: quote.rentPriceWei
    )
  }
}

private struct PendingAvatarUpload {
  let id: UUID
  let data: Data
  let mimeType: String
  let fileName: String
}

private enum NameInfoTone {
  case info
  case success
  case error
}

private struct ProfileGlassCapsuleButtonModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .buttonStyle(.glass)
    } else {
      content
        .background(
          Capsule()
            .fill(AppThemeColor.fillPrimary)
        )
    }
  }
}

private struct ProfileProminentActionButtonModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .buttonStyle(.glassProminent)
    } else {
      content
        .foregroundStyle(AppThemeColor.backgroundPrimary)
        .background(
          Capsule()
            .fill(Color.blue)
        )
    }
  }
}

#Preview {
  ProfileView(
    eoaAddress: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193",
    accountService: AccountSetupService(),
    ensService: ENSService(),
    aaExecutionService: AAExecutionService()
  )
}
