import SwiftUI
import AppKit
import CoreText

// Looped brand (brand.looped.sh) for the native Settings window: tokens,
// type, and the handful of controls the brand specifies differently from
// AppKit's defaults. Day / Night follow the system appearance.

// MARK: - Colour tokens

enum Looped {
    static let paper      = dynamic(0xFBFBF9, 0x0F1013)   // background
    static let raised     = dynamic(0xFFFFFF, 0x191A1E)   // menus, popovers
    static let shade      = dynamic(0xF0F0EC, 0x24252B)   // hover, selection ground
    static let ink        = dynamic(0x17181B, 0xE6E3DC)
    static let ink2       = dynamic(0x5B5F66, 0xA5A29A)   // supporting text
    static let ink3       = dynamic(0x70757C, 0x9A978F)   // muted metadata
    static let rule       = dynamic(0xE3E3DE, 0x2C2D32)
    static let ruleStrong = dynamic(0xC9C9C2, 0x54555D)

    static let accent     = dynamic(0x6554C0, 0xB4A3ED)   // text, selection, focus
    static let accentDark = dynamic(0x443786, 0x493494)   // primary button's lower edge
    static let accentWash = dynamic(0xEEEBF7, 0x2A243B)   // quiet selection ground
    static let accentFill = dynamic(0x6554C0, 0x7358D6)   // primary button fill
    static let accentText = Color.white

    static let moss    = dynamic(0x4B7A3F, 0x8FB877)      // success
    static let ochre   = dynamic(0x9A6B12, 0xD8AB52)      // warning, review
    static let indigo  = dynamic(0x3D5BA9, 0x93A8E4)      // info
    static let oxblood = dynamic(0xA8322C, 0xE8776E)      // error, removal

    static let radius: CGFloat = 3
    static let gutter: CGFloat = 28
    static let railHeight: CGFloat = 52     // the app header, --topbar-h
    static let footHeight: CGFloat = 52     // the sidebar's foot and a page's foot

    private static func dynamic(_ day: UInt32, _ night: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? night : day)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Type

/// Work Sans for everything people read, Space Mono for short metadata,
/// labels and paths. Both ship in Resources/Fonts; when they're missing
/// (`swift build`, tests) the system fonts stand in.
enum LoopedType {
    static let registered: Void = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        if !urls.isEmpty {
            CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
        }
    }()

    /// Work Sans is a variable font, so the weight is set on its `wght` axis
    /// rather than picked from named faces.
    static func sans(_ size: CGFloat, weight: CGFloat = 400) -> Font {
        _ = registered
        let wght = NSNumber(value: 0x7767_6874)   // 'wght'
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: "Work Sans",
            .variation: [wght: weight],
        ])
        if let font = NSFont(descriptor: descriptor, size: size), font.familyName == "Work Sans" {
            return Font(font)
        }
        return .system(size: size, weight: systemWeight(weight))
    }

    static func mono(_ size: CGFloat, bold: Bool = false) -> Font {
        _ = registered
        if let font = NSFont(name: bold ? "SpaceMono-Bold" : "SpaceMono-Regular", size: size) {
            return Font(font)
        }
        return .system(size: size, weight: bold ? .bold : .regular, design: .monospaced)
    }

    private static func systemWeight(_ w: CGFloat) -> Font.Weight {
        switch w {
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        default:     return .bold
        }
    }
}

extension Font {
    static func sans(_ size: CGFloat, weight: CGFloat = 400) -> Font { LoopedType.sans(size, weight: weight) }
    static func mono(_ size: CGFloat, bold: Bool = false) -> Font { LoopedType.mono(size, bold: bold) }
}

extension View {
    /// Supporting copy under a setting.
    func lpCaption() -> some View {
        font(.sans(12)).foregroundStyle(Looped.ink2)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Small uppercase Space Mono label: section heads and field labels.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.mono(10)).tracking(0.8)
            .foregroundStyle(Looped.ink3)
    }
}

/// The fine 1px separator the brand uses instead of boxing regions in cards.
struct Rule: View {
    var strong = false
    var body: some View {
        Rectangle().fill(strong ? Looped.ruleStrong : Looped.rule).frame(height: 1)
    }
}

// MARK: - Buttons

