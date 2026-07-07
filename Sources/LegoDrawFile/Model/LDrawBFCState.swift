/// The back-face culling (BFC) state in effect at a point in an LDraw file, as
/// established by `0 BFC` meta-commands.
public struct LDrawBFCState: Sendable, Equatable {
    /// `nil` until a `CERTIFY`/`NOCERTIFY` directive has been seen.
    public var isCertified: Bool?
    /// The declared winding order for front faces. `true` is the LDraw default (CCW).
    public var windingIsCCW: Bool
    /// Whether back-face clipping (culling) is enabled.
    public var isClipEnabled: Bool
    /// Set by `INVERTNEXT`; consumed by the immediately-following statement, then reset.
    public var invertNext: Bool

    public init(
        isCertified: Bool? = nil,
        windingIsCCW: Bool = true,
        isClipEnabled: Bool = true,
        invertNext: Bool = false
    ) {
        self.isCertified = isCertified
        self.windingIsCCW = windingIsCCW
        self.isClipEnabled = isClipEnabled
        self.invertNext = invertNext
    }

    /// Applies a sequence of directives parsed from a single `0 BFC ...` line, in order.
    public mutating func apply(_ directives: [LDrawBFCDirective]) {
        for directive in directives {
            switch directive {
            case .certify:
                isCertified = true
            case .noCertify:
                isCertified = false
            case .cw:
                windingIsCCW = false
            case .ccw:
                windingIsCCW = true
            case .clip:
                isClipEnabled = true
            case .noClip:
                isClipEnabled = false
            case .invertNext:
                invertNext = true
            }
        }
    }
}

/// A single token from a `0 BFC ...` statement. A line may carry several of these
/// in sequence (e.g. `0 BFC CCW CLIP`), applied left to right via ``LDrawBFCState/apply(_:)``.
public enum LDrawBFCDirective: Sendable, Equatable {
    case certify
    case noCertify
    case cw
    case ccw
    case clip
    case noClip
    case invertNext
}
