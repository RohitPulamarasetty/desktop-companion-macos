import Foundation

/// A coarse idea of what the user is doing, from the frontmost app's bundle
/// identifier only. Never stored or sent anywhere; used for the optional
/// "comment on what I'm doing" chatter.
public enum AppCategory: String, CaseIterable, Equatable {
    case coding, browsing, email, chatting, meeting, music, design, writing, video

    public static func category(forBundleID id: String) -> AppCategory? {
        let s = id.lowercased()
        func has(_ parts: [String]) -> Bool { parts.contains { s.contains($0) } }
        if has(["xcode", "vscode", "visualstudio", "jetbrains", "intellij", "pycharm", "webstorm", "sublimetext", "nova", "terminal", "iterm", "warp", "cursor", "zed", "androidstudio", "github"]) { return .coding }
        if has(["zoom", "microsoft.teams", "facetime", "webex", "meet", "skype"]) { return .meeting }
        if has(["slack", "discord", "mobilesms", "whatsapp", "telegram", "signal", "messenger", "imessage", "apple.messages"]) { return .chatting }
        if has(["apple.mail", "outlook", "spark", "airmail", "superhuman", "thunderbird"]) { return .email }
        if has(["spotify", "apple.music", "tidal", "deezer", "podcasts"]) { return .music }
        if has(["figma", "sketch", "photoshop", "illustrator", "affinity", "pixelmator", "canva", "blender", "lightroom"]) { return .design }
        if has(["notion", "apple.notes", "apple.iwork.pages", "microsoft.word", "obsidian", "bear", "ulysses", "scrivener", "drafts", "evernote", "craft"]) { return .writing }
        if has(["netflix", "youtube", "vlc", "iina", "quicktime", "apple.tv", "primevideo", "disney", "twitch"]) { return .video }
        if has(["safari", "chrome", "firefox", "brave", "arc", "opera", "vivaldi", "edge"]) { return .browsing }
        return nil
    }

    public var messageCategory: MessageCategory {
        switch self {
        case .coding: return .appCoding
        case .browsing: return .appBrowsing
        case .email: return .appEmail
        case .chatting: return .appChatting
        case .meeting: return .appMeeting
        case .music: return .appMusic
        case .design: return .appDesign
        case .writing: return .appWriting
        case .video: return .appVideo
        }
    }
}
