// LanguageOption.swift
// Created by Peter Anyaogu on 02/03/2026.

import Foundation

struct LanguageOption: Identifiable, Equatable, Sendable {
    let code: String
    let displayName: String
    let flag: String

    var id: String {
        code
    }
}
