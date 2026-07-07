/// An error produced while resolving subfile references into a ``ResolvedLDrawModel``.
///
/// Distinct from ``LDrawParseError`` since resolution is a separate concern (a graph
/// walk requiring I/O via ``LDrawPartResolver``) from parsing raw statement text.
public enum LDrawResolutionError: Error, Sendable {
    /// Only surfaces when the resolver's `missingPartPolicy` is `.fail`.
    case partNotFound(reference: String)
    /// Wraps a failure description from a resolver implementation's own I/O layer.
    case underlying(String)
    /// A part transitively references itself; `chain` lists the reference names
    /// involved, in resolution order.
    case circularReference(chain: [String])
    case parseErrorInResolvedPart(reference: String, error: LDrawParseError)
}
