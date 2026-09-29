import Foundation
import Core

private let dummyURL = URL(fileURLWithPath: "/tmp/does-not-matter/manifest.json")

func runCharacterPackageLoaderTests(_ runner: TestRunner) {
    runner.run("CharacterPackageLoader.validJSON_loadsSuccessfully") {
        let json = """
        {
          "id": "biscuit", "displayName": "Biscuit", "attribution": null, "initialState": "idle",
          "states": [ { "id": "idle", "animation": { "spriteSheet": "idle.png", "frameWidth": 32, "frameHeight": 32, "frameCount": 4, "framesPerSecond": 8, "loop": true } } ],
          "transitions": []
        }
        """.data(using: .utf8)!
        let result = CharacterPackageLoader.load(manifestURL: dummyURL, data: json, fileExists: { _ in true })
        switch result {
        case .success(let manifest): try expectEqual(manifest.id, "biscuit")
        case .failure(let error): try fail("Expected success, got \(error)")
        }
    }

    runner.run("CharacterPackageLoader.malformedJSON_isReportedNotThrown") {
        let json = "{ this is not valid json ".data(using: .utf8)!
        let result = CharacterPackageLoader.load(manifestURL: dummyURL, data: json, fileExists: { _ in true })
        switch result {
        case .success: try fail("Expected failure for malformed JSON")
        case .failure(let error):
            guard case .malformedJSON = error else { try fail("Expected malformedJSON, got \(error)"); return }
        }
    }

    runner.run("CharacterPackageLoader.missingRequiredField_failsValidation") {
        let json = """
        {
          "id": "", "displayName": "Biscuit", "attribution": null, "initialState": "idle",
          "states": [ { "id": "idle", "animation": { "spriteSheet": "idle.png", "frameWidth": 32, "frameHeight": 32, "frameCount": 4, "framesPerSecond": 8, "loop": true } } ],
          "transitions": []
        }
        """.data(using: .utf8)!
        let result = CharacterPackageLoader.load(manifestURL: dummyURL, data: json, fileExists: { _ in true })
        switch result {
        case .success: try fail("Expected validation failure")
        case .failure(let error):
            guard case .validationFailed(let errors) = error else { try fail("Expected validationFailed, got \(error)"); return }
            try expectTrue(errors.contains(.missingRequiredField("id")))
        }
    }

    runner.run("CharacterPackageLoader.missingSpriteFile_failsValidationNotCrash") {
        let json = """
        {
          "id": "biscuit", "displayName": "Biscuit", "attribution": null, "initialState": "idle",
          "states": [ { "id": "idle", "animation": { "spriteSheet": "idle.png", "frameWidth": 32, "frameHeight": 32, "frameCount": 4, "framesPerSecond": 8, "loop": true } } ],
          "transitions": []
        }
        """.data(using: .utf8)!
        let result = CharacterPackageLoader.load(manifestURL: dummyURL, data: json, fileExists: { _ in false })
        switch result {
        case .success: try fail("Expected validation failure due to missing sprite asset")
        case .failure(let error):
            guard case .validationFailed(let errors) = error else { try fail("Expected validationFailed, got \(error)"); return }
            try expectTrue(errors.contains(.missingSpriteAsset(state: "idle", path: "idle.png")))
        }
    }

    runner.run("CharacterPackageLoader.fileNotFound_isReported") {
        let missingURL = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID().uuidString)/manifest.json")
        let result = CharacterPackageLoader.load(manifestURL: missingURL)
        switch result {
        case .success: try fail("Expected fileNotFound")
        case .failure(let error):
            guard case .fileNotFound = error else { try fail("Expected fileNotFound, got \(error)"); return }
        }
    }

    runner.run("CharacterPackageLoader.loadOrFallback_returnsSafeDefaultOnFailure") {
        let missingURL = URL(fileURLWithPath: "/tmp/definitely-does-not-exist-\(UUID().uuidString)/manifest.json")
        var reportedError: CharacterPackageError?
        let manifest = CharacterPackageLoader.loadOrFallback(manifestURL: missingURL, onFailure: { reportedError = $0 })
        try expectEqual(manifest, SafeDefaultCharacter.manifest)
        try expectNotNil(reportedError)
    }

    runner.run("CharacterPackageLoader.loadOrFallback_doesNotCrashOnCorruptPackage") {
        let json = "not json at all".data(using: .utf8)!
        var reportedError: CharacterPackageError?
        let manifest = CharacterPackageLoader.loadOrFallback(
            manifestURL: dummyURL, data: json, fileExists: { _ in true }, onFailure: { reportedError = $0 }
        )
        try expectEqual(manifest, SafeDefaultCharacter.manifest)
        guard case .malformedJSON = reportedError else { try fail("Expected malformedJSON, got \(String(describing: reportedError))"); return }
    }
}
