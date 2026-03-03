// AppBootstrapResultModel.swift
// Created by Peter Anyaogu on 02/03/2026.

import Foundation

enum AppBootstrapResultModel: Sendable {
    case onboarding

    case activeSession(AppSessionStateModel)
}
