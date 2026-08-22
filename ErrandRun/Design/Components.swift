//
//  Components.swift
//  ErrandRun
//
//  Every shared control in the app.
//

import SwiftUI

// MARK: - Titles

struct ERScreenTitle: View {
    var text: String
    var small: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(small ? .erScreenTitleSmall : .erScreenTitle)
            .tracking(-0.5)
            .foregroundStyle(.fire)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ERSectionHeader: View {
    var text: String
    var trailing: String? = nil
    var dark: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.erSection)
                .tracking(1)
                .foregroundStyle(dark ? ER.cream.opacity(0.75) : ER.charcoal)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing.uppercased())
                    .font(.erSection)
                    .tracking(1)
                    .foregroundStyle(dark ? ER.gold : ER.charcoal.opacity(0.5))
            }
        }
    }
}

/// The app explaining itself in its own voice.
struct ERNote: View {
    var text: String
    var dark: Bool = false

    var body: some View {
        Text(text)
            .font(.erCaption)
            .italic()
            .foregroundStyle(dark ? ER.cream.opacity(0.7) : ER.charcoal.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Card

struct ERCard<Content: View>: View {
    var index: Int = 0
    var tone: ERStatusTone? = nil
    var glow: Bool = false
    var dark: Bool = false
    var tilt: Bool = true
    var padding: CGFloat = 15
    @ViewBuilder var content: Content

    init(index: Int = 0,
         tone: ERStatusTone? = nil,
         glow: Bool = false,
         dark: Bool = false,
         tilt: Bool = true,
         padding: CGFloat = 15,
         @ViewBuilder content: () -> Content) {
        self.index = index
        self.tone = tone
        self.glow = glow
        self.dark = dark
        self.tilt = tilt
        self.padding = padding
        self.content = content()
    }

    private var strokeColor: Color {
        if glow { return ER.gold }
        return dark ? ER.orange : ER.charcoal
    }

    var body: some View {
        content
            .padding(.vertical, padding)
            .padding(.trailing, padding)
            .padding(.leading, tone == nil ? padding : padding + ERMetric.statusStripe + 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .leading) {
                    BeveledRect().fill(dark ? ER.darkCard : ER.card)
                    if let tone {
                        BeveledStripe().fill(tone.color)
                    }
                }
            }
            .overlay {
                BeveledRect().stroke(strokeColor, lineWidth: glow ? 2 : ERMetric.stroke)
            }
            .compositingGroup()
            .denseShadow(dark ? Color.black.opacity(0.55) : ER.cherry)
            .goldGlow(glow)
            .rotationEffect(.degrees(tilt ? (index % 2 == 0 ? 2 : -2) : 0))
    }
}

struct CardAppear: ViewModifier {
    var index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(shown ? 0 : (index % 2 == 0 ? 4 : -4)))
            .offset(y: shown ? 0 : 26)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.erCard.delay(Double(min(index, 8)) * 0.04)) { shown = true }
            }
    }
}

extension View {
    func erAppear(_ index: Int) -> some View { modifier(CardAppear(index: index)) }
}

// MARK: - Buttons

private struct FireLabel: View {
    var configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.erButton)
            .textCase(.uppercase)
            .foregroundStyle(ER.cherry)
            .frame(maxWidth: .infinity)
            .frame(height: ERMetric.buttonHeight)
            .background {
                BeveledRect().fill(isEnabled ? AnyShapeStyle(.fire) : AnyShapeStyle(ER.charcoal.opacity(0.18)))
            }
            .overlay { BeveledRect().stroke(ER.charcoal, lineWidth: isEnabled ? 0 : 2) }
            .opacity(isEnabled ? 1 : 0.7)
            .compositingGroup()
            .denseShadow(ER.cherry, active: isEnabled && !configuration.isPressed)
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .animation(.erPress, value: configuration.isPressed)
    }
}

struct FireButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { FireLabel(configuration: configuration) }
}

struct GhostButtonStyle: ButtonStyle {
    var dark: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.erButton)
            .textCase(.uppercase)
            .foregroundStyle(dark ? ER.cream : ER.charcoal)
            .frame(maxWidth: .infinity)
            .frame(height: ERMetric.buttonHeight)
            .overlay { BeveledRect().stroke(dark ? ER.cream : ER.charcoal, lineWidth: 3) }
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .animation(.erPress, value: configuration.isPressed)
    }
}

