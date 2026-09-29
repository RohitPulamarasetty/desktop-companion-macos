import Core

func makeAnimation(
    sheet: String = "idle.png",
    w: Int = 32,
    h: Int = 32,
    frames: Int = 4,
    fps: Double = 8,
    loop: Bool = true
) -> AnimationDefinition {
    AnimationDefinition(spriteSheet: sheet, frameWidth: w, frameHeight: h, frameCount: frames, framesPerSecond: fps, loop: loop)
}

func runManifestValidatorTests(_ runner: TestRunner) {
    runner.run("ManifestValidator.validManifest_producesNoErrors") {
        let manifest = CharacterManifest(
            id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "idle",
            states: [StateDefinition(id: "idle", animation: makeAnimation())], transitions: []
        )
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.isEmpty)
    }

    runner.run("ManifestValidator.missingID_isReported") {
        let manifest = CharacterManifest(
            id: "", displayName: "Biscuit", attribution: nil, initialState: "idle",
            states: [StateDefinition(id: "idle", animation: makeAnimation())], transitions: []
        )
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.contains(.missingRequiredField("id")))
    }

    runner.run("ManifestValidator.emptyStates_isReported") {
        let manifest = CharacterManifest(id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "idle", states: [], transitions: [])
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.contains(.missingRequiredField("states")))
    }

    runner.run("ManifestValidator.duplicateStateID_isReported") {
        let manifest = CharacterManifest(
            id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "idle",
            states: [
                StateDefinition(id: "idle", animation: makeAnimation()),
                StateDefinition(id: "idle", animation: makeAnimation(sheet: "idle2.png")),
            ], transitions: []
        )
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.contains(.duplicateStateID("idle")))
    }

    runner.run("ManifestValidator.invalidTransitionTargets_areReported") {
        let manifest = CharacterManifest(
            id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "idle",
            states: [StateDefinition(id: "idle", animation: makeAnimation())],
            transitions: [
                TransitionDefinition(from: "idle", to: "ghost-state", trigger: .timeout, weight: 1, minimumDuration: 5),
                TransitionDefinition(from: "another-ghost", to: "idle", trigger: .mouseDown, weight: 1, minimumDuration: nil),
            ]
        )
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.contains(.unknownStateInTransition(field: "to", stateID: "ghost-state")))
        try expectTrue(errors.contains(.unknownStateInTransition(field: "from", stateID: "another-ghost")))
    }

    runner.run("ManifestValidator.invalidFrameCount_isReported") {
        let manifest = CharacterManifest(
            id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "idle",
            states: [StateDefinition(id: "idle", animation: makeAnimation(frames: 0))], transitions: []
        )
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.contains(.invalidFrameCount(state: "idle", value: 0)))
    }

    runner.run("ManifestValidator.invalidFrameRate_isReported") {
        let manifest = CharacterManifest(
            id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "idle",
            states: [StateDefinition(id: "idle", animation: makeAnimation(fps: 0))], transitions: []
        )
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.contains(.invalidFrameRate(state: "idle", value: 0)))
    }

    runner.run("ManifestValidator.invalidFrameDimensions_isReported") {
        let manifest = CharacterManifest(
            id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "idle",
            states: [StateDefinition(id: "idle", animation: makeAnimation(w: 0, h: -1))], transitions: []
        )
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.contains(.invalidFrameDimensions(state: "idle", width: 0, height: -1)))
    }

    runner.run("ManifestValidator.noMatchingInitialState_isReported") {
        let manifest = CharacterManifest(
            id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "does-not-exist",
            states: [StateDefinition(id: "idle", animation: makeAnimation())], transitions: []
        )
        let errors = ManifestValidator.validate(manifest) { _ in true }
        try expectTrue(errors.contains(.noInitialState("does-not-exist")))
    }

    runner.run("ManifestValidator.missingSpriteAsset_isReported") {
        let manifest = CharacterManifest(
            id: "biscuit", displayName: "Biscuit", attribution: nil, initialState: "idle",
            states: [StateDefinition(id: "idle", animation: makeAnimation(sheet: "missing.png"))], transitions: []
        )
        let errors = ManifestValidator.validate(manifest) { path in path != "missing.png" }
        try expectTrue(errors.contains(.missingSpriteAsset(state: "idle", path: "missing.png")))
    }
}
