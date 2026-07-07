/// Walks a parsed ``LDrawSourceFile``/``LDrawMultiPartDocument`` and, using a supplied
/// ``LDrawPartResolver``, resolves every subfile reference into a fully-linked
/// ``ResolvedLDrawModel`` tree.
public struct LDrawModelResolver: Sendable {

    public enum MissingPartPolicy: Sendable {
        /// Silently drop subfile references that can't be resolved.
        case omit
        /// Keep a `Node.missingSubfile` placeholder for unresolved references.
        case placeholder
        /// Throw `LDrawResolutionError.partNotFound`.
        case fail
    }

    private let resolver: any LDrawPartResolver
    private let missingPartPolicy: MissingPartPolicy

    public init(resolver: any LDrawPartResolver, missingPartPolicy: MissingPartPolicy = .omit) {
        self.resolver = resolver
        self.missingPartPolicy = missingPartPolicy
    }

    public func resolve(_ file: LDrawSourceFile) throws(LDrawResolutionError) -> ResolvedLDrawModel {
        var inProgress: Set<String> = []
        return try resolveFile(file, embeddedFiles: [:], inProgress: &inProgress)
    }

    /// Resolves an MPD's main file, checking `document.embeddedFiles` before falling
    /// back to the injected resolver for any given reference (so sibling submodels
    /// embedded in the same MPD never require external I/O, while references to
    /// standard library parts like `3001.dat` still do).
    public func resolve(_ document: LDrawMultiPartDocument) throws(LDrawResolutionError) -> ResolvedLDrawModel {
        var inProgress: Set<String> = []
        return try resolveFile(document.mainFile, embeddedFiles: document.embeddedFiles, inProgress: &inProgress)
    }

    private func resolveFile(
        _ file: LDrawSourceFile,
        embeddedFiles: [String: LDrawSourceFile],
        inProgress: inout Set<String>
    ) throws(LDrawResolutionError) -> ResolvedLDrawModel {
        var bfcState = LDrawBFCState()
        var children: [ResolvedLDrawModel.Node] = []

        for statement in file.statements {
            switch statement {
            case .meta(.bfc(let directives)):
                bfcState.apply(directives)
            case .meta:
                break
            case .subfileReference(let reference):
                let invertFromBFC = bfcState.invertNext
                bfcState.invertNext = false
                if let node = try resolveSubfileReference(
                    reference, embeddedFiles: embeddedFiles, invertFromBFC: invertFromBFC, inProgress: &inProgress
                ) {
                    children.append(node)
                }
            case .line(let line):
                bfcState.invertNext = false
                children.append(.line(line))
            case .triangle(let triangle):
                bfcState.invertNext = false
                children.append(.triangle(triangle))
            case .quadrilateral(let quadrilateral):
                bfcState.invertNext = false
                children.append(.quadrilateral(quadrilateral))
            case .optionalLine(let optionalLine):
                bfcState.invertNext = false
                children.append(.optionalLine(optionalLine))
            }
        }

        return ResolvedLDrawModel(name: file.name, bfcState: bfcState, children: children)
    }

    private func resolveSubfileReference(
        _ reference: LDrawSubfileReference,
        embeddedFiles: [String: LDrawSourceFile],
        invertFromBFC: Bool,
        inProgress: inout Set<String>
    ) throws(LDrawResolutionError) -> ResolvedLDrawModel.Node? {
        let key = LDrawMultiPartDocument.normalizedName(reference.fileName)

        if inProgress.contains(key) {
            throw LDrawResolutionError.circularReference(chain: Array(inProgress) + [key])
        }

        let childFile: LDrawSourceFile?
        if let embedded = embeddedFiles[key] {
            childFile = embedded
        } else {
            childFile = try resolver.resolve(reference: reference.fileName)
        }

        guard let childFile else {
            switch missingPartPolicy {
            case .omit:
                return nil
            case .placeholder:
                return .missingSubfile(transform: reference.transform, color: reference.color, fileName: reference.fileName)
            case .fail:
                throw LDrawResolutionError.partNotFound(reference: reference.fileName)
            }
        }

        inProgress.insert(key)
        let childModel = try resolveFile(childFile, embeddedFiles: embeddedFiles, inProgress: &inProgress)
        inProgress.remove(key)

        let invertWinding = invertFromBFC != (reference.transform.determinant < 0)
        return .subfile(transform: reference.transform, color: reference.color, invertWinding: invertWinding, model: childModel)
    }
}