struct CancelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.erButton)
            .textCase(.uppercase)
            .foregroundStyle(ER.cream)
            .frame(maxWidth: .infinity)
            .frame(height: ERMetric.buttonHeight)
            .background { BeveledRect().fill(ER.cherry) }
            .compositingGroup()
            .denseShadow(ER.charcoal, active: !configuration.isPressed)
            .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
            .animation(.erPress, value: configuration.isPressed)
    }
}

/// Small square-ish action used in headers and rows.
struct ERIconButton: View {
    var systemName: String
    var dark: Bool = false
    var filled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(filled ? ER.cherry : (dark ? ER.cream : ER.charcoal))
                .frame(width: 46, height: 42)
                .background {
                    if filled {
                        BeveledRect(radius: 10).fill(.fire)
                    } else {
                        BeveledRect(radius: 10).stroke(dark ? ER.cream : ER.charcoal, lineWidth: 2.5)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chips

struct ERChip: View {
    var title: String
    var selected: Bool
    var dark: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.erCaption)
                .foregroundStyle(selected ? ER.cherry : (dark ? ER.cream : ER.charcoal))
                .padding(.horizontal, 16)
                .frame(height: ERMetric.chipHeight)
                .background {
                    if selected {
                        BeveledRect(radius: 10, cap: 10).fill(.fire)
                    } else {
                        BeveledRect(radius: 10, cap: 10).stroke(dark ? ER.cream.opacity(0.6) : ER.charcoal, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct ERChipRow<T: Hashable>: View {
    var items: [T]
    var title: (T) -> String
    @Binding var selection: T
    var dark: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(items, id: \.self) { item in
                    ERChip(title: title(item), selected: item == selection, dark: dark) {
                        withAnimation(.erPress) { selection = item }
                    }
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
        }
    }
}

/// Non-interactive tag.
struct ERTag: View {
    var text: String
    var color: Color = ER.charcoal
    var filled: Bool = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black).italic())
            .tracking(0.8)
            .foregroundStyle(filled ? ER.cherry : color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                if filled {
                    BeveledRect(radius: 7, cap: 6).fill(color)
                } else {
                    BeveledRect(radius: 7, cap: 6).stroke(color, lineWidth: 2)
                }
            }
    }
}

// MARK: - Numbers

struct ERBigNumber: View {
    var value: String
    var caption: String
    var dark: Bool = false
    var gradient: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: -4) {
            Text(value)
                .font(.erHuge)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(gradient ? AnyShapeStyle(.fire) : AnyShapeStyle(dark ? ER.cream : ER.charcoal))
            Text(caption.uppercased())
                .font(.erSection)
                .tracking(1)
                .foregroundStyle(dark ? ER.cream.opacity(0.7) : ER.charcoal.opacity(0.7))
        }
    }
}

// MARK: - Empty / loading / error states

struct EREmptyState: View {
    var title: String
    var message: String
    var primaryTitle: String? = nil
    var primaryAction: (() -> Void)? = nil
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    var dark: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The motif lives in its own band, above the words — never across them.
            SparkField(seed: title.count, count: 9, bright: dark)
                .frame(height: 54)
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.erScreenTitleSmall)
                    .tracking(-0.5)
                    .foregroundStyle(.fire)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.erBody)
                    .foregroundStyle(dark ? ER.cream.opacity(0.85) : ER.charcoal.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let primaryTitle, let primaryAction {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(FireButtonStyle())
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(GhostButtonStyle(dark: dark))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

struct ERLoadingState: View {
    var text: String
    @State private var spin = false

    var body: some View {
        HStack(spacing: 12) {
            DiamondShape()
                .fill(.fire)
                .frame(width: 18, height: 18)
                .rotationEffect(.degrees(spin ? 180 : 0))
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: spin)
            Text(text.uppercased())
                .font(.erSection)
                .tracking(1)
                .foregroundStyle(ER.charcoal.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
        .onAppear { spin = true }
    }
}

struct ERErrorState: View {
    var title: String
    var message: String
    var retryTitle: String = "Try Again"
    var retry: (() -> Void)? = nil

    var body: some View {
        ERCard(tone: .active) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(.erCardTitle)
                    .foregroundStyle(ER.charcoal)
                Text(message)
                    .font(.erBody)
                    .foregroundStyle(ER.charcoal.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button(retryTitle, action: retry)
                        .buttonStyle(GhostButtonStyle())
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Form fields

struct ERField<Content: View>: View {
    var label: String
    var hint: String? = nil
    var dark: Bool = false
    @ViewBuilder var content: Content

    init(_ label: String, hint: String? = nil, dark: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.hint = hint
        self.dark = dark
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ERSectionHeader(text: label, dark: dark)
            content
            if let hint {
                ERNote(text: hint, dark: dark)
            }
        }
    }
}

struct ERTextField: View {
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var dark: Bool = false

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(dark ? ER.cream.opacity(0.4) : ER.charcoal.opacity(0.35)))
            .font(.erBody)
            .foregroundStyle(dark ? ER.cream : ER.charcoal)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.sentences)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background { BeveledRect(radius: 10, cap: 12).fill(dark ? ER.darkCard : ER.card) }
            .overlay { BeveledRect(radius: 10, cap: 12).stroke(dark ? ER.orange : ER.charcoal, lineWidth: 2) }
    }
}

struct ERTextEditor: View {
    var placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 96

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.erBody)
                .foregroundStyle(ER.charcoal)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(minHeight: minHeight)
            if text.isEmpty {
                Text(placeholder)
                    .font(.erBody)
                    .foregroundStyle(ER.charcoal.opacity(0.35))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
        .background { BeveledRect(radius: 10, cap: 14).fill(ER.card) }
        .overlay { BeveledRect(radius: 10, cap: 14).stroke(ER.charcoal, lineWidth: 2) }
    }
}

struct ERTimeField: View {
    @Binding var minutes: Int
    var dark: Bool = false

    private var binding: Binding<Date> {
        Binding(
            get: { ERTime.date(fromMinutes: minutes) },
            set: { minutes = ERTime.minutes(from: $0) }
        )
    }

    var body: some View {
        DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.compact)
            .tint(ER.scarlet)
            .environment(\.colorScheme, dark ? .dark : .light)
    }
}

