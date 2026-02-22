import ENS
import PhotosUI
import SwiftUI
import Transactions
import UIKit
import UniformTypeIdentifiers

struct ProfileView: View {
    enum FocusedField: Hashable {
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

    @State var ensName = ""
    @State var avatarURL = ""
    @State var bio = ""
    @State var isNameLocked = false
    @State var isCheckingName = false
    @State var lastQuotedName = ""
    @State var nameInfoText: String?
    @State var nameInfoTone: NameInfoTone = .info
    @State var isSaving = false
    @State var isUploadingAvatar = false
    @State var errorMessage: String?
    @State var successMessage: String?
    @State var preparedPayloads = 0
    @State var initialENSName = ""
    @State var initialAvatarURL = ""
    @State var initialBio = ""
    @State var localAvatarImage: UIImage?
    @State var pendingAvatarUpload: PendingAvatarUpload?
    @State var showPhotoSourceDialog = false
    @State var showPhotoPicker = false
    @State var showFileImporter = false
    @State var selectedPhotoItem: PhotosPickerItem?
    @State var quoteTask: Task<Void, Never>?
    @State var avatarUploadTask: Task<Void, Never>?
    @State var errorMessageResetTask: Task<Void, Never>?
    @State var successMessageResetTask: Task<Void, Never>?
    @State var saveFlowState: ProfileAsyncStateModel = .idle
    @State var avatarUploadFlowState: ProfileAsyncStateModel = .idle
    @State var successTrigger = 0
    @State var errorTrigger = 0
    @FocusState var focusedField: FocusedField?
    let quoteWorker: ENSQuoteWorker

    init(
        eoaAddress: String,
        accountService: AccountSetupService,
        ensService: ENSService,
        aaExecutionService: AAExecutionService,
        imageStorageService: ProfileImageStorageService = ProfileImageStorageService(),
        commitRevealStore: ENSCommitRevealStore = ENSCommitRevealStore(),
        onBack: @escaping () -> Void = {},
    ) {
        self.eoaAddress = eoaAddress
        self.accountService = accountService
        self.ensService = ensService
        self.aaExecutionService = aaExecutionService
        self.imageStorageService = imageStorageService
        self.commitRevealStore = commitRevealStore
        quoteWorker = ENSQuoteWorker(configuration: ensService.configuration)
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            AppThemeColor.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    ProfileAvatarSectionView(
                        localAvatarImage: localAvatarImage,
                        remoteAvatarURL: remoteAvatarURL,
                        canEditProfileFields: canEditProfileFields,
                        onEditPhoto: { showPhotoSourceDialog = true },
                    )
                    .padding(.top, 46)
                    .padding(.bottom, AppSpacing.xxxl)

                    if let nameInfoText, !isNameLocked {
                        infoText(nameInfoText, tone: nameInfoTone)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.bottom, AppSpacing.sm)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    formSection
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusedField = nil
                },
            )
            .padding(.top, AppHeaderMetrics.contentTopPadding)

            if let errorMessage {
                toast(message: errorMessage, isError: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xl)
            }

            if let successMessage {
                toast(message: successMessage, isError: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xl)
            }
        }
        .animation(.default, value: nameInfoText)
        .animation(.spring(), value: errorMessage)
        .animation(.spring(), value: successMessage)
        .safeAreaInset(edge: .top, spacing: 0) {
            ProfileHeaderView(
                hasChanges: hasSavableChanges,
                isSaving: isSaving,
                canSave: canSave,
                onBack: onBack,
                onCancel: { cancelEditing() },
                onSave: { Task { await saveProfile() } },
            )
        }
        .task {
            await loadProfile()
            await resumePendingCommitRevealIfNeeded()
        }
        .onChange(of: ensName) { _, newValue in
            guard !isNameLocked else { return }
            scheduleQuoteLookup(for: newValue)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await importPhotoItem(newItem) }
        }
        .confirmationDialog(
            String(localized: "profile_change_photo_title"),
            isPresented: $showPhotoSourceDialog,
            titleVisibility: .visible,
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
            preferredItemEncoding: .automatic,
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
        ) { result in
            Task { await importFile(result) }
        }
        .onDisappear {
            quoteTask?.cancel()
            quoteTask = nil
            avatarUploadTask?.cancel()
            avatarUploadTask = nil
            errorMessageResetTask?.cancel()
            errorMessageResetTask = nil
            successMessageResetTask?.cancel()
            successMessageResetTask = nil
        }
        .sensoryFeedback(AppHaptic.success.sensoryFeedback, trigger: successTrigger) { _, _ in true }
        .sensoryFeedback(AppHaptic.error.sensoryFeedback, trigger: errorTrigger) { _, _ in true }
    }

    var formSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: 10) {
                        TextField(
                            "",
                            text: $ensName,
                            prompt: Text("profile_enter_name_placeholder")
                                .font(.custom("Roboto-Medium", size: 14))
                                .foregroundStyle(AppThemeColor.labelSecondary),
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
                .padding(AppSpacing.md)

                Rectangle()
                    .fill(AppThemeColor.separatorOpaque.opacity(0.7))
                    .frame(height: 1)
                    .padding(.horizontal, AppSpacing.sm)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
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
                                .padding(.top, AppSpacing.xs)
                                .padding(.leading, AppSpacing.xxs)
                                .allowsHitTesting(false)
                                .opacity(canEditProfileFields ? 1 : 0.72)
                        }
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppThemeColor.backgroundSecondary)
            .clipShape(.rect(cornerRadius: 16))

            Text(
                "Your ENS name is visible on the blockchain. Including your text records, i.e photo and bio.",
            )
            .font(.custom("Roboto-Regular", size: 12))
            .foregroundStyle(AppThemeColor.labelSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.sm)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.xl)
    }

    var canEditProfileFields: Bool {
        !isSaving
    }

    var nameFieldIsLocked: Bool {
        isNameLocked || isSaving
    }

    var canSave: Bool {
        guard !isSaving, !isCheckingName else { return false }
        if !isNameLocked, !hasReadyNameRegistration {
            return false
        }
        return hasSavableChanges
    }

    var hasSavableChanges: Bool {
        if isNameLocked {
            return hasProfileRecordChanges
        }

        // While name is unlocked, we only allow save once the current name quote
        // is validated as available and matches the latest normalized input.
        return hasReadyNameRegistration || hasProfileRecordChanges
    }

    var hasReadyNameRegistration: Bool {
        let normalizedName = normalizeENSLabel(ensName)
        return !normalizedName.isEmpty
            && normalizedName == lastQuotedName
            && nameInfoTone == .success
    }

    var hasProfileRecordChanges: Bool {
        let avatar = avatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        return pendingAvatarUpload != nil || avatar != initialAvatarURL || description != initialBio
    }

    var remoteAvatarURL: URL? {
        URL(string: avatarURL.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

#Preview {
    ProfileView(
        eoaAddress: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193",
        accountService: AccountSetupService(),
        ensService: ENSService(),
        aaExecutionService: AAExecutionService(),
    )
}
