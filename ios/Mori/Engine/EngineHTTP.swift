import Foundation
import WebKit

/// Native HTTP client used by the scraper core.
/// It mirrors the request/response semantics of Capacitor's `CapacitorHttp` on iOS,
/// so the shared JS scrapers behave exactly like they did in the Capacitor build.
enum EngineHTTP {
    struct HTTPError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let insecureDelegate = InsecureTrustDelegate()
    private static let insecureSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: insecureDelegate, delegateQueue: nil)
    }()

    static func perform(_ options: [String: Any]) async throws -> [String: Any] {
        guard var urlString = options["url"] as? String, !urlString.isEmpty else {
            throw HTTPError(message: "Invalid URL")
        }
        let method = ((options["method"] as? String) ?? "GET").uppercased()
        let headers = (options["headers"] as? [String: Any]) ?? [:]
        let params = (options["params"] as? [String: Any]) ?? [:]
        let responseType = ((options["responseType"] as? String) ?? "text").lowercased()
        let timeoutMs = (options["timeout"] as? NSNumber)?.doubleValue ?? 30000
        let insecure = (options["disableSSLValidation"] as? Bool) ?? false

        // Same rule as Capacitor: only encode when the string has no percent escapes yet
        if urlString == urlString.removingPercentEncoding,
           let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString = encoded
        }
        guard var url = URL(string: urlString) else { throw HTTPError(message: "Invalid URL: \(urlString)") }

        if !params.isEmpty, var comps = URLComponents(url: url, resolvingAgainstBaseURL: true) {
            var items = comps.queryItems ?? []
            for (key, value) in params {
                if let arr = value as? [Any] {
                    arr.forEach { items.append(URLQueryItem(name: key, value: "\($0)")) }
                } else {
                    items.append(URLQueryItem(name: key, value: "\(value)"))
                }
            }
            comps.queryItems = items
            if let u = comps.url { url = u }
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = max(5, timeoutMs / 1000)
        if let lang = Locale.autoupdatingCurrent.language.languageCode?.identifier {
            if let region = Locale.autoupdatingCurrent.region?.identifier {
                request.setValue("\(lang)-\(region),\(lang);q=0.5", forHTTPHeaderField: "Accept-Language")
            } else {
                request.setValue("\(lang);q=0.5", forHTTPHeaderField: "Accept-Language")
            }
        }
        var normalizedHeaders: [String: String] = [:]
        for (key, value) in headers {
            let v = "\(value)"
            request.setValue(v, forHTTPHeaderField: key)
            normalizedHeaders[key.lowercased()] = v
        }

        if let body = options["data"], !(body is NSNull) {
            // Capacitor only attaches a body when a Content-Type is present
            if let contentType = normalizedHeaders["content-type"] {
                request.httpBody = try encodeBody(body, contentType: contentType, request: &request)
            } else if let s = body as? String, method != "GET" {
                request.httpBody = Data(s.utf8)
            }
        }

        let (data, response) = try await (insecure ? insecureSession : session).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError(message: "Invalid response") }

        var out: [String: Any] = [:]
        out["status"] = http.statusCode
        var lowered: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            lowered[String(describing: k).lowercased()] = String(describing: v)
        }
        out["headers"] = lowered
        out["url"] = http.url?.absoluteString ?? url.absoluteString

        let contentType = (lowered["content-type"] ?? "application/default").lowercased()
        if contentType.contains("application/json") || responseType == "json" {
            if let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                out["data"] = obj
            } else {
                out["data"] = decodeText(data)
            }
        } else if responseType == "arraybuffer" || responseType == "blob" {
            out["data"] = data.base64EncodedString()
        } else {
            out["data"] = decodeText(data)
        }
        return out
    }

    private static func decodeText(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodeBody(_ body: Any, contentType: String, request: inout URLRequest) throws -> Data? {
        if let s = body as? String { return Data(s.utf8) }
        let ct = contentType.lowercased()
        if ct.contains("application/json") {
            guard JSONSerialization.isValidJSONObject(body) else {
                throw HTTPError(message: "Request body must be serializable to JSON")
            }
            return try JSONSerialization.data(withJSONObject: body)
        }
        if ct.contains("application/x-www-form-urlencoded") {
            guard let obj = body as? [String: Any] else { throw HTTPError(message: "Form body must be an object") }
            let allowed = CharacterSet(charactersIn: "-._*").union(.alphanumerics)
            func enc(_ s: String) -> String {
                (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: "%20", with: "+")
            }
            return Data(obj.map { "\(enc($0.key))=\(enc("\($0.value)"))" }.joined(separator: "&").utf8)
        }
        if ct.contains("multipart/form-data") {
            guard let obj = body as? [String: Any] else { throw HTTPError(message: "Multipart body must be an object") }
            var boundary = UUID().uuidString
            if let range = contentType.range(of: "boundary=") {
                var b = String(contentType[range.upperBound...])
                if let semi = b.firstIndex(of: ";") { b = String(b[..<semi]) }
                boundary = b.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } else {
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            }
            var data = Data()
            for (key, value) in obj {
                data.append(Data("\r\n--\(boundary)\r\n".utf8))
                data.append(Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
                data.append(Data("\(value)".utf8))
            }
            data.append(Data("\r\n--\(boundary)--\r\n".utf8))
            return data
        }
        if JSONSerialization.isValidJSONObject(body) {
            return try JSONSerialization.data(withJSONObject: body)
        }
        throw HTTPError(message: "Request body could not be encoded for \(contentType)")
    }
}

/// Accepts any server certificate. Only used when "Bypass SSL validation" is enabled in settings.
final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// `window.webkit.messageHandlers.moriHttp.postMessage(options)` → Promise<response>
final class EngineHTTPBridge: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any] else {
            replyHandler(nil, "Invalid request payload")
            return
        }
        Task.detached {
            do {
                let result = try await EngineHTTP.perform(body)
                await MainActor.run { replyHandler(result, nil) }
            } catch {
                let msg = error.localizedDescription
                await MainActor.run { replyHandler(nil, msg) }
            }
        }
    }
}
