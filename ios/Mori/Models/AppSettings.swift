import SwiftUI

enum PreferServer: String, CaseIterable, Identifiable {
    case ask, server1, server2
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .ask: return "Ask every time"
        case .server1: return "Server 1"
        case .server2: return "Server 2"
        }
    }
}

enum SaveTarget: String, CaseIterable, Identifiable {
    case files, photos, both
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .files: return "Files only"
        case .photos: return "Photos only"
        case .both: return "Files & Photos"
        }
    }
}

enum FilenameTemplate: String, CaseIterable, Identifiable {
    case title, titlePlatform = "title-platform", titleDate = "title-date", titleTimestamp = "title-timestamp"
    // Short formats with a per-platform running number (upstream #21)
    case platformDateNumber = "platform_date_number"
    case platformTimeNumber = "platform_time_number"
    case platformQualityNumber = "platform_quality_number"
    case platformDateTimeQualityNumber = "platform_date_time_quality_number"

    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .title: return "Title"
        case .titlePlatform: return "Title_Platform"
        case .titleDate: return "Title_Date"
        case .titleTimestamp: return "Title_Timestamp"
        case .platformDateNumber: return "Platform_Date_No."
        case .platformTimeNumber: return "Platform_Time_No."
        case .platformQualityNumber: return "Platform_Quality_No."
        case .platformDateTimeQualityNumber: return "Platform_Date_Time_Quality_No."
        }
    }

    /// Placeholder pattern: {title} {platform} {date} {time} {quality} {num} {timestamp}
    var pattern: String {
        switch self {
        case .title: return "{title}"
        case .titlePlatform: return "{title}_{platform}"
        case .titleDate: return "{title}_{date}"
        case .titleTimestamp: return "{title}_{timestamp}"
        case .platformDateNumber: return "{platform}_{date}_{num}"
        case .platformTimeNumber: return "{platform}_{time}_{num}"
        case .platformQualityNumber: return "{platform}_{quality}_{num}"
        case .platformDateTimeQualityNumber: return "{platform}_{date}_{time}_{quality}_{num}"
        }
    }
}

enum BatchFormat: String, CaseIterable, Identifiable {
    case video, audio
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .video: return "Video (best available)"
        case .audio: return "Audio only (MP3)"
        }
    }
}

enum OverwriteMode: String, CaseIterable, Identifiable {
    case rename, overwrite, skip
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .rename: return "Keep both (rename)"
        case .overwrite: return "Overwrite"
        case .skip: return "Skip"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum UserAgentPreset: String, CaseIterable, Identifiable {
    case `default`, safari, desktop
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .default: return "Default (Android Chrome)"
        case .safari: return "iPhone Safari"
        case .desktop: return "Desktop Chrome"
        }
    }
}

/// App-wide preferences backed by UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @AppStorage("preferServer") var preferServer: PreferServer = .ask
    @AppStorage("saveTarget") var saveTarget: SaveTarget = .files
    @AppStorage("filenameTemplate") var filenameTemplate: FilenameTemplate = .title
    @AppStorage("overwriteMode") var overwriteMode: OverwriteMode = .rename
    @AppStorage("autoPlatformFolder") var autoPlatformFolder = true
    @AppStorage("concurrentDownloads") var concurrentDownloads = 2
    @AppStorage("autoDownload") var autoDownload = false
    @AppStorage("batchFormat") var batchFormat: BatchFormat = .video
    @AppStorage("requestTimeout") var requestTimeout = 30
    @AppStorage("headerSpoofing") var headerSpoofing = true
    @AppStorage("bypassSSL") var bypassSSL = false
    @AppStorage("userAgent") var userAgent: UserAgentPreset = .default
    @AppStorage("incognito") var incognito = false
    @AppStorage("appLock") var appLock = false
    @AppStorage("clipboardDetection") var clipboardDetection = true
    @AppStorage("appearance") var appearance: AppearanceMode = .system
    @AppStorage("haptics") var haptics = true
    @AppStorage("hideGalleryTab") var hideGalleryTab = false

    /// Values the scraper core reads through its localStorage shim.
    var engineConfig: [String: String] {
        [
            "mori_request_timeout": String(min(180, max(5, requestTimeout))),
            "mori_header_spoofing": headerSpoofing ? "true" : "false",
            "mori_bypass_ssl": bypassSSL ? "true" : "false",
            "mori_force_ipv4": "false",
            "mori_doh": "off",
            "mori_user_agent": userAgent.rawValue,
        ]
    }

    var downloadUserAgent: String {
        switch userAgent {
        case .default:
            return "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36"
        case .safari:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        case .desktop:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
        }
    }
}
