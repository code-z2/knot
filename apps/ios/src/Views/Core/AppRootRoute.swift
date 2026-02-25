// AppRootRoute.swift
// Created by Martin Lasek on 24/02/2026.

import Foundation

enum AppRootRoute {
    case splash

    case onboarding

    case main
}

enum AppRootDestination: Hashable {
    case profile
    case preferences
    case addressBook
    case receive
    case sendMoney
    case walletBackup
}
