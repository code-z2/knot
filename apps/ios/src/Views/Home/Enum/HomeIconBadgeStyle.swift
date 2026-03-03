// HomeIconBadgeStyle.swift
// Created by Peter Anyaogu on 02/03/2026.

import SwiftUI

enum HomeIconBadgeStyle {
    case solid(background: Color, icon: Color? = nil)

    case gradient(colors: [Color], icon: Color? = nil)
}
