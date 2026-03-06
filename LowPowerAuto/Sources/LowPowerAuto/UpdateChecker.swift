import Foundation

struct UpdateInfo {
    let version: String
    let url: String
}

enum UpdateCheckError: Error {
    case message(String)
}

final class UpdateChecker {
    private let owner: String
    private let repo: String

    init(owner: String = "payrghfgh", repo: String = "Low-Power-Mode-Auto") {
        self.owner = owner
        self.repo = repo
    }

    func checkLatestRelease(completion: @escaping (Result<UpdateInfo, UpdateCheckError>) -> Void) {
        let endpoint = "https://api.github.com/repos/\(owner)/\(repo)/releases/latest"
        guard let url = URL(string: endpoint) else {
            completion(.failure(.message("Invalid update URL")))
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("LowPowerAuto", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(.message("Update check failed: \(error.localizedDescription)")))
                return
            }

            guard let data else {
                completion(.failure(.message("Update check failed: empty response")))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(.message("Invalid update response")))
                    return
                }

                let tag = (json["tag_name"] as? String) ?? "unknown"
                let htmlURL = (json["html_url"] as? String) ?? ""
                completion(.success(UpdateInfo(version: tag, url: htmlURL)))
            } catch {
                completion(.failure(.message("Failed to parse update response")))
            }
        }.resume()
    }
}
