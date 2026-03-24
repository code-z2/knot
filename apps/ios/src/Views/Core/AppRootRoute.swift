// AppRootRoute.swift
// Created by Peter Anyaogu on 24/02/2026.

import Foundation

enum AppRootRoute {
    case splash

    case onboarding

    case main
}

enum AppRootDestination: Hashable {
    case profile
    case gasTank
    case gasTankInformation
    case gasTankTopUp(GasTankTopUpDraft)
    case preferences
    case helpSupport
    case addressBook
    case receive
    case sendMoney
    case walletBackup
}
