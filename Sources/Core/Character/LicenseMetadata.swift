import Foundation

/// Where a character's artwork came from and who to credit.
public struct LicenseMetadata: Codable, Equatable {
    public let type: String?
    public let name: String?
    public let url: String?
    public let author: String?
    public let sourceURL: String?

    public init(type: String? = nil, name: String? = nil, url: String? = nil, author: String? = nil, sourceURL: String? = nil) {
        self.type = type
        self.name = name
        self.url = url
        self.author = author
        self.sourceURL = sourceURL
    }
}
