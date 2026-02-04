import SwiftUI

struct AddressBookView: View {
  let eoaAddress: String
  let store: BeneficiaryStore
  var onBack: () -> Void = {}

  @State private var searchText = ""
  @State private var beneficiaries: [Beneficiary] = []
  @State private var showAddSheet = false
  @State private var errorMessage: String?

  var body: some View {
    ZStack(alignment: .topLeading) {
      AppThemeColor.fixedDarkSurface.ignoresSafeArea()

      BackNavigationButton(action: onBack)
      .offset(x: 20, y: 39)

      VStack(spacing: 0) {
        Text("Address Book")
          .font(.custom("Inter-Bold", size: 22))
          .foregroundStyle(AppThemeColor.labelSecondary)
          .padding(.top, 48)
          .padding(.bottom, 21)

        headerTools
          .padding(.horizontal, 25)

        if visibleBeneficiaries.isEmpty {
          emptyState
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 25)
        } else {
          listState
            .padding(.top, 24)
        }
      }

      if let errorMessage {
        toast(message: errorMessage)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .padding(.bottom, 28)
          .padding(.horizontal, 20)
      }
    }
    .task { await reload() }
    .sheet(isPresented: $showAddSheet) {
      AddBeneficiarySheet { draft in
        await addBeneficiary(draft)
      }
      .presentationDetents([.fraction(0.50)])
      .presentationDragIndicator(.visible)
    }
  }

  private var headerTools: some View {
    HStack(spacing: 12) {
      SearchInput(text: $searchText, placeholder: "Search", width: 285)

      Button {
        showAddSheet = true
      } label: {
        Image("Icons/plus")
          .renderingMode(.template)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 24, height: 24)
          .foregroundStyle(AppThemeColor.accentBrown)
          .frame(width: 66, height: 50)
      }
      .buttonStyle(.plain)
    }
    .frame(width: 351, height: 50)
  }

  private var listState: some View {
    ScrollView(showsIndicators: false) {
      LazyVStack(spacing: 6) {
        ForEach(visibleBeneficiaries) { beneficiary in
          BeneficiaryRow(beneficiary: beneficiary)
            .padding(.horizontal, 25)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              Button(role: .destructive) {
                Task { await deleteBeneficiary(beneficiary.id) }
              } label: {
                Image("Icons/trash_03")
                  .renderingMode(.template)
              }
              .tint(AppThemeColor.accentRed)
            }
        }
      }
      .padding(.top, 0)
      .padding(.bottom, 36)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 0) {
      Spacer().frame(height: 130)
      Text("You have not added any beneficiary")
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
      beneficiaries = try await store.list(eoaAddress: eoaAddress)
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func addBeneficiary(_ draft: AddBeneficiaryDraft) async {
    let entry = Beneficiary(name: draft.name, address: draft.address, chainLabel: draft.chain)
    do {
      try await store.upsert(entry, for: eoaAddress)
      beneficiaries = try await store.list(eoaAddress: eoaAddress)
    } catch {
      showError(error)
    }
  }

  @MainActor
  private func deleteBeneficiary(_ id: UUID) async {
    do {
      try await store.delete(id: id, for: eoaAddress)
      beneficiaries.removeAll { $0.id == id }
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
    Text(message)
      .font(.custom("RobotoMono-Medium", size: 12))
      .foregroundStyle(AppThemeColor.labelPrimary)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(AppThemeColor.fillPrimary)
      )
  }
}

private struct AddBeneficiaryDraft {
  let name: String
  let address: String
  let chain: String?
}

private struct AddBeneficiarySheet: View {
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var address = ""
  @State private var chain = ""

  let onSave: (AddBeneficiaryDraft) async -> Void

  var body: some View {
    NavigationStack {
      ZStack {
        AppThemeColor.fixedDarkSurface.ignoresSafeArea()

        VStack(spacing: 14) {
          field(title: "Name", text: $name, placeholder: "Alice")
          field(title: "Wallet Address", text: $address, placeholder: "0x...")
          field(title: "Chain (optional)", text: $chain, placeholder: "Base")

          AppButton(label: "Save", variant: .default) {
            Task {
              await onSave(
                .init(
                  name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                  address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                  chain: chain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil : chain.trimmingCharacters(in: .whitespacesAndNewlines)
                )
              )
              dismiss()
            }
          }
          .frame(maxWidth: .infinity, minHeight: 48)
          .disabled(!isValid)
          .opacity(isValid ? 1 : 0.5)
          .padding(.top, 8)
        }
        .padding(20)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
            .foregroundStyle(AppThemeColor.labelSecondary)
        }
        ToolbarItem(placement: .principal) {
          Text("Add Beneficiary")
            .font(.custom("Roboto-Bold", size: 16))
            .foregroundStyle(AppThemeColor.labelPrimary)
        }
      }
    }
  }

  private var isValid: Bool {
    !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func field(title: String, text: Binding<String>, placeholder: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.custom("RobotoMono-Medium", size: 12))
        .foregroundStyle(AppThemeColor.labelSecondary)

      TextField(placeholder, text: text)
        .font(.custom("Roboto-Regular", size: 15))
        .foregroundStyle(AppThemeColor.labelPrimary)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
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
    }
  }
}

#Preview {
  AddressBookView(
    eoaAddress: "0xF5bB7F874D8e3f41821175c0Aa9910d30d10e193",
    store: BeneficiaryStore()
  )
}
