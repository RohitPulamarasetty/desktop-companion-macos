import Foundation

/// Every way a character package can be malformed. The engine must catch all
/// of these at load time and fall back safely — never crash on a bad package.
public enum ManifestValidationError: Error, Equatable, CustomStringConvertible {
    case missingRequiredField(String)
    case duplicateStateID(String)
    case unknownStateInTransition(field: String, stateID: String)
    case invalidFrameCount(state: String, value: Int)
    case invalidFrameRate(state: String, value: Double)
    case invalidFrameDimensions(state: String, width: Int, height: Int)
    case noInitialState(String)
    case missingSpriteAsset(state: String, path: String)
    /// A sprite path failed `PackagePathPolicy` -- absolute, `~`-relative,
    /// contains `..`, or uses a file extension packages may not ship
    /// (script, binary, executable, ...). Never a missing-file problem;
    /// see `missingSpriteAsset` for that.
    case unsafeAssetPath(state: String, path: String)

    public var description: String {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .duplicateStateID(let id):
            return "Duplicate state id: \(id)"
        case .unknownStateInTransition(let field, let stateID):
            return "Transition references unknown state '\(stateID)' in field '\(field)'"
        case .invalidFrameCount(let state, let value):
            return "State '\(state)' has invalid frameCount: \(value)"
        case .invalidFrameRate(let state, let value):
            return "State '\(state)' has invalid framesPerSecond: \(value)"
        case .invalidFrameDimensions(let state, let width, let height):
            return "State '\(state)' has invalid frame dimensions: \(width)x\(height)"
        case .noInitialState(let id):
            return "initialState '\(id)' does not match any declared state"
        case .missingSpriteAsset(let state, let path):
            return "State '\(state)' references missing sprite asset: \(path)"
        case .unsafeAssetPath(let state, let path):
            return "State '\(state)' references an unsafe or disallowed asset path: \(path)"
        }
    }
}

/// Validates a decoded manifest against the engine's structural rules.
/// Decoding failures (malformed JSON) are handled separately by the loader —
/// this validator only runs on manifests that decoded successfully.
public enum ManifestValidator {
    public static func validate(
        _ manifest: CharacterManifest,
        assetsExist: (String) -> Bool
    ) -> [ManifestValidationError] {
        var errors: [ManifestValidationError] = []

        if manifest.id.trimmingCharacters(in: .whitespaces).isEmpty {
            errors.append(.missingRequiredField("id"))
        }
        if manifest.states.isEmpty {
            errors.append(.missingRequiredField("states"))
        }

        var seenStateIDs = Set<String>()
        for state in manifest.states {
            if seenStateIDs.contains(state.id) {
                errors.append(.duplicateStateID(state.id))
            }
            seenStateIDs.insert(state.id)

            let animation = state.animation
            if animation.frameCount <= 0 {
                errors.append(.invalidFrameCount(state: state.id, value: animation.frameCount))
            }
            if animation.framesPerSecond <= 0 {
                errors.append(.invalidFrameRate(state: state.id, value: animation.framesPerSecond))
            }
            if animation.frameWidth <= 0 || animation.frameHeight <= 0 {
                errors.append(.invalidFrameDimensions(state: state.id, width: animation.frameWidth, height: animation.frameHeight))
            }
            // Path safety is checked before ever touching the filesystem
            // with this string: a package must never be able to make the
            // loader stat or read outside its own directory.
            if !PackagePathPolicy.isAllowedPackageFile(animation.spriteSheet) {
                errors.append(.unsafeAssetPath(state: state.id, path: animation.spriteSheet))
            } else if !assetsExist(animation.spriteSheet) {
                errors.append(.missingSpriteAsset(state: state.id, path: animation.spriteSheet))
            }
        }

        if !seenStateIDs.contains(manifest.initialState) {
            errors.append(.noInitialState(manifest.initialState))
        }

        if let preview = manifest.preview {
            if !PackagePathPolicy.isAllowedPackageFile(preview.spriteSheet) {
                errors.append(.unsafeAssetPath(state: "preview", path: preview.spriteSheet))
            } else if !assetsExist(preview.spriteSheet) {
                errors.append(.missingSpriteAsset(state: "preview", path: preview.spriteSheet))
            }
        }

        for transition in manifest.transitions {
            if !seenStateIDs.contains(transition.from) {
                errors.append(.unknownStateInTransition(field: "from", stateID: transition.from))
            }
            if !seenStateIDs.contains(transition.to) {
                errors.append(.unknownStateInTransition(field: "to", stateID: transition.to))
            }
        }

        return errors
    }
}
