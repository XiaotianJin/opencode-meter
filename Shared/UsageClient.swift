import Foundation

// MARK: - Model

struct UsageWindow: Codable, Equatable {
    /// Percentage already consumed, 0...100.
    let usedPercent: Double
    let limited: Bool
    let resetsAt: Date

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct UsageSnapshot: Codable, Equatable {
    let rolling: UsageWindow?
    let weekly: UsageWindow?
    let monthly: UsageWindow?
    let usageURL: URL?
    let workspaceName: String?
}

// MARK: - Service discovery

struct OpenCodeService: Codable, Equatable {
    let url: URL
    let password: String

    static var stateFileURL: URL {
        if let override = ProcessInfo.processInfo.environment["OPENCODE_SERVICE_FILE"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/opencode/service.json")
    }

    /// The shared OpenCode service rewrites this file on every start, so read it
    /// fresh instead of caching the port.
    static func discover() -> OpenCodeService? {
        guard let data = try? Data(contentsOf: stateFileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawURL = object["url"] as? String,
              let url = URL(string: rawURL),
              let password = object["password"] as? String,
              !password.isEmpty
        else { return nil }
        return OpenCodeService(url: url, password: password)
    }
}

// MARK: - Wire model
//
// GET /api/experimental/usage/limits
// {
//   "data": {
//     "workspace": { "id": "...", "name": "Default", "usageURL": "..." },
//     "go": {
//       "rolling": { "percent": 0, "limited": false, "resetsAt": 1793687085000 },
//       "weekly":  { "percent": 2, "limited": false, "resetsAt": 1794182400000 },
//       "monthly": { "percent": 1, "limited": false, "resetsAt": 1796178951000 }
//     }
//   }
// }

private struct WireWindow: Decodable {
    let percent: Double
    let limited: Bool
    let resetsAt: Double
}

private struct WireGo: Decodable {
    let rolling: WireWindow?
    let weekly: WireWindow?
    let monthly: WireWindow?
}

private struct WireWorkspace: Decodable {
    let id: String?
    let name: String?
    let usageURL: String?
}

private struct WireData: Decodable {
    let workspace: WireWorkspace?
    let go: WireGo?
}

private struct WireResponse: Decodable {
    let data: WireData?
}

// MARK: - Errors

enum UsageError: Error {
    case serviceMissing
    case unauthorized
    case notSignedIn
    case http(Int)
    case network
    case malformed

    var message: String {
        switch self {
        case .serviceMissing:
            return "未找到 OpenCode 服务，请先启动 OpenCode"
        case .unauthorized:
            return "认证失败，请在 OpenCode 中重新登录"
        case .notSignedIn:
            return "当前未登录 OpenCode 账号"
        case .http(let code):
            return "服务返回 HTTP \(code)"
        case .network:
            return "无法连接 OpenCode 本地服务"
        case .malformed:
            return "返回数据格式异常"
        }
    }
}

// MARK: - Client

enum UsageClient {
    static func fetchLive() async throws -> (snapshot: UsageSnapshot, service: OpenCodeService) {
        guard let service = OpenCodeService.discover() else {
            throw UsageError.serviceMissing
        }
        let snapshot = try await fetch(service: service)
        return (snapshot, service)
    }

    static func fetch(service: OpenCodeService) async throws -> UsageSnapshot {
        var request = URLRequest(url: service.url.appendingPathComponent("api/experimental/usage/limits"))
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let token = Data("opencode:\(service.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.malformed
        }
        switch http.statusCode {
        case 200:
            break
        case 401, 403:
            throw UsageError.unauthorized
        default:
            throw UsageError.http(http.statusCode)
        }

        guard let wire = try? JSONDecoder().decode(WireResponse.self, from: data) else {
            throw UsageError.malformed
        }
        guard let payload = wire.data else {
            throw UsageError.notSignedIn
        }
        guard let go = payload.go else {
            throw UsageError.malformed
        }

        func convert(_ window: WireWindow?) -> UsageWindow? {
            guard let window else { return nil }
            return UsageWindow(
                usedPercent: window.percent,
                limited: window.limited,
                resetsAt: Date(timeIntervalSince1970: window.resetsAt / 1000)
            )
        }

        return UsageSnapshot(
            rolling: convert(go.rolling),
            weekly: convert(go.weekly),
            monthly: convert(go.monthly),
            usageURL: payload.workspace?.usageURL.flatMap(URL.init(string:)),
            workspaceName: payload.workspace?.name
        )
    }
}
