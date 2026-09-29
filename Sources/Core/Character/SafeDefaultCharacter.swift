import Foundation

/// The built-in fallback used whenever a character package fails to load or
/// validate. It references no external sprite file — it is a single solid-color
/// 1x1 state so the app can always render *something* instead of crashing.
/// `SafeDefaultCharacter.spriteData` is a valid 1x1 transparent-red PNG, embedded
/// so this fallback never depends on disk assets being present.
public enum SafeDefaultCharacter {
    public static let spriteSheetName = "__safe_default__"

    public static let manifest = CharacterManifest(
        id: "safe-default",
        displayName: "Safe Default",
        attribution: nil,
        initialState: "idle",
        states: [
            StateDefinition(
                id: "idle",
                animation: AnimationDefinition(
                    spriteSheet: spriteSheetName,
                    frameWidth: 1,
                    frameHeight: 1,
                    frameCount: 1,
                    framesPerSecond: 1,
                    loop: true
                )
            )
        ],
        transitions: []
    )
}
