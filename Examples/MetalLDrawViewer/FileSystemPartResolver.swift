import Foundation
import LegoDrawFile

struct FileSystemPartResolver: LDrawPartResolver {
    var searchDirectories: [URL]

    func resolve(reference: String) throws(LDrawResolutionError) -> LDrawSourceFile? {
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
