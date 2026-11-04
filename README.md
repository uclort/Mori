<p align="center">
  <img src="assets/icon.png" width="128" alt="Mori Logo">
</p>

<h1 align="center">Mori</h1>
<p align="center"><em><strong>Save anything, From anywhere.</strong></em></p>

<p align="center">
  <img src="https://img.shields.io/badge/Version-v5.2.0-brown?style=flat-square" alt="Version">
  <img src="https://img.shields.io/badge/iOS-Native%20SwiftUI-0A84FF?style=flat-square&logo=swift&logoColor=white" alt="iOS Native SwiftUI">
  <a href="https://www.npmjs.com/package/@coflyn/mori"><img src="https://img.shields.io/npm/v/@coflyn/mori?style=flat-square&color=CB3837&logo=npm&logoColor=white" alt="NPM Version"></a>
  <img src="https://img.shields.io/github/downloads/coflyn/Mori/total?style=flat-square&color=blue" alt="Downloads">
  <img src="https://img.shields.io/github/stars/coflyn/Mori?style=flat-square&color=gold" alt="Stars">
  <img src="https://img.shields.io/github/repo-size/coflyn/Mori?style=flat-square&color=purple" alt="Repo Size">
  <img src="https://img.shields.io/badge/License-GPL--3.0-blue?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20CLI-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Platform">
</p>

<div align="center">

Save and download videos, photos, and music from 16 platforms. No watermarks. No accounts. No tracking. Everything stays on your device.

<a href="https://sociabuzz.com/coflyn/tribe" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="60" />
</a>

</div>

## 📸 Screenshots

<p align="center">
  <img src="assets/1.webp" width="30%">
  <img src="assets/2.webp" width="30%">
  <img src="assets/3.webp" width="30%">
</p>
<p align="center">
  <img src="assets/4.webp" width="30%">
  <img src="assets/5.webp" width="30%">
  <img src="assets/6.webp" width="30%">
</p>

---

## 🍎 iOS 原生重构（本分支 `custom/features`）

从 **v5.0.0** 起，本分支的 iOS 版不再使用 Capacitor + WebView 界面，而是 **用 SwiftUI 完全重写的原生 App**。核心解析能力保持不变，其余功能全部改为原生实现。

### 保留了什么

- **解析核心原样保留**：16 个平台的解析器仍是 `public/js/scrapers/bundle.js`（与 Android、CLI 共用同一份代码，支持 OTA 热更新）。
- 解析核心运行在一个**不可见的 WKWebView** 中，只把它当作 JS 运行时（`DOMParser`、`URL`、定时器）使用；解析器发出的所有网络请求都经 `CapacitorHttp` 兼容层交给原生 **URLSession** 处理，请求体/响应格式与原 Capacitor 版保持一致，解析器代码无需任何修改。
- 链接二次解析（YouTube / Spotify / Apple Music / SnapSave 等 `*_resolve:` 链接）、服务器 1/2 选择、抖音短链跳转与重试等逻辑均从原 JS 代码移植到引擎宿主 `ios/Mori/Engine/EngineHost.js` 中。

### 原生实现的功能

