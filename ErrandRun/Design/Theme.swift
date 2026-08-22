//
//  Theme.swift
//  ErrandRun
//
//  Colour, gradient and type foundations.
//

import SwiftUI

// MARK: - Palette

enum ER {
    static let cream = Color(hex: 0xFFF0D6)
    static let card = Color(hex: 0xFFFAEC)
    static let charcoal = Color(hex: 0x171316)
    static let cherry = Color(hex: 0x3A0B12)
    static let scarlet = Color(hex: 0xFF3426)
    static let orange = Color(hex: 0xFF7A18)
    static let gold = Color(hex: 0xFFD24A)
    static let darkCard = Color(hex: 0x4A1219)

    /// The one blur in the whole app: the glow on a finished errand.
    static let glow = Color(hex: 0xFFD24A).opacity(0.5)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Fire gradient

extension LinearGradient {
    /// Three stops at 120 degrees: scarlet, orange, gold.
    static func fire(_ angle: Double = 120) -> LinearGradient {
        let radians = angle * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return LinearGradient(
            colors: [ER.scarlet, ER.orange, ER.gold],
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 + dy),
            endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 - dy)
        )
    }
}

extension ShapeStyle where Self == LinearGradient {
    static var fire: LinearGradient { .fire() }
}

// MARK: - Type

extension Font {
    static let erScreenTitle = Font.system(size: 36, weight: .black).italic()
    static let erScreenTitleSmall = Font.system(size: 28, weight: .black).italic()
    static let erSection = Font.system(size: 14, weight: .black).italic()
    static let erHuge = Font.system(size: 60, weight: .black).italic()
    static let erNumber = Font.system(size: 34, weight: .black).italic()
    static let erHours = Font.system(size: 16, weight: .bold).monospacedDigit()
    static let erHoursSmall = Font.system(size: 13, weight: .bold).monospacedDigit()
    static let erBody = Font.system(size: 16)
    static let erBodyBold = Font.system(size: 16, weight: .semibold)
    static let erCaption = Font.system(size: 13, weight: .semibold)
    static let erCardTitle = Font.system(size: 18, weight: .black).italic()
    static let erButton = Font.system(size: 18, weight: .black).italic()
    static let erTab = Font.system(size: 10, weight: .black).italic()
}

// MARK: - Metrics

enum ERMetric {
    static let cardRadius: CGFloat = 12
    static let bevel: CGFloat = 8          // degrees
    static let stroke: CGFloat = 2.5
    static let shadowOffset: CGFloat = 4
    static let tabBarHeight: CGFloat = 88
    static let buttonHeight: CGFloat = 58
    static let chipHeight: CGFloat = 40
    static let statusStripe: CGFloat = 10
    static let screenPadding: CGFloat = 18
}

// MARK: - Motion

extension Animation {
    /// Card entry / route rebuild.
    static let erCard = Animation.interpolatingSpring(stiffness: 340, damping: 18)
    /// Tab indicator travel.
    static let erTab = Animation.interpolatingSpring(stiffness: 320, damping: 20)
    /// Button press.
    static let erPress = Animation.easeOut(duration: 0.08)
    /// Screen darkening for run mode.
    static let erDarken = Animation.easeInOut(duration: 0.4)
    /// Route rebuild fan.
    static let erRebuild = Animation.interpolatingSpring(stiffness: 260, damping: 20)
}

// MARK: - Status colour

enum ERStatusTone {
    case idle, active, done, blocked, dropped, waiting

    var color: Color {
        switch self {
        case .idle: return ER.charcoal
        case .active: return ER.scarlet
        case .done: return ER.gold
        case .blocked: return ER.cherry
        case .dropped: return ER.charcoal.opacity(0.35)
        case .waiting: return ER.orange
        }
    }
}
