import Foundation

struct QuickAddVersion: Comparable {
    let parts: [Int]

    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              components.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = components.compactMap { Int($0) }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

struct QuickAddRelease {
    let version: String
    let downloadURL: URL
}

enum QuickAddUpdateChecker {
    private static let releasesAPI = URL(string:
        "https://api.github.com/repos/TheCuriousProcrastinator/QuickAdd-for-Reminders/releases/latest"
    )!
    private static let downloadPath = "/TheCuriousProcrastinator/QuickAdd-for-Reminders/releases/download/"

    enum CheckError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case missingZIP

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "GitHub did not return a valid QuickAdd release. Please try again later."
            case .httpStatus(let code): "GitHub returned HTTP \(code). Please try again later."
            case .missingZIP: "The latest QuickAdd release does not include QuickAdd.zip."
            }
        }
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
    }

    static func latestRelease() async throws -> QuickAddRelease {
        var request = URLRequest(url: releasesAPI)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("QuickAdd-for-Reminders", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CheckError.invalidResponse
        }
        guard response.statusCode == 200 else { throw CheckError.httpStatus(response.statusCode) }
        return try release(from: data)
    }

    static func release(from data: Data) throws -> QuickAddRelease {
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw CheckError.invalidResponse
        }
        guard QuickAddVersion(release.tag_name) != nil else { throw CheckError.invalidResponse }
        guard let asset = release.assets.first(where: { $0.name == "QuickAdd.zip" }),
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host == "github.com",
              asset.browser_download_url.path.hasPrefix(downloadPath) else {
            throw CheckError.missingZIP
        }
        return QuickAddRelease(version: release.tag_name, downloadURL: asset.browser_download_url)
    }
}
