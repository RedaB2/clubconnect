import SwiftUI

/// App surfaces stay neutral outside a club. A club adds a light primary wash to its
/// canvas and a stronger secondary wash to supporting elements such as event dates.
struct BrandTheme {
    let canvas: Color
    let surface: Color
    let ink: Color
    let accent: Color
    let wash: Color

    static let application = BrandTheme(club: nil)

    init(club: Club?) {
        let primary = RGB(hex: club?.accentHex) ?? .appAccent
        let secondary = RGB(hex: club?.effectiveSecondaryHex) ?? .appWash
        let custom = club != nil && (primary != .appAccent || secondary != .appWash)

        let lightCanvas = custom ? RGB.appCanvas.mixed(with: primary, by: 0.055) : .appCanvas
        let darkCanvas = custom ? RGB.darkCanvas.mixed(with: primary, by: 0.08) : .darkCanvas
        let lightSurface = custom ? RGB.white.mixed(with: secondary, by: 0.025) : .white
        let darkSurface = custom ? RGB.darkSurface.mixed(with: secondary, by: 0.045) : .darkSurface
        let lightWash = custom ? RGB.appWash.mixed(with: secondary, by: 0.23) : .appWash
        let darkWash = custom ? RGB.darkWash.mixed(with: secondary, by: 0.17) : .darkWash

        canvas = Self.adaptive(lightCanvas, darkCanvas)
        surface = Self.adaptive(lightSurface, darkSurface)
        wash = Self.adaptive(lightWash, darkWash)
        let lightBackgrounds = [lightCanvas, lightSurface, lightWash]
        let darkBackgrounds = [darkCanvas, darkSurface, darkWash]
        ink = Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let base = dark ? RGB.darkInk : .appInk
            guard traits.accessibilityContrast == .high else { return base.uiColor }
            let values = (dark ? darkBackgrounds : lightBackgrounds).map(\.luminance)
            let limiting = dark ? (values.max() ?? 0) : (values.min() ?? 1)
            return base.readable(against: limiting, dark: dark, highContrast: true).uiColor
        })
        accent = Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let backgrounds = dark ? darkBackgrounds : lightBackgrounds
            // A scoped tint also appears on native elevated/grouped surfaces and on iPad sidebars.
            let system = [UIColor.systemBackground, .secondarySystemGroupedBackground, .tertiarySystemGroupedBackground]
                .compactMap { RGB($0.resolvedColor(with: traits)) }
            let luminances = (backgrounds + system).map(\.luminance)
            let limiting = dark ? (luminances.max() ?? 0) : (luminances.min() ?? 1)
            let base = dark && !custom ? RGB.darkAccent : primary
            return base.readable(against: limiting, dark: dark, highContrast: traits.accessibilityContrast == .high).uiColor
        })
    }

    /// Use for a label on an opaque solid fill. Adaptive accent fills also satisfy
    /// Increase Contrast. Native controls can keep their own semantic label treatment.
    static func label(on fill: Color) -> Color {
        Color(uiColor: UIColor { traits in
            let color = UIColor(fill).resolvedColor(with: traits)
            guard let rgb = RGB(color) else { return .label }
            // Black and white have equal contrast at this relative luminance.
            return rgb.luminance >= 0.1791287847 ? .black : .white
        })
    }

    private static func adaptive(_ light: RGB, _ dark: RGB) -> Color {
        Color(uiColor: UIColor { traits in (traits.userInterfaceStyle == .dark ? dark : light).uiColor })
    }
}

extension Club {
    var effectiveSecondaryHex: String { secondaryHex ?? (id == "menasa" ? "#31675D" : Self.defaultSecondaryHex) }
    var brandColor: Color { Color(uiColor: (RGB(hex: accentHex) ?? .appAccent).uiColor) }
    var secondaryBrandColor: Color { Color(uiColor: (RGB(hex: effectiveSecondaryHex) ?? .appWash).uiColor) }
    var accent: Color { BrandTheme(club: self).accent }
}

private struct BrandThemeKey: EnvironmentKey {
    static let defaultValue = BrandTheme.application
}

extension EnvironmentValues {
    var brandTheme: BrandTheme {
        get { self[BrandThemeKey.self] }
        set { self[BrandThemeKey.self] = newValue }
    }
}

extension View {
    /// Apply at a navigation or presentation boundary. The tab bar and native
    /// materials continue to use the system's appearance and scroll-edge behaviors.
    func brandScope(_ club: Club? = nil) -> some View {
        let theme = club.map { BrandTheme(club: $0) } ?? .application
        return environment(\.brandTheme, theme)
            .tint(theme.accent)
            .background(theme.canvas.ignoresSafeArea())
    }

    func brandListBackground() -> some View { modifier(BrandListBackground()) }
}

private struct BrandListBackground: ViewModifier {
    @Environment(\.brandTheme) private var theme

    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background(theme.canvas)
    }
}

private struct RGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    static let appCanvas = RGB(0xFBF8F4)
    static let appInk = RGB(0x291D19)
    static let appAccent = RGB(0x80523F)
    static let appWash = RGB(0xF0E4D9)
    static let darkCanvas = RGB(0x191513)
    static let darkSurface = RGB(0x261F1B)
    static let darkInk = RGB(0xF6EFE9)
    static let darkAccent = RGB(0xE4B59B)
    static let darkWash = RGB(0x3A2F29)
    static let white = RGB(0xFFFFFF)
    static let black = RGB(0)

    init?(hex: String?) {
        guard let hex else { return nil }
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : hex[...]
        guard digits.utf8.count == 6, digits.allSatisfy(\.isHexDigit),
              let value = Int(digits, radix: 16) else { return nil }
        self.init(value)
    }

    init?(_ color: UIColor) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        self.init(red: red, green: green, blue: blue)
    }

    init(_ value: Int) {
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }

    var luminance: Double {
        func linear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func mixed(with other: RGB, by fraction: Double) -> RGB {
        RGB(red: red + (other.red - red) * fraction,
            green: green + (other.green - green) * fraction,
            blue: blue + (other.blue - blue) * fraction)
    }

    func readable(against background: Double, dark: Bool, highContrast: Bool) -> RGB {
        let minimum = highContrast ? 7.0 : 4.5
        func passes(_ color: RGB) -> Bool {
            let foreground = color.luminance
            // Choose the same side of every possible surface, including pure white/black.
            return dark ? (foreground + 0.05) / (background + 0.05) >= minimum
                        : (background + 0.05) / (foreground + 0.05) >= minimum
        }
        guard !passes(self) else { return self }
        let end = dark ? RGB.white : RGB.black
        var low = 0.0, high = 1.0
        for _ in 0..<14 {
            let middle = (low + high) / 2
            if passes(mixed(with: end, by: middle)) { high = middle } else { low = middle }
        }
        return mixed(with: end, by: high)
    }
}
