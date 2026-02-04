import SwiftUI

struct ToggleSwitch: View {
  @Binding var isOn: Bool
  var onToggle: (() -> Void)? = nil

  var body: some View {
    Button {
      isOn.toggle()
      onToggle?()
    } label: {
      Image(isOn ? "Icons/toggle_01_right" : "Icons/toggle_01_left")
        .renderingMode(.original)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 24, height: 24)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Toggle")
    .accessibilityValue(isOn ? "On" : "Off")
    .accessibilityAddTraits(.isButton)
  }
}

#Preview {
  VStack(spacing: 12) {
    ToggleSwitch(isOn: .constant(false))
    ToggleSwitch(isOn: .constant(true))
  }
  .padding()
  .background(AppThemeColor.fixedDarkSurface)
}
