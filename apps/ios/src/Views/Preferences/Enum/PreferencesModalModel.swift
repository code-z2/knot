// PreferencesModalModel.swift
// Created by Peter Anyaogu on 24/02/2026.

import SwiftUI

enum PreferencesModalModel: String, Identifiable {
    case appearance

    var id: String {
        rawValue
    }

    var sheetKind: AppSheetKind {
        .height(260)
    }
}
