// CurrencyOption.swift
// Created by Peter Anyaogu on 02/03/2026.

import Foundation

struct CurrencyOption: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let iconAssetName: String

    var id: String {
        code
    }
}
