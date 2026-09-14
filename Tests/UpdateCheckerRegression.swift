import Foundation

@main
struct UpdateCheckerRegression {
    static func main() throws {
        let installed = QuickAddVersion("1.1.7")!
        precondition(QuickAddVersion("v1.1.8")! > installed)
        precondition(QuickAddVersion("1.1.10")! > QuickAddVersion("1.1.9")!)
        precondition(QuickAddVersion("2.0.0")! > QuickAddVersion("1.99.99")!)
        precondition(QuickAddVersion("1.1.7")! == installed)
        for invalid in ["", "v1.1", "1.1.7-beta", "1.1.7.1", "1..7"] {
            precondition(QuickAddVersion(invalid) == nil)
        }

        let good = #"{"tag_name":"v1.1.8","assets":[{"name":"QuickAdd.zip","browser_download_url":"https://github.com/TheCuriousProcrastinator/QuickAdd-for-Reminders/releases/download/v1.1.8/QuickAdd.zip"}]}"#
        let release = try QuickAddUpdateChecker.release(from: Data(good.utf8))
        precondition(release.version == "v1.1.8")
        precondition(release.downloadURL.lastPathComponent == "QuickAdd.zip")

        let missing = #"{"tag_name":"v1.1.8","assets":[]}"#
        let wrongHost = good.replacingOccurrences(of: "github.com", with: "example.com")
        let wrongRepository = good.replacingOccurrences(of: "QuickAdd-for-Reminders", with: "Other-Repository")
        for json in [missing, wrongHost, wrongRepository] {
            do {
                _ = try QuickAddUpdateChecker.release(from: Data(json.utf8))
                preconditionFailure("Unexpectedly accepted an invalid download")
            } catch QuickAddUpdateChecker.CheckError.missingZIP {
                // Expected.
            }
        }

        for json in ["{}", #"{"tag_name":"v1.1.8-beta","assets":[]}"#] {
            do {
                _ = try QuickAddUpdateChecker.release(from: Data(json.utf8))
                preconditionFailure("Unexpectedly accepted invalid release metadata")
            } catch QuickAddUpdateChecker.CheckError.invalidResponse {
                // Expected.
            }
        }
        print("Update checker regression checks passed")
    }
}
