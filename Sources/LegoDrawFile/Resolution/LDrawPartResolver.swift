/// Resolves a subfile reference's file name (e.g. `"3001.dat"`) to its parsed contents.
///
/// Kept as a caller-supplied protocol so `LegoDrawFile`'s core parsing/model layer
/// never performs file I/O itself. Implementations typically read from a local parts
/// library directory, an app bundle, or a network cache.
public protocol LDrawPartResolver: Sendable {
    /// Resolves `reference` to its parsed file, or `nil` if no such part exists
    /// (a normal, expected outcome the caller handles via `MissingPartPolicy`).
    /// Throw only for genuine I/O failures.
    func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile?
}