struct ERToggleRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var dark: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.erBodyBold)
                    .foregroundStyle(dark ? ER.cream : ER.charcoal)
                if let subtitle {
                    Text(subtitle)
                        .font(.erCaption)
                        .foregroundStyle(dark ? ER.cream.opacity(0.7) : ER.charcoal.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ER.scarlet)
        }
    }
}

/// A stepper built from the app's own parts.
struct ERStepperRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 5
    var suffix: String = "min"

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.erBodyBold)
                .foregroundStyle(ER.charcoal)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                ERIconButton(systemName: "minus") {
                    value = max(range.lowerBound, value - step)
                }
                Text("\(value) \(suffix)")
                    .font(.erHours)
                    .foregroundStyle(ER.charcoal)
                    .frame(minWidth: 74)
                ERIconButton(systemName: "plus") {
                    value = min(range.upperBound, value + step)
                }
            }
        }
    }
}

// MARK: - Navigation bar

struct ERNavBar: View {
    var title: String
    var dark: Bool = false
    var onBack: (() -> Void)? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let onBack {
                ERIconButton(systemName: "chevron.left", dark: dark, action: onBack)
            }
            Text(title.uppercased())
                .font(.erScreenTitleSmall)
                .tracking(-0.5)
                .foregroundStyle(.fire)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            if let trailing { trailing }
        }
    }
}

// MARK: - Screen scaffold

struct ERScreen<Content: View>: View {
    var dark: Bool = false
    var sparkSeed: Int = 3
    @ViewBuilder var content: Content

    init(dark: Bool = false, sparkSeed: Int = 3, @ViewBuilder content: () -> Content) {
        self.dark = dark
        self.sparkSeed = sparkSeed
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            (dark ? ER.cherry : ER.cream).ignoresSafeArea()
            // Only the strip behind the status bar, where no text of ours ever goes.
            SparkField(seed: sparkSeed, count: 4, bright: dark)
                .frame(height: 44)
                .padding(.horizontal, 10)
                .offset(y: -46)
                .ignoresSafeArea(edges: .top)
            content
        }
    }
}

// MARK: - Row helpers

struct ERKeyValueRow: View {
    var key: String
    var value: String
    var dark: Bool = false
    var mono: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.erBody)
                .foregroundStyle(dark ? ER.cream.opacity(0.8) : ER.charcoal.opacity(0.75))
            Spacer(minLength: 6)
            Text(value)
                .font(mono ? .erHours : .erBodyBold)
                .foregroundStyle(dark ? ER.cream : ER.charcoal)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A tappable list row that keeps the card language.
struct ERNavRow: View {
    var title: String
    var detail: String? = nil
    var index: Int = 0
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ERCard(index: index) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.erBodyBold)
                            .foregroundStyle(ER.charcoal)
                        if let detail {
                            Text(detail)
                                .font(.erCaption)
                                .foregroundStyle(ER.charcoal.opacity(0.65))
                                .multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(ER.scarlet)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