/// Primary is the tactile filled button (one per view); secondary is quiet
/// and bordered; destructive is the only semantic variant.
struct LoopedButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, kind: kind, compact: compact)
    }

    private struct Styled: View {
        let configuration: Configuration
        let kind: Kind
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        private var pressed: Bool { configuration.isPressed && isEnabled }
        private var travel: CGFloat { kind == .primary && pressed && !reduceMotion ? 1 : 0 }
        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Looped.radius) }

        var body: some View {
            configuration.label
                .font(.sans(compact ? 12 : 13, weight: 500))
                .lineLimit(1)
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, compact ? 4 : 6)
                .foregroundStyle(foreground)
                .background(shape.fill(fill))
                .overlay(shape.strokeBorder(border, lineWidth: kind == .primary ? 0 : 1))
                .background(
                    // Hard lower edge; it shrinks as the face travels down.
                    shape.fill(Looped.accentDark)
                        .offset(y: 2 - travel)
                        .opacity(kind == .primary && isEnabled ? 1 : 0)
                )
                .offset(y: travel)
                .padding(.bottom, kind == .primary ? 2 : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var foreground: Color {
            switch kind {
            case .primary:     return Looped.accentText
            case .secondary:   return Looped.ink
            case .destructive: return Looped.oxblood
            }
        }

        private var fill: Color {
            switch kind {
            case .primary: return Looped.accentFill
            default:       return hovering && isEnabled ? Looped.shade : .clear
            }
        }

        private var border: Color {
            switch kind {
            case .primary:     return .clear
            case .secondary:   return Looped.ruleStrong
            case .destructive: return Looped.oxblood.opacity(0.55)
            }
        }
    }
}

/// Quiet underlined text action.
struct LoopedLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }
    private struct Styled: View {
        let configuration: Configuration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.sans(12))
                .underline()
                .foregroundStyle(hovering ? Looped.ink : Looped.ink2)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Square icon-only button with a flat shade hover.
struct LoopedIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }
    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            let destructive = configuration.role == .destructive
            configuration.label
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(hovering && isEnabled
                                 ? (destructive ? Looped.oxblood : Looped.ink) : Looped.ink2)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: Looped.radius)
                    .fill(hovering && isEnabled ? Looped.shade : .clear))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == LoopedButtonStyle {
    static var primary: LoopedButtonStyle { LoopedButtonStyle(kind: .primary) }
    static var secondary: LoopedButtonStyle { LoopedButtonStyle(kind: .secondary) }
    static var primaryCompact: LoopedButtonStyle { LoopedButtonStyle(kind: .primary, compact: true) }
    static var secondaryCompact: LoopedButtonStyle { LoopedButtonStyle(kind: .secondary, compact: true) }
    static var destructiveCompact: LoopedButtonStyle { LoopedButtonStyle(kind: .destructive, compact: true) }
}
extension ButtonStyle where Self == LoopedLinkStyle {
    static var quietLink: LoopedLinkStyle { LoopedLinkStyle() }
}
extension ButtonStyle where Self == LoopedIconButtonStyle {
    static var icon: LoopedIconButtonStyle { LoopedIconButtonStyle() }
}

// MARK: - Toggles

/// The brand switch: square-ish (2px), neutral in both states. On is told by
/// an ink thumb and a stronger border, never a primary fill.
struct LoopedSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }
    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let on = configuration.isOn
            ZStack(alignment: on ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: 2).fill(on ? Looped.shade : Looped.raised)
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(on ? Looped.ink2 : Looped.ruleStrong, lineWidth: 1)
                RoundedRectangle(cornerRadius: 1)
                    .fill(on ? Looped.ink : Looped.ruleStrong)
                    .frame(width: 12, height: 12)
                    .padding(3)
            }
            .frame(width: 34, height: 18)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isEnabled else { return }
                withAnimation(.easeOut(duration: 0.12)) { configuration.isOn.toggle() }
            }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        }
    }
}

/// A switch whose title is shown elsewhere in the row (but still read out).
struct LoopedSwitch: View {
    let label: String
    @Binding var isOn: Bool
    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        self._isOn = isOn
    }
    var body: some View {
        Toggle(label, isOn: $isOn).labelsHidden().toggleStyle(LoopedSwitchStyle())
    }
}

/// Checkbox with a visible label; checked is an ink box, not a primary one.
struct LoopedCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }
    private struct Styled: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let on = configuration.isOn
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(on ? Looped.ink : Looped.raised)
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(on ? Looped.ink : Looped.ruleStrong, lineWidth: 1))
                    .overlay {
                        if on {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Looped.paper)
                        }
                    }
                    .frame(width: 14, height: 14)
                configuration.label
                    .font(.sans(13)).foregroundStyle(Looped.ink)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        }
    }
}

