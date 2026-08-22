//
//  Shapes.swift
//  ErrandRun
//
//  Bevelled cards, parallelograms, diamonds and sparks.
//

import SwiftUI

// MARK: - Rounded polygon helper

extension Path {
    static func rounded(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let count = points.count
        let first = points[0]
        let second = points[1]
        path.move(to: CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2))
        for index in 1...count {
            let current = points[index % count]
            let next = points[(index + 1) % count]
            path.addArc(tangent1End: current, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

private func bevelInset(for height: CGFloat, degrees: CGFloat, cap: CGFloat) -> CGFloat {
    min(height * tan(degrees * .pi / 180), cap)
}

// MARK: - Bevelled card

/// A rounded rectangle whose left edge leans by `degrees`.
struct BeveledRect: Shape {
    var radius: CGFloat = ERMetric.cardRadius
    var degrees: CGFloat = ERMetric.bevel
    var cap: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let dx = bevelInset(for: rect.height, degrees: degrees, cap: cap)
        return .rounded([
            CGPoint(x: rect.minX + dx, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ], radius: radius)
    }
}

/// The status stripe living inside the card, repeating the same lean.
struct BeveledStripe: Shape {
    var width: CGFloat = ERMetric.statusStripe
    var degrees: CGFloat = ERMetric.bevel
    var cap: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let dx = bevelInset(for: rect.height, degrees: degrees, cap: cap)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + dx, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + dx + width, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + width, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Both edges lean — the tab indicator and chips-in-motion.
struct ParallelogramShape: Shape {
    var radius: CGFloat = 10
    var degrees: CGFloat = ERMetric.bevel
    var cap: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let dx = bevelInset(for: rect.height, degrees: degrees, cap: cap)
        return .rounded([
            CGPoint(x: rect.minX + dx, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX - dx, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ], radius: radius)
    }
}

// MARK: - Motif

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

/// Four-ray spark, drawn as strokes.
struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Scattered motif field

/// Deterministic scatter of diamonds and sparks. Never sits on top of text —
/// always used as a background layer with its own frame.
struct SparkField: View {
    var seed: Int
    var count: Int = 7
    var bright: Bool = false

    var body: some View {
        GeometryReader { geo in
            let marks = Self.marks(seed: seed, count: count, size: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(marks) { mark in
                    Group {
                        if mark.isDiamond {
                            DiamondShape()
                                .fill(mark.gold ? ER.gold : ER.orange)
                                .frame(width: mark.size, height: mark.size)
                        } else {
                            SparkShape()
                                .stroke(mark.gold ? ER.gold : ER.orange, lineWidth: 2)
                                .frame(width: mark.size + 4, height: mark.size + 4)
                        }
                    }
                    .rotationEffect(.degrees(mark.rotation))
                    .position(x: mark.x, y: mark.y)
                }
            }
            .opacity(bright ? 0.6 : 0.35)
        }
        .allowsHitTesting(false)
    }

    struct Mark: Identifiable {
        var id: Int
        var x: CGFloat, y: CGFloat, size: CGFloat, rotation: Double
        var isDiamond: Bool, gold: Bool
    }

    static func marks(seed: Int, count: Int, size: CGSize) -> [Mark] {
        var state = UInt64(truncatingIfNeeded: seed &* 2_654_435_761 &+ 12345)
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double((state >> 33) % 10_000) / 10_000
        }
        return (0..<count).map { index in
            Mark(
                id: index,
                x: CGFloat(next()) * max(size.width, 1),
                y: CGFloat(next()) * max(size.height, 1),
                size: next() > 0.5 ? 10 : 6,
                rotation: next() * 90,
                isDiamond: next() > 0.45,
                gold: next() > 0.5
            )
        }
    }
}

// MARK: - Card chrome

extension View {
    /// Dense, unblurred shadow — 4pt down and right, no blur.
    func denseShadow(_ color: Color = ER.cherry, active: Bool = true) -> some View {
        shadow(color: active ? color : .clear,
               radius: 0,
               x: active ? ERMetric.shadowOffset : 0,
               y: active ? ERMetric.shadowOffset : 0)
    }

    /// The gold glow of a completed errand.
    func goldGlow(_ active: Bool) -> some View {
        shadow(color: active ? ER.glow : .clear, radius: active ? 14 : 0, x: 0, y: 0)
    }
}
