/// The surface finish declared by a `0 !COLOUR` meta-command, as used to approximate
/// material appearance when rendering.
public enum LDrawColorFinish: Sendable, Equatable, Hashable {
    case solid
    case transparent
    case chrome
    case pearlescent
    case rubber
    case matteMetallic
    case metal
    /// `MATERIAL <params>` finishes (e.g. GLITTER, SPECKLE) with the parameter
    /// tail preserved verbatim rather than fully parsed.
    case material(raw: String)
}
