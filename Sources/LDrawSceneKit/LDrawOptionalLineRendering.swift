/// How to render LDraw's type-5 optional/conditional lines.
///
/// True view-dependent conditional visibility (shown only when the two control
/// points fall on the same side of the viewer's projection) isn't implemented in v1;
/// see the type-level documentation on ``LDrawSceneBuilder`` for rationale.
public enum LDrawOptionalLineRenderingMode: Sendable, Equatable {
    case omit
    case hiddenByDefault
    case alwaysShown
}
