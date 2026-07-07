import Foundation
import LegoDrawFile

/// Resolves subfile references by searching a list of directories on disk — the
/// standard LDraw parts library layout (`parts/`, `parts/s/`, `p/`, `p/48/`, `models/`)
/// plus the directory the input file itself lives in, for local sibling parts.
struct FileSystemPartResolver: LDrawPartResolver {
    var searchDirectories: [URL]

    func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile? {
        // LDraw files historically write subfile paths with Windows-style backslashes
        // (e.g. `s\3001s01.dat` for a stud primitive); normalize to forward slashes
        // so `appendingPathComponent` treats them as real subdirectories on POSIX systems.
        let normalizedReference = reference.replacingOccurrences(of: "\\", with: "/")

        for directory in searchDirectories {
            for candidateName in [normalizedReference, normalizedReference.lowercased()] {
                let candidateURL = directory.appendingPathComponent(candidateName)
                guard FileManager.default.fileExists(atPath: candidateURL.path) else { continue }

                let text: String
                do {
                    text = try String(contentsOf: candidateURL, encoding: .utf8)
                } catch {
                    throw LDrawResolutionError.underlying("\(error)")
                }

                do {
                    return try LDrawParser.parseFile(text)
                } catch {
                    throw LDrawResolutionError.parseErrorInResolvedPart(reference: reference, error: error)
                }
            }
        }
        return nil
    }
}
