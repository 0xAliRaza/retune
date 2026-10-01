import Foundation

/// Fast, accent/case-insensitive matching for catalogs with tens of thousands of titles.
public enum SearchText {
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Every whitespace-separated term in `query` must appear in `normalizedName`.
    public static func matches(normalizedName: String, terms: [String]) -> Bool {
        terms.allSatisfy { normalizedName.contains($0) }
    }

    public static func terms(_ query: String) -> [String] {
        normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

public enum BrowseSort: String, CaseIterable, Identifiable, Sendable {
    case provider, title, recentlyAdded, rating

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .provider: "Default"
        case .title: "Title"
        case .recentlyAdded: "Recently Added"
        case .rating: "Rating"
        }
    }
}

/// Uniform view over channels, movies and series for filtering, counting and sorting.
public protocol Browsable: Identifiable<String> {
    var name: String { get }
    var categoryID: String? { get }
    var sortDate: Date? { get }
    var sortRating: Double? { get }
}

extension Channel: Browsable {
    public var sortDate: Date? { nil }
    public var sortRating: Double? { nil }
}

extension Movie: Browsable {
    public var sortDate: Date? { added }
    public var sortRating: Double? { rating }
}

extension Series: Browsable {
    public var sortDate: Date? { lastModified }
    public var sortRating: Double? { rating }
}

/// Precomputed lookups for one content list: per-category membership and normalised names.
public struct BrowseIndex<Item: Browsable>: Sendable where Item: Sendable {
    public let items: [Item]
    private let normalizedNames: [String]
    private let byCategory: [String: [Int]]
    private let positionByID: [String: Int]

    public init(_ items: [Item]) {
        self.items = items
        normalizedNames = items.map { SearchText.normalize($0.name) }
        var groups: [String: [Int]] = [:]
        var positions: [String: Int] = [:]
        for (offset, item) in items.enumerated() {
            if let category = item.categoryID { groups[category, default: []].append(offset) }
            positions[item.id] = positions[item.id] ?? offset
        }
        byCategory = groups
        positionByID = positions
    }

    public func count(in categoryID: String) -> Int { byCategory[categoryID]?.count ?? 0 }

    public func item(id: String) -> Item? { positionByID[id].map { items[$0] } }

    /// Items for a category (nil = all), optionally narrowed by a search query, restricted to `ids`,
    /// and with items from `excludedCategories` (hidden or locked) left out.
    public func select(category: String?, query: String = "", ids: Set<String>? = nil,
                       excludedCategories: Set<String> = [], sort: BrowseSort = .provider) -> [Item] {
        var offsets: [Int] = category.map { byCategory[$0] ?? [] } ?? Array(items.indices)
        if let ids { offsets = offsets.filter { ids.contains(items[$0].id) } }
        if !excludedCategories.isEmpty {
            offsets = offsets.filter { items[$0].categoryID.map { !excludedCategories.contains($0) } ?? true }
        }
        let terms = SearchText.terms(query)
        if !terms.isEmpty {
            offsets = offsets.filter { SearchText.matches(normalizedName: normalizedNames[$0], terms: terms) }
        }
        return sorted(offsets, by: sort).map { items[$0] }
    }

    private func sorted(_ offsets: [Int], by order: BrowseSort) -> [Int] {
        switch order {
        case .provider:
            return offsets
        case .title:
            return offsets.sorted { normalizedNames[$0] < normalizedNames[$1] }
        case .recentlyAdded:
            return offsets.sorted { (items[$0].sortDate ?? .distantPast) > (items[$1].sortDate ?? .distantPast) }
        case .rating:
            return offsets.sorted { (items[$0].sortRating ?? -1) > (items[$1].sortRating ?? -1) }
        }
    }
}
