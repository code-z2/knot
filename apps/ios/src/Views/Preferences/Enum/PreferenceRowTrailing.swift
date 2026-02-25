//
//  PreferenceRowTrailing.swift
//  Created by Peter Anyaogu on 24/02/2026.
//

import SwiftUI

enum PreferenceRowTrailing {
    case chevron

    case toggle(isOn: Binding<Bool>)

    case valueChevron(String)

    case localizedValueChevron(LocalizedStringKey)

    case custom(AnyView)
}