extension ToggleStyle where Self == LoopedCheckboxStyle {
    static var loopedCheckbox: LoopedCheckboxStyle { LoopedCheckboxStyle() }
}

// MARK: - Choosers

/// Compact, borderless switcher with radio semantics and a neutral selected
/// surface. For two or three short choices.
struct LoopedSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Segment(label: options[i].label,
                        selected: options[i].value == selection) {
                    selection = options[i].value
                }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Looped.radius).strokeBorder(Looped.rule))
        .opacity(isEnabled ? 1 : 0.45)
    }

    private struct Segment: View {
        let label: String
        let selected: Bool
        let action: () -> Void
        @State private var hovering = false
        var body: some View {
            Button(action: action) {
                Text(label)
                    .font(.sans(12, weight: selected ? 500 : 400))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Looped.ink : Looped.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5).padding(.horizontal, 10)
                    .background(RoundedRectangle(cornerRadius: 2)
                        .fill(selected || hovering ? Looped.shade : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(selected ? Looped.ruleStrong : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// Full-width bordered radio rows: shade when selected, ink indicator.
struct LoopedRadioGroup<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                Row(label: options[i].label, selected: options[i].value == selection) {
                    selection = options[i].value
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private struct Row: View {
        let label: String
        let selected: Bool
        let action: () -> Void
        @State private var hovering = false
        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    Circle()
                        .strokeBorder(selected ? Looped.ink : Looped.ruleStrong, lineWidth: 1)
                        .overlay { if selected { Circle().fill(Looped.ink).padding(3.5) } }
                        .frame(width: 14, height: 14)
                    Text(label).font(.sans(13, weight: selected ? 500 : 400))
                        .foregroundStyle(Looped.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: Looped.radius)
                    .fill(selected || hovering ? Looped.shade : .clear))
                .overlay(RoundedRectangle(cornerRadius: Looped.radius)
                    .strokeBorder(selected ? Looped.ruleStrong : Looped.rule))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

/// Field-styled chrome shared by text inputs and the select button.
private struct FieldChrome: ViewModifier {
    var focused = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Looped.radius).fill(Looped.paper))
            .overlay(RoundedRectangle(cornerRadius: Looped.radius)
                .strokeBorder(focused ? Looped.accent : Looped.ruleStrong,
                              lineWidth: focused ? 2 : 1))
    }
}

/// A dropdown on raised paper. Single choice; the current value carries an
/// accent wash and a checkmark.
struct LoopedSelect<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var placeholder = "Choose…"
    @State private var open = false
    @Environment(\.isEnabled) private var isEnabled

    private var current: String {
        options.first { $0.value == selection }?.label ?? placeholder
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Text(current).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Looped.ink3)
            }
            .font(.sans(12)).foregroundStyle(Looped.ink)
            .modifier(FieldChrome(focused: open))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(options.indices, id: \.self) { i in
                        OptionRow(label: options[i].label,
                                  selected: options[i].value == selection) {
                            selection = options[i].value
                            open = false
                        }
                    }
                }
                .padding(4)
            }
            .frame(minWidth: 200, maxHeight: 320)
            .fixedSize(horizontal: false, vertical: true)
            .background(Looped.raised)
        }
        .accessibilityValue(current)
    }
}

struct OptionRow: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(selected ? 1 : 0)
                Text(label).font(.sans(13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Looped.accent : Looped.ink)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 2)
                .fill(selected ? Looped.accentWash : hovering ? Looped.shade : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A field-styled button that opens a custom popover (multi-select etc.).
struct LoopedFieldButton: View {
    let text: String
    @Binding var isOpen: Bool
    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                Text(text).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Looped.ink3)
            }
            .font(.sans(12)).foregroundStyle(Looped.ink)
            .modifier(FieldChrome(focused: isOpen))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inputs

/// Transparent paper field, rule border, 12px content, 2px accent focus.
struct LoopedField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var mono = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: prompt)
            } else {
                TextField("", text: $text, prompt: prompt)
            }
        }
        .textFieldStyle(.plain)
        .focusEffectDisabled()
        .focused($focused)
        .onSubmit(onSubmit)
        .font(mono ? .mono(12) : .sans(12))
        .foregroundStyle(Looped.ink)
        .modifier(FieldChrome(focused: focused))
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(placeholder)
    }

    private var prompt: Text {
        Text(placeholder).foregroundStyle(Looped.ink3)
    }
}

