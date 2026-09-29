import Foundation

public enum CharacterPackageError: Error, Equatable {
    case fileNotFound(String)
    case malformedJSON(String)
    case validationFailed([ManifestValidationError])
}

/// Loads a character package's manifest.json from disk, decodes it, and
/// validates it against ManifestValidator. Never throws to a caller that
/// can't recover — `loadOrFallback` always returns a usable manifest.
public enum CharacterPackageLoader {
    public static func load(
        manifestURL: URL,
        data: Data? = nil,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Result<CharacterManifest, CharacterPackageError> {
        let jsonData: Data
        if let data {
            jsonData = data
        } else {
            guard let loaded = try? Data(contentsOf: manifestURL) else {
                return .failure(.fileNotFound(manifestURL.path))
            }
            jsonData = loaded
        }

        let decoder = JSONDecoder()
        guard let manifest = try? decoder.decode(CharacterManifest.self, from: jsonData) else {
            return .failure(.malformedJSON(manifestURL.path))
        }

        let baseDir = manifestURL.deletingLastPathComponent()
        let errors = ManifestValidator.validate(manifest) { relativePath in
            fileExists(baseDir.appendingPathComponent(relativePath).path)
        }
        if !errors.isEmpty {
            return .failure(.validationFailed(errors))
        }

        return .success(manifest)
    }

    /// Always returns a renderable manifest: the loaded one on success, or
    /// `SafeDefaultCharacter.manifest` on any failure. This is what the app
    /// actually calls at startup — the distinction between "not found",
    /// "malformed", and "invalid" only matters for logging/tests.
    public static func loadOrFallback(
        manifestURL: URL,
        data: Data? = nil,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        onFailure: (CharacterPackageError) -> Void = { _ in }
    ) -> CharacterManifest {
        switch load(manifestURL: manifestURL, data: data, fileExists: fileExists) {
        case .success(let manifest):
            return manifest
        case .failure(let error):
            onFailure(error)
            return SafeDefaultCharacter.manifest
        }
    }
}
