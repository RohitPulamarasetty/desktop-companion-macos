import Foundation

/// What a character package is allowed to contain and reference. A package
/// is DATA + ASSETS -- never code -- so this is the one place that decides
/// whether a path or file is safe to read, extract, or bundle.
public enum PackagePathPolicy {
    /// Extensions a character package may ship, by category. Anything else
    /// (scripts, binaries, executables, plugins, ...) is refused.
    public static let allowedImageExtensions: Set<String> = ["png", "webp"]
    public static let allowedAudioExtensions: Set<String> = ["caf", "wav", "aiff", "m4a", "mp3"]
    public static let allowedDataExtensions: Set<String> = ["json"]
    public static var allowedExtensions: Set<String> {
        allowedImageExtensions.union(allowedAudioExtensions).union(allowedDataExtensions)
    }

    /// Explicitly-dangerous extensions, rejected even if a future allow-list
    /// change is careless. Kept separate from "not in the allow list" so a
    /// rejection can say *why* rather than just "not permitted".
    public static let deniedExtensions: Set<String> = [
        "swift", "py", "js", "mjs", "ts", "exe", "dll", "dylib", "so",
        "command", "sh", "bash", "zsh", "app", "scpt", "applescript",
        "jar", "pl", "rb", "php", "wasm", "bin",
    ]

    /// A relative path is safe to resolve against a package's base
    /// directory if it: is non-empty, is not absolute, does not start with
    /// `~`, contains no backslashes, and has no
    /// `..` path component (parent-directory / zip-slip traversal). This is
    /// a string-level check independent of what's actually on disk, so it
    /// catches a malicious manifest *before* any file access is attempted.
    public static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        if path.hasPrefix("/") || path.hasPrefix("~") { return false }
        if path.contains("\\") { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        for c in components {
            if c == ".." { return false }
            // A leading-empty component means the path was "//foo" or
            // similar; treat it the same as absolute.
            if c.isEmpty && components.first != nil && c == components[0] { return false }
        }
        return true
    }

    /// Whether a file at `relativePath` is a kind a character package may
    /// legitimately contain: `manifest.json` at the root, sprite images
    /// under `sprites/`, previews at the root, audio under `sounds/`, and
    /// any JSON metadata. Everything else -- and every denied extension,
    /// anywhere -- is rejected regardless of location.
    public static func isAllowedPackageFile(_ relativePath: String) -> Bool {
        guard isSafeRelativePath(relativePath) else { return false }
        let ext = (relativePath as NSString).pathExtension.lowercased()
        if deniedExtensions.contains(ext) { return false }
        return allowedExtensions.contains(ext)
    }
}
