import SwiftUI

// MARK: - Xomify Brand Typography
//
// All app-facing type uses the rounded system design so screens feel
// modern and friendly — closer to Apple Music / Spotify than the default
// SF blocks. Heights track the same sizes as `.title`, `.headline`,
// `.body`, etc. so Dynamic Type still scales.

extension Font {
    static let xomifyLargeTitle = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let xomifyTitle      = Font.system(.title,      design: .rounded).weight(.bold)
    static let xomifyTitle2     = Font.system(.title2,     design: .rounded).weight(.bold)
    static let xomifyTitle3     = Font.system(.title3,     design: .rounded).weight(.semibold)
    static let xomifyHeadline   = Font.system(.headline,   design: .rounded).weight(.semibold)
    static let xomifySubheadline = Font.system(.subheadline, design: .rounded).weight(.medium)
    static let xomifyBody       = Font.system(.body,       design: .rounded)
    static let xomifyCallout    = Font.system(.callout,    design: .rounded)
    static let xomifyFootnote   = Font.system(.footnote,   design: .rounded)
    static let xomifyCaption    = Font.system(.caption,    design: .rounded).weight(.medium)
    static let xomifyCaption2   = Font.system(.caption2,   design: .rounded).weight(.semibold)
}
