import Foundation

/// One picker row: enough to render a list without decoding any sprite.
public struct CharacterCatalogEntry: Equatable {
    public let id: String
    public let name: String
    public let description: String
    public let author: String?
    public let previewRelativePath: String?
    public let tags: [String]

    public init(id: String, name: String, description: String, author: String?, previewRelativePath: String?, tags: [String]) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.previewRelativePath = previewRelativePath
        self.tags = tags
    }
}

public enum CharacterCatalog {
    public static func entries(_ characters: [CharacterDefinition]) -> [CharacterCatalogEntry] {
        characters.map(entry(for:))
    }

    public static func entry(for character: CharacterDefinition) -> CharacterCatalogEntry {
        CharacterCatalogEntry(
            id: character.id,
            name: character.displayName,
            description: character.manifest.description ?? character.tagline,
            author: character.manifest.license?.author,
            previewRelativePath: character.manifest.preview?.spriteSheet,
            tags: []
        )
    }
}

public enum CharacterLibrarySection: String, CaseIterable, Equatable {
    case all = "All"
    case favorites = "Favorites"
}

public enum CharacterLibrary {
    public static func filter(_ entries: [CharacterCatalogEntry], section: CharacterLibrarySection, favorites: Set<String> = []) -> [CharacterCatalogEntry] {
        switch section {
        case .all: return entries
        case .favorites: return entries.filter { favorites.contains($0.id) }
        }
    }
}