// MARK: - Status

/// Flat 9px progress track in shade, square ends.
struct LoopedProgress: View {
    var value: Double
    var total: Double = 1
    var height: CGFloat = 9
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Looped.shade)
                Rectangle().fill(Looped.ink)
                    .frame(width: geo.size.width * max(0, min(1, value / max(total, .ulpOfOne))))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((value / max(total, .ulpOfOne)) * 100)) percent")
    }
}

/// Outlined pill badge. Colour is always paired with its label.
struct LoopedBadge: View {
    let text: String
    var tint: Color = Looped.ink2
    init(_ text: String, tint: Color = Looped.ink2) {
        self.text = text
        self.tint = tint
    }
    var body: some View {
        Text(text.uppercased())
            .font(.mono(9)).tracking(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
            .fixedSize()
    }
}

/// Shade ground, square corners, a 2px semantic rule on the left.
struct LoopedAlert<Extra: View>: View {
    enum Tone { case info, success, warning, error }
    let tone: Tone
    let title: String
    var message: String? = nil
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.sans(13, weight: 500)).foregroundStyle(Looped.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let message { Text(message).lpCaption() }
                extra()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Looped.shade)
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 2) }
    }

    private var color: Color {
        switch tone {
        case .info:    return Looped.indigo
        case .success: return Looped.moss
        case .warning: return Looped.ochre
        case .error:   return Looped.oxblood
        }
    }
    private var symbol: String {
        switch tone {
        case .info:    return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error:   return "xmark.octagon"
        }
    }
}

extension LoopedAlert where Extra == EmptyView {
    init(tone: Tone, title: String, message: String? = nil) {
        self.init(tone: tone, title: title, message: message) { EmptyView() }
    }
}

/// Small uppercase mono label over a light, large value.
struct LoopedStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(label)
            Text(value).font(.sans(28, weight: 300)).foregroundStyle(Looped.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings layout

/// A titled group of settings, separated from the next by space, not a box.
struct SettingSection<Content: View>: View {
    let title: String?
    @ViewBuilder var content: () -> Content
    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                // A Work Sans heading, so it reads above the mono field labels.
                Text(title)
                    .font(.sans(15, weight: 500)).tracking(-0.2)
                    .foregroundStyle(Looped.ink)
                    .padding(.bottom, 8)
                Rule()
            }
            content()
        }
        .padding(.top, 22)
    }
}

/// Title and caption on the left, the control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var control: () -> Control
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, caption: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.sans(13)).foregroundStyle(Looped.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption { Text(caption).lpCaption() }
            }
            .opacity(isEnabled ? 1 : 0.55)
            Spacer(minLength: 0)
            control()
        }
        .padding(.vertical, 12)
    }
}

/// A mono label over a full-width control, with an optional caption below.
struct SettingField<Control: View>: View {
    let label: String
    var caption: String? = nil
    @ViewBuilder var control: () -> Control
    @Environment(\.isEnabled) private var isEnabled

    init(_ label: String, caption: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.caption = caption
        self.control = control
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Eyebrow(label)
            control()
            if let caption { Text(caption).lpCaption().opacity(isEnabled ? 1 : 0.55) }
        }
        .padding(.vertical, 12)
    }
}

/// A file location with its actions — the app's on-disk sources of truth.
struct PathRow<Actions: View>: View {
    let icon: String
    let path: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .light))
                .foregroundStyle(Looped.ink3)
            Text(path)
                .font(.mono(11)).foregroundStyle(Looped.ink2)
                .lineLimit(1).truncationMode(.middle)
                .help(path)
            Spacer(minLength: 8)
            actions()
        }
        .padding(.vertical, 10)
    }
}

/// Scrolling page body with the standard gutter.
struct PaneScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Looped.gutter)
                .padding(.bottom, 24)
        }
        .scrollIndicators(.automatic)
    }
}

/// Empty states are a heading and a line of text — no icons or illustrations.
struct EmptyState: View {
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.sans(14, weight: 500)).foregroundStyle(Looped.ink)
            Text(message).lpCaption()
        }
        .padding(.vertical, 18)
    }
}
