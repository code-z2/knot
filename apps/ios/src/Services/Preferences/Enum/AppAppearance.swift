// AppAppearance.swift
// Created by Peter Anyaogu on 02/03/2026.

import Foundation

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark

    case system

    case light

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .dark: "Dark"
        case .system: "System"
        case .light: "Light"
        }
    }
}
