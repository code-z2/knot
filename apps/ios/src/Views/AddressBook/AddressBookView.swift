import SwiftUI

struct AddressBookView: View {
  let eoaAddress: String
  let store: BeneficiaryStore
  let ensService: ENSService
  var onBack: () -> Void = {}

  @State private var searchText = ""
  @State private var isSearchFocused = false
  @State private var beneficiaries: [Beneficiary] = []
  @State private var showAddScreen = false
  @State private var errorMessage: String?
  @State private var successTrigger = 0

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      VStack(spacing: 0) {
        headerTools
          .padding(.top, AppHeaderMetrics.contentTopPadding)
          .padding(.horizontal, 25)

        if visibleBeneficiaries.isEmpty {
          emptyState
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 25)
        } else {
          listState
            .padding(.top, AppSpacing.xl)
        }
      }

      if let errorMessage {
        toast(message: errorMessage)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, 28)
          .padding(.horizontal, AppSpacing.lg)
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      AppHeader(
        title: "address_book_title",
        titleFont: .custom("Roboto-Bold", size: 22),
        titleColor: AppThemeColor.labelSecondary,
        onBack: onBack
      )
    }
    .task { await reload() }
    .sensoryFeedback(AppHaptic.success.sensoryFeedback, trigger: successTrigger) { _, _ in true }
    .fullScreenCover(isPresented: $showAddScreen) {
      AddAddressView(beneficiaries: beneficiaries, ensService: ensService) { draft in
        await addBeneficiary(draft)
      }
    }
  }

  private var headerTools: some View {
    HStack(spacing: AppSpacing.sm) {
      SearchInput(
        text: $searchText,
        placeholderKey: "search_placeholder",
        width: isSearchFocused ? nil : 285
      ) { focused in
        isSearchFocused = focused
      }

      if !isSearchFocused {
        Button {
          showAddScreen = true
        } label: {
          Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppThemeColor.accentBrown)
                .frame(width: 44, height: 44)
        }
        .clipShape(.circle)
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Dismiss search"))
      }
    }
    .frame(width: 351, height: 50)
    .animation(.spring(response: 0.26, dampingFraction: 0.82), value: isSearchFocused)
  }

  private var listState: some View {
    List {
      ForEach(visibleBeneficiaries) { beneficiary in
        BeneficiaryRow(beneficiary: beneficiary)
          .listRowInsets(EdgeInsets(top: 0, leading: 15, bottom: 6, trailing: 15))
          .listRowSeparatorTint(AppThemeColor.separatorOpaque)
          .listRowBackground(Color.clear)
          .swipeActions(edge: .trailing, allowsFullSwipe: true) {
              Button(role: .destructive) {
              Task { await deleteBeneficiary(beneficiary.id) }
            } label: {
              Image(systemName: "trash")
            }
          }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(AppThemeColor.backgroundPrimary)
    .padding(.bottom, 30)
  }

  private var emptyState: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 130)
      Text("empty_beneficiary")
        .font(.custom("Roboto-Regular", size: 15))
        .foregroundStyle(AppThemeColor.labelSecondary.opacity(0.45))
      Spacer()
    }
  }

  private var visibleBeneficiaries: [Beneficiary] {
    SearchSystem.filter(
      query: searchText,
      items: beneficiaries,
      toDocument: {
        SearchDocument(
          id: $0.id,
          title: $0.name,
          keywords: [$0.address, $0.chainLabel ?? ""]
        )
      },
      itemID: { $0.id }
    )
  }

  @MainActor
  private func reload() async {
    do {
      beneficiaries = try store.list(eoaAddress: eoaAddress)
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func addBeneficiary(_ draft: AddBeneficiaryDraft) async {
    let entry = Beneficiary(name: draft.name, address: draft.address, chainLabel: draft.chain)
    do {
      try store.upsert(entry, for: eoaAddress)
      beneficiaries = try store.list(eoaAddress: eoaAddress)
      successTrigger += 1
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func deleteBeneficiary(_ id: UUID) async {
    do {
      try store.delete(id: id, for: eoaAddress)
      beneficiaries.removeAll { $0.id == id }
      successTrigger += 1
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func showError(_ error: Error) {
    errorMessage = error.localizedDescription
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2.5))
      if errorMessage == error.localizedDescription {
        errorMessage = nil
      }
    }
  }

  private func toast(message: String) -> some View {
    ToastView(message: message)
  }
}

struct AddBeneficiaryDraft: Sendable {
  let name: String
  let address: String
  let chain: String?
}

#Preview {
  AddressBookView(
    eoaAddress: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193",
    store: BeneficiaryStore(),
    ensService: ENSService()
  )
}