| 功能 | 实现方式 |
| :-- | :-- |
| 界面 | SwiftUI（首页 / 图库 / 历史 / 设置 四个标签页），深色模式跟随系统 |
| 网络请求 | URLSession（Cookie 共享、可选跳过 SSL 校验、可配置超时与 User-Agent） |
| 下载管理 | URLSession 下载任务：实时进度与速度、取消/重试、可配置并发数（1–5）、切到后台后短时继续 |
| 保存位置 | 「文件」App（`我的 iPhone › Mori`）/ 相册（PhotoKit）/ 两者；WebP 自动转 JPEG 入相册，设置中可一键打开「文件」App |
| 解析结果 | 图集以宫格展示，点图预览、点右上角按钮下载；视频/音频仅点下载按钮才开始下载 |
| 图片加载 | [Kingfisher](https://github.com/onevcat/Kingfisher)（自动带 Referer 等请求头、降采样、内存+磁盘缓存，设置中可一键清理） |
| 图片预览 | [JXPhotoBrowser](https://github.com/JiongXing/PhotoBrowser)（从点击的缩略图缩放展开、关闭时缩回原位置，缩放/左右滑动/下拉关闭，预览中可直接下载当前图） |
| 视频播放 | 系统播放器 AVPlayerViewController（在线预览自动带请求头） |
| 图库 | 图片用 JXPhotoBrowser、视频用系统播放器、音频/PDF 用 QuickLook；筛选、搜索、多选后右下角悬浮菜单批量保存到相册/分享/删除 |
| 图集导出 PDF | UIGraphicsPDFRenderer（替代 pdf-lib） |
| 批量模式 | 输入框每行一个链接，多个链接自动批量解析，失败时自动切换服务器 2 |
| 剪贴板 | 系统 `PasteButton`（不弹粘贴权限提示），粘贴只追加到输入框、不自动解析，可连续粘贴多个链接 |
| 隐私 | 无痕模式、面容 ID / 设备密码锁（LocalAuthentication） |
| 解析引擎 | 设置中查看引擎版本、在线检查更新（OTA）、恢复内置引擎 |
| 其他 | `mori://analyze?url=<链接>` URL Scheme、触感反馈、中英文本地化 |

> 下载目录与旧版保持一致（`Documents/Download/Mori/<平台>`、`Documents/Music/Mori/<平台>`），升级后旧文件仍会出现在图库中。旧版 WebView 中的历史记录无法迁移。
>
> 相比旧 Web 界面移除的内容：动态背景、音效、PIN 数字锁（改用系统面容 ID/密码）、内置自定义播放器（改用系统播放器/QuickLook）；界面语言目前为简体中文与英文。
>
> 修复：解析器为单个下载项返回的专用请求头（如 Bilibili 要求的 `User-Agent: Bilibili/1.0`）现在会被正确带上，旧版会因此出现 HTTP 403。

### 安装

- 在 [Releases](https://github.com/uclort/Mori/releases) 下载 `Mori-v*-custom.*-unsigned.ipa`，用 AltStore / SideStore / TrollStore 等自行签名安装（最低 iOS 16）。

### 从源码构建

```bash
brew install xcodegen          # 可选：修改 ios/project.yml 后重新生成工程
cd ios && xcodegen generate    # 生成 Mori.xcodeproj（仓库中已提交生成结果）
open Mori.xcodeproj            # 用 Xcode 直接运行

# 打包未签名 ipa → dist/Mori-v<版本>-iOS-Unsigned.ipa
npm run build:ios:ipa          # 等价于 bash ios/build-ipa.sh
```

---

## 📋 Table of Contents

0. [iOS 原生重构（本分支）](#-ios-原生重构本分支-customfeatures)
1. [How to Use](#-how-to-use)
2. [Download & Installation](#-download--installation)
3. [Mori CLI (Terminal)](#-mori-cli-terminal)
4. [Features](#-features)
5. [Supported Platforms & Scraper Engines](#-supported-platforms--scraper-engines)
6. [For Developers & Building from Source](#-for-developers--building-from-source)
7. [Scraper Architecture](#-scraper-architecture)

8. [Disclaimer](#-disclaimer)
9. [License & Terms of Use](#-license--terms-of-use)

---

## 🚀 How to Use

Saving media with Mori takes only three simple steps:

1. **Copy Link**: Copy any video, photo, or music link from your favorite app (TikTok, Instagram, YouTube, Spotify, etc.).
2. **Open Mori**: Mori automatically detects the link from your clipboard and analyzes it right away. _(On Android, you can also just tap **Share** on any post and choose **Mori** to download directly without leaving the app!)_
3. **Download**: Pick your preferred quality (HD video without watermarks, audio MP3, or photo gallery) and tap **Download**. Your media is saved straight to your device's gallery or music folder.

## 📥 Download & Installation

Pre-compiled, ready-to-use packages are available for all devices on **[GitHub Releases](https://github.com/coflyn/Mori/releases)** and **[npm](https://www.npmjs.com/package/@coflyn/mori)**.

| Platform                                                                                                                        | Available Packages                                                | Installation Guide                                                                  |
| :------------------------------------------------------------------------------------------------------------------------------ | :---------------------------------------------------------------- | :---------------------------------------------------------------------------------- |
| <img src="https://cdn.simpleicons.org/android/3DDC84" width="16" /> **Android**                                                 | `Mori v...apk`                                                    | [Installation & Play Protect Guide](GUIDE.md#android-installation--troubleshooting) |
| <img src="https://cdn.simpleicons.org/apple/000000" width="16" /> **iOS (native SwiftUI)**                                      | `Mori-v...-unsigned.ipa`                                          | [AltStore / TrollStore Sideloading](GUIDE.md#ios-sideloading-guide)                 |
| <img src="https://cdn.simpleicons.org/npm/CB3837" width="16" /> **CLI (Desktop & Server)**                                       | `npx @coflyn/mori`<br>`npm install -g @coflyn/mori`               | [Mori CLI Guide](#-mori-cli-terminal)                                               |

> 📖 **Need help installing or troubleshooting?**  
> Read the complete **[Installation, Sideloading & User Guide (GUIDE.md)](GUIDE.md)**.

> 💡 **Why Desktop GUI Deleted?**  
> Desktop GUI builds (`.dmg`, `.exe`, `.msi`) previously built with Tauri have been retired and consolidated into the standalone **Mori CLI** (`@coflyn/mori`).  
>
> - **Direct Execution via NPX**: Rather than downloading standalone installers and manually updating them, desktop users across macOS, Windows, and Linux can run Mori immediately on demand through `npx @coflyn/mori` or install it globally via `npm install -g @coflyn/mori`.
> - **No Gatekeeper & SmartScreen Blocks**: Uncertified desktop binaries frequently trigger false-positive security warnings on desktop operating systems—such as macOS Gatekeeper's *"Mori is damaged and can't be opened"* quarantine and Windows SmartScreen alerts. Shifting to an npm-distributed CLI completely bypasses these operating system hurdles without requiring users to run manual terminal bypass commands (`xattr -cr`).
> - **Focus on Mobile & Scraper Reliability**: Supporting four operating systems at once created unnecessary friction. Maintaining separate Rust toolchains and chasing desktop-specific GUI bugs took valuable time away from the core project. Retiring the desktop GUI allows development to focus entirely on polishing the mobile experience (Android & iOS) and keeping all 16 scraper engines fast and reliable.
> - **Full Feature Parity**: The CLI is not a reduced version. It retains full access to all 16 supported platforms, dual-engine scrapers, interactive REPL navigation, audio extraction, PDF compilation, and concurrent parallel downloads.

---

## 💻 Mori CLI (Terminal)

Prefer the command line? Mori is also available as a standalone terminal CLI powered by `@clack/prompts`:

<p align="center">
  <img src="assets/cli.webp" width="85%" alt="Mori CLI Preview">
</p>

```bash
# Run directly without installation
npx @coflyn/mori

# Download any link directly
npx @coflyn/mori <URL>

# Download audio stream only (MP3)
npx @coflyn/mori <URL> -a

# Compile photo album directly into PDF
npx @coflyn/mori <URL> -p
```

Or install globally:

```bash
npm install -g @coflyn/mori
mori
```

Key CLI capabilities:
- **Interactive REPL**: Arrow-key navigation, format selectors, and 21 slash commands (`/history`, `/play <num>`, `/delete <num>`, `/config`, `/stats`, `/update`, `/clear`, etc.).
- **Automatic Version Checker**: Non-blocking check on launch alerts you whenever a newer CLI release is published to npm.
- **Parallel Multi-Processing**: High-speed concurrent downloads for photo carousels and albums with clean single-row in-place progress.
- **OTA Scraper Hot-Patching & Dual Updates**: Pull engine patches directly via `mori --update` or `/update` without waiting for package updates.
- **Read the [CLI Documentation (cli/README.md)](cli/README.md)** for full CLI documentation and options reference.

## 📜 Features

- **16 Platforms in One App**: Save watermark-free videos, high-resolution photos, and audio from TikTok, Instagram, YouTube, Twitter/X, Spotify, Apple Music, Pinterest, Facebook, Threads, Bandcamp, Pixiv, Bilibili, Douyin, RedNote, Reddit, and TeraBox.
- **Over-The-Air (OTA) Scraper Hot-Patching**: Never wait for app updates when a platform changes its API. Mori seamlessly hot-patches scraper engines in the background without needing to reinstall the app.
- **Custom Directory & Storage Freedom**: Pick any folder across your device storage (including SD cards, Movies, Downloads, and custom folders) with native folder pickers and full file management support.
- **One-Tap Playlists & Albums**: Download full music albums or playlists from **Spotify**, **Apple Music**, and **YouTube** in one click instead of saving songs one by one.
- **High-Speed Concurrent Downloads**: Download music albums, playlists, and multi-photo galleries in parallel with up to 5 concurrent worker threads for blazing fast speeds.
- **Floating Download Bubble & Manager**: Non-intrusive monochrome floating bubble tracking active tasks in real-time with an aggregated progress ring, expandable dropup tray, individual task progress bars, and instant cancellation.
- **Quick Save via Android Share Menu**: Spot a video you love? Tap **Share** in any app and select Mori to download it instantly in a neat overlay without switching apps.
- **Multi-Link Batch Mode**: Paste several links at once and let Mori queue and download them all automatically in the background.
- **Built-in Custom Fullscreen Player & Preview**: Play videos, stream tracks, and browse photo carousels right inside the app with a sleek custom fullscreen player, real-time title bar, smooth seek scrubbing, double-tap seek, and mute controls.
- **Integrated Media Gallery**: Browse and play all saved videos, music, photos, and PDF documents directly within the app, complete with media filter chips, real-time search, sorting options, and an in-app viewer.
- **Instant Photo-to-PDF**: Combine photo galleries or multi-image posts into a single, clean PDF file for offline reading or sharing.
- **PIN & Biometric Lock**: Protect your download history, media gallery, and settings with an optional 4-digit PIN code or fingerprint / Face ID lock.
- **Clean Folder Organization**: Files are neatly organized in standard system folders (`Movies/Mori`, `Music/Mori`, `Pictures/Mori`) for easy access in your gallery.
- **Automatic Clipboard Detection**: Opening Mori automatically suggests your copied link for instant one-tap downloading.
- **Background Downloads**: Large videos and playlists keep downloading seamlessly even when you minimize the app or turn off the screen.
- **Anti-Corrupt File Protection**: Files are saved securely—media only appears in your gallery once 100% complete, preventing broken or unplayable files.
- **Modern Themes & Live Backgrounds**: Choose from elegant dark modes and interactive animated backgrounds (Stars, Waves, Fireflies).
- **9 Languages**: English, Indonesian, Japanese, Korean, Simplified Chinese, Arabic (with RTL support), Russian, Tagalog, and Hindi.
- **100% Private & Ad-Free**: No ads, no analytics, no accounts required, and zero external hosting. Everything runs on your device.

## 🌐 Supported Platforms & Scraper Engines

| Platform                                                                               | Supported Domains / Formats                                    | Features                     | Scraper Engine / Provider                                                               |
| :------------------------------------------------------------------------------------- | :------------------------------------------------------------- | :--------------------------- | :-------------------------------------------------------------------------------------- |
| <img src="https://cdn.simpleicons.org/instagram/E4405F" width="16" /> **Instagram**    | `instagram.com` (`/p/`, `/reel/`, `/stories/`)                 | Reels / Stories / Photos     | **InDown** (`indown.net`) & **SnapSave** (`snapsave.app`)                               |
| <img src="https://cdn.simpleicons.org/tiktok/000000" width="16" /> **TikTok**          | `tiktok.com`, `vt.tiktok.com`                                  | Video (No WM) / Slide Photos | **TikDownloader** (`tikdownloader.io`) & **TikTokIO** (`tiktokio.com`)                  |
| <img src="https://cdn.simpleicons.org/youtube/FF0000" width="16" /> **YouTube**        | `youtube.com`, `youtu.be`, `music.youtube.com`                 | Playlist / Album / MP4 / MP3 | **Ytmp3.gg** (`media.ytmp3.gg`) & **Ytmp3.mobi** (`ytmp3.mobi`)                         |
| <img src="https://cdn.simpleicons.org/x/000000" width="16" /> **Twitter (X)**          | `twitter.com`, `x.com`                                         | HD Video / GIFs              | **TwitterVideoDownloader** (`twittervideodownloader.com`) & **SaveTWT** (`savetwt.com`) |
| <img src="https://cdn.simpleicons.org/spotify/1DB954" width="16" /> **Spotify**        | `open.spotify.com` (`track`, `album`, `playlist`, `/s/`)       | Playlist / Album / MP3       | **SpotiDown** (`spotidown.app`) & **SoundLoaders** (`spotimate.app`)                    |
| <img src="https://cdn.simpleicons.org/applemusic/FA243C" width="16" /> **Apple Music** | `music.apple.com`                                              | Album / Playlist / MP3 Track | **AplMate** (`aplmate.com`)                                                             |
| <img src="https://cdn.simpleicons.org/pinterest/E60023" width="16" /> **Pinterest**    | `pinterest.com`, `pin.it`                                      | Video / HD Images            | Direct `pinimg.com` Parser & **PinDown** (`pindown.io`)                                 |
| <img src="https://cdn.simpleicons.org/facebook/1877F2" width="16" /> **Facebook**      | `facebook.com`, `fb.watch`                                     | Reels / HD Video             | **SnapSave** (`snapsave.app`)                                                           |
| <img src="https://cdn.simpleicons.org/xiaohongshu/FF2442" width="16" /> **RedNote**    | `xiaohongshu.com`, `xhslink.com`, `xhslink.cn`, `rednote.com`  | HD Photos / Videos           | Direct `__INITIAL_STATE__` SSR Extractor                                                |
| <img src="https://cdn.simpleicons.org/threads/000000" width="16" /> **Threads**        | `threads.com`                                                  | Video / Photo Carousel       | **Threadster** (`threadster.app`)                                                       |
| <img src="https://cdn.simpleicons.org/bilibili/00A1D6" width="16" /> **Bilibili**      | `bilibili.com`, `b23.tv`, `bili.im`, `bilibili.tv`             | Video / Audio (DASH 1080p)   | Direct Bilibili Web API (`api.bilibili.com` & `api.bilibili.tv`) & Wbi Resolver         |
| <img src="https://cdn.simpleicons.org/pixiv/0096FA" width="16" /> **Pixiv**            | `pixiv.net` (`artworks`)                                       | Gallery / Ugoira to MP4      | Direct Pixiv AJAX API & Ugoira Zip-to-MP4 Converter                                     |
| <img src="https://cdn.simpleicons.org/tiktok/000000" width="16" /> **Douyin**          | `douyin.com`, `v.douyin.com`                                   | Video (No WM) / Photos       | Direct `iesdouyin.com` API & Multi-Marker SSR Resolver                                  |
| <img src="https://cdn.simpleicons.org/bandcamp/1DA1F2" width="16" /> **Bandcamp**      | `*.bandcamp.com`                                               | Track / Album / MP3          | **BandcampDownloader** (`bandcampdownloader.app`)                                       |
| <img src="https://cdn.simpleicons.org/reddit/FF4500" width="16" /> **Reddit**          | `reddit.com`, `redd.it`                                        | HD Video (Audio) / Photos    | **RapidSave** (`rapidsave.com`)                                                         |
| <img src="https://cdn.simpleicons.org/box/0061D5" width="16" /> **TeraBox**            | `terabox.com`, `teraboxapp.com`, `1024tera.com`, `teraboxlink` | Direct File / Stream (m3u8)  | **Sechno** (`sechno.com`)                                                               |

## 🛠️ For Developers & Building from Source

Interested in customizing the interface, contributing translations, or compiling binaries locally?

👉 **[Contributing & Build Guide (CONTRIBUTING.md)](CONTRIBUTING.md)** — Complete prerequisites, environment setup, and compilation instructions for Android and iOS.  
📜 **[Release History & Changelog (CHANGELOG.md)](CHANGELOG.md)** — Detailed version-by-version release logs.

<details>
<summary><b>🔍 Click to view Tech Stack & Project Structure</b></summary>

### Built With

- **JavaScript (ES6+)**: Core application logic and client-side UI.
- **HTML5 & CSS3**: Custom responsive design system with dark mode and smooth animations.
- **SwiftUI (iOS)**: Fully native iOS app; the shared scraper core runs in a hidden WKWebView with a URLSession-backed HTTP bridge.
- **CapacitorJS (Android)**: Native Android bridge for filesystem, share sheet, clipboard, and biometrics.
- **OkHttp (Native Android)**: High-performance native HTTP engine to seamlessly bypass WebView CORS and network restrictions.
- **Cheerio & Axios**: Fast DOM HTML parsing and HTTP client request handling.
- **pdf-lib**: Client-side PDF generation and bundling.

### Project Structure

```
Mori/
├── android/                    # Capacitor Android native project
│   ├── app/src/main/
│   │   ├── java/com/mori/downloader/
│   │   │   ├── DownloadForegroundService.java # Background download persistent service & wake-lock
│   │   │   ├── MainActivity.java   # Main Activity + native HTTP bridge & 640px HD frame extractor
│   │   │   └── ShareActivity.java  # Native Quick Save Share overlay & MediaStore indexer
│   │   └── res/                # Android layout, drawables, XML configs & splash screens
│   └── gradle/                 # Gradle build scripts & configurations
├── ios/                        # Native SwiftUI iOS app (no Capacitor / CocoaPods)
│   ├── project.yml             # XcodeGen spec (bundles ../public/js/scrapers/bundle.js as a resource)
│   ├── Mori.xcodeproj          # Generated Xcode project
│   ├── build-ipa.sh            # Unsigned .ipa packaging script
│   └── Mori/
│       ├── App/                # App entry, tab root, app lock, URL scheme
│       ├── Engine/             # EngineHost.js (dispatcher + link resolver), WKWebView host, URLSession HTTP bridge, OTA store
│       ├── Download/           # Download queue, CDN headers, file naming, Photos saver, PDF exporter
│       ├── Models/             # Media result, platforms, settings, history & library stores
│       ├── Views/              # SwiftUI screens: Home, Result, Downloads, Gallery, History, Settings
│       ├── Utilities/          # Kingfisher image loading, JXPhotoBrowser presenter, system video player
│   └── MoriUITests/            # Screenshot UI walkthrough (XCUITest)
│       └── Resources/          # Info.plist, assets, en / zh-Hans localizations
├── cli/                        # Standalone Universal Media Downloader CLI (Node.js)
├── src-scrapers/               # Modular ES scraper engine source files (16 platforms)
├── scripts/                    # Build & compilation tooling
│   └── compile-scrapers.mjs    # esbuild compilation script for scrapers bundle & checksum manifest
├── landing/                    # Standalone promotional landing page & cross-platform download portal
│   ├── index.html              # Landing page markup & release download links
│   └── style.css               # Landing page responsive styling
├── assets/                     # App icons, mockups, & screenshots
├── public/                     # Frontend web assets (Vanilla JS + CSS)
│   ├── css/                    # Modular CSS architecture
│   │   ├── variables.css       # Design tokens, themes (dark/light), typography, glass, corner presets
│   │   ├── base.css            # CSS reset, typography, header, dynamic greeting, bottom navigation
│   │   ├── components.css      # Reusable buttons, custom toast, floating download bubble & dropup manager
│   │   ├── home.css            # URL input bar, batch textarea, skeleton loader, media preview cards, custom fullscreen
│   │   ├── gallery.css         # Media gallery grid, filtering chips, search toolbar, modal viewer, audio & PDF card
│   │   ├── history.css         # History layout, summary stats card, cards, actions bar, thumbnail overlay
│   │   ├── settings.css        # Settings menu list, sub-page slide transitions, custom dropdowns
│   │   ├── modals.css          # Modal overlays, PIN keypad, user guide, confirm & info dialogs
│   │   ├── rtl.css             # Right-to-Left (RTL) language overrides for Arabic [dir="rtl"]
│   │   └── style.css           # Master stylesheet entry point with sequential @import rules
│   ├── js/
│   │   ├── app.js              # Main application entry point & startup lifecycle
│   │   ├── components/         # Reusable UI components
│   │   │   └── player.js       # In-app media player (fullscreen overlay, dedicated volume toggle, unmute badge)
│   │   ├── downloader/         # Modular native download engine
│   │   │   ├── filename.js     # Extension resolution, title sanitization, template & folder logic
│   │   │   ├── headers.js      # Platform-specific Referer/Origin headers builder & URL unwrapper
│   │   │   ├── resolver.js     # Asynchronous link resolver (YouTube, Spotify, Apple Music, workers)
│   │   │   ├── storage.js      # Desktop/Mobile filesystem persistence, retry loops, temp cleanup
│   │   │   ├── postProcess.js  # MediaScanner, feedback haptics/audio, tray notifications, UI reset
│   │   │   └── index.js        # Barrel re-export for downloader sub-modules
│   │   ├── i18n/               # Multi-language translations (9 languages + RTL support)
│   │   │   ├── locales/        # Modular locale dictionaries (en, id, ja, ko, zh, ar, ru, tl, hi)
│   │   │   └── index.js        # Translation registry, t() helper, and fallback resolver
│   │   ├── modules/            # Core business logic & application state
│   │   │   ├── authManager.js  # PIN passcode & biometric lock system
│   │   │   ├── batchManager.js # Multi-link batch queue & playlist manager
│   │   │   ├── bgAnimation.js  # Interactive Live Canvas backgrounds (Stars, Waves, etc.)
│   │   │   ├── core.js         # Shared global state, DOM references, constants
│   │   │   ├── download.js     # Analysis pipeline & download controllers
│   │   │   ├── gallery.js      # Storage scanning, 640px HD thumbnails, favorites priority, PDF/audio viewer
│   │   │   ├── history.js      # Download history manager, local storage, & cleanup
│   │   │   ├── intents.js      # Auto-clipboard detection & native paste event listener
│   │   │   ├── modals.js       # Confirmation dialogs & information modals
│   │   │   ├── settings/       # Modular user settings & configuration subsystem
│   │   │   │   ├── nativeSync.js # Native SharedPreferences bridge & platform detection
│   │   │   │   ├── appearance.js # Themes (dark/light), color accents, fonts, & visual presets
│   │   │   │   ├── behavior.js   # Toggles (incognito, data saver, Wi-Fi only, keep awake, anti-403)
│   │   │   │   ├── storage.js    # Download subfolder pickers, cache cleanup, wipe data & stats
│   │   │   │   ├── language.js   # Dropdown select engine, i18n switcher, sub-page navigation
│   │   │   │   └── index.js      # Barrel re-export for settings sub-modules
│   │   │   ├── settings.js     # User preferences orchestrator & backward-compatible facade
│   │   │   ├── update.js       # Automatic GitHub release update checker
│   │   │   └── updateScrapers.js # OTA scraper hot-patch downloader & validator
│   │   ├── scrapers/           # Scraper runtime loader & HTTP helper
│   │   │   ├── bundle.js       # Bundled scraper core (esbuild IIFE, all 16 platforms)
│   │   │   ├── httpHelper.js   # Unified HTTP engine (native OkHttp/Capacitor bridge + UA rotation)
│   │   │   └── index.js        # Runtime loader with OTA hot-patch support
│   │   ├── ui/                 # UI rendering & presentation layer
│   │   │   ├── downloadBubble.js # Persistent floating download bubble & dropup task manager
│   │   │   ├── nativeDownload.js # Native download flow orchestrator & progress tracking
│   │   │   ├── result.js       # Analysis results view, media slider, & PDF creator
│   │   │   └── resultModal.js  # Detailed preview modal & folder path navigator
│   │   ├── share.js            # Android Quick Save Share Overlay controller
│   │   ├── ui.js               # History rendering & gesture handlers (long-press delete)
│   │   ├── utils/              # Helper utilities subsystem
│   │   │   ├── plugins.js      # Capacitor native plugin registry & auto-sync lifecycle
│   │   │   ├── http.js         # User-Agent presets, cookie parser, query serializer, error handler
│   │   │   ├── device.js       # Haptic feedback triggers, clipboard writer, wake lock, Wi-Fi guard
│   │   │   ├── toast.js        # Standard notification toasts & action feedback alerts
│   │   │   ├── sound.js        # Web Audio API procedural synthesizer & sound pack generator
│   │   │   ├── media.js        # Video canvas thumbnail generator & playback safe controls
│   │   │   ├── pdfHelper.js    # PDF generation & image bundling via pdf-lib
│   │   │   ├── urlUtils.js     # URL sanitization & tracking parameter remover
│   │   │   └── index.js        # Barrel re-exporter providing 100% backward compatibility
│   │   └── vendor/             # Bundled third-party libraries
│   │       ├── pdf-lib.min.js  # PDF creation & image bundling
│   │       ├── pdf.min.js      # Mozilla PDF.js offline rendering core
│   │       └── pdf.worker.min.js # PDF.js background worker for high-DPI canvas
│   ├── index.html              # Main single-page application markup
│   ├── scrapers-version.json   # Scraper bundle version & SHA256 checksum manifest
│   └── share.html              # Standalone Android Quick Save Share Overlay markup
├── capacitor.config.json       # Capacitor cross-platform configuration
├── package.json                # Project dependencies & build scripts
├── CHANGELOG.md                # Detailed version-by-version release history
├── CONTRIBUTING.md             # Developer setup, build guidelines, & PR instructions
├── GUIDE.md                    # In-app user manual & usage walkthrough
├── LICENSE                     # GNU General Public License v3.0
├── log.txt                     # Internal engineering development log
└── README.md                   # Primary project overview & documentation
```

</details>

## 🔧 Scraper Architecture

Mori's scraper core is bundled via esbuild into `public/js/scrapers/bundle.js` — a plain minified IIFE containing all 16 platform scrapers.

- **OTA Hot-Patching**: When a platform changes its API, Mori can silently download and apply an updated `bundle.js` from GitHub without requiring a full app update.
- **Native iOS host**: On iOS the same `bundle.js` is evaluated inside a hidden WKWebView. `ios/Mori/Engine/EngineHost.js` provides the `window.__moriDeps` utilities, a `CapacitorHttp`-compatible bridge to URLSession, platform routing and the download-link resolver, so the scrapers run unmodified.
- **Open Client Architecture**: The entire frontend, UI design system, and core app logic remain **100% open source under GPL-3.0**.
- **Collaborative Development**: Honest developers who want to improve scrapers or fix broken endpoints are always welcome to coordinate through [CONTRIBUTING.md](CONTRIBUTING.md).

## ⚖️ Disclaimer

- **Personal & Educational Use Only**: Mori is an open-source educational utility designed solely for personal media archiving and research. Users are solely responsible for complying with local copyright laws and the terms of service of source platforms.
- **Zero Media Hosting**: Mori does not host, stream, cache, or redistribute any media on external servers. All operations execute strictly on-demand directly on the user's local device.
- **Respect for Third-Party Providers**: Mori acts purely as a client-side wrapper querying publicly available web endpoints. If you are an operator or developer of an upstream service and wish to have your endpoint excluded or removed from Mori, please reach out via GitHub Issues or email (riazrepo@gmail.com), and we will promptly accommodate your request.

## 📄 License & Terms of Use

Mori is free and open-source software licensed under the **[GNU General Public License v3.0 (GPL-3.0)](LICENSE)**.

- **Copyleft Enforcement**: Anyone who modifies or distributes copies of this software is strictly required to provide the complete corresponding source code under the same GPL-3.0 license.
- **No Unauthorized Commercial Re-selling**: Packaging, rebranding, or distributing closed-source, paid, or monetized variants of Mori without honoring GPL-3.0 requirements violates copyright law and will be subject to official DMCA takedowns.
- **Trademark & Identity**: The name "Mori", app logo, and associated visual designs are the property of the original author. Derivative works must be clearly distinguished and must not claim affiliation with the original project.

---

Developed with ❤️ by coflyn.  
GitHub: https://github.com/coflyn  
Instagram: @\_coflyn
