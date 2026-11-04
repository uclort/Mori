import XCTest

/// Screenshot walkthrough of the main flows. Screenshots go to $MORI_UI_SHOTS (default /tmp/mori-ui).
final class MoriUITests: XCTestCase {
    private var app: XCUIApplication!

    private var shotDir: String {
        ProcessInfo.processInfo.environment["MORI_UI_SHOTS"] ?? "/tmp/mori-ui"
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"] + extra
        app.launch()
    }

    private func shot(_ name: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
    }

    private func pause(_ s: TimeInterval) { _ = XCTWaiter.wait(for: [expectation(description: "pause")], timeout: s) }

    func test1_Home() {
        launch()
        pause(2)
        shot("home_empty")
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("https://www.tiktok.com/@a/video/1\nhttps://www.instagram.com/p/x")
        app.staticTexts["Mori"].firstMatch.tap()   // dismiss keyboard by tapping elsewhere
        pause(1)
        shot("home_two_links")
    }

    func test2_ResultGrid() {
        launch(["-moriTestURL", "demo:photos"])
        let first = app.descendants(matching: .any)["photo-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        pause(4)
        shot("result_grid")
        // Corner download button on the 2nd photo
        let downloadButtons = app.buttons.matching(identifier: "photo-download")
        if downloadButtons.count > 1 { downloadButtons.element(boundBy: 1).tap() }
        pause(0.6)
        shot("result_grid_downloading")
        pause(0.6)
        shot("result_grid_downloaded_check")
        pause(2.5)
        shot("result_grid_download_reverted")
        first.tap()
        pause(0.12)
        shot("photo_browser_zoom")
        pause(3)
        shot("photo_browser")
        let dl = app.buttons["下载"].firstMatch
        if dl.waitForExistence(timeout: 3) { dl.tap() }
        pause(1)
        shot("photo_browser_download_tapped")
    }

    func test3_GalleryDelete() {
        launch(["-moriTab", "gallery"])
        pause(3)
        shot("gallery_top")
        let cells = app.descendants(matching: .any).matching(identifier: "gallery-cell")
        guard cells.count >= 2 else { return XCTFail("gallery needs files") }
        // Long-press → context menu → delete → confirmation anchored to the cell
        cells.element(boundBy: 0).press(forDuration: 1.2)
        pause(1)
        shot("gallery_context_menu")
        let del = app.buttons["删除"].firstMatch
        if del.waitForExistence(timeout: 3) { del.tap() }
        pause(1.5)
        shot("gallery_cell_delete_confirm")
        // Popovers have no Cancel button — tap outside to dismiss
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).tap()
        pause(1.5)

        app.buttons["选择"].firstMatch.tap()
        if !app.buttons["完成"].waitForExistence(timeout: 2) {
            app.buttons["选择"].firstMatch.tap()
        }
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 3))
        pause(1)
        cells.element(boundBy: 0).tap()
        cells.element(boundBy: 1).tap()
        pause(1)
        shot("gallery_selecting")
        app.descendants(matching: .any)["gallery-actions"].firstMatch.tap()
        pause(1)
        shot("gallery_actions_menu")
        let menuDelete = app.buttons["删除"].firstMatch
        if menuDelete.waitForExistence(timeout: 3) { menuDelete.tap() }
        pause(1.5)
        shot("gallery_selection_delete_confirm")
    }

    /// The home toolbar indicator must flip back to the download icon as soon as
    /// the queue empties (child item changes used to be swallowed).
    func test5_HomeToolbar() {
        launch(["-moriTestURL", "demo:photos"])
        let all = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "下载全部")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        pause(3)
        all.tap()
        pause(0.25)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(0.2)
        shot("home_toolbar_downloading")
        pause(1.2)
        shot("home_toolbar_mid")
        pause(8)
        shot("home_toolbar_8s")
        pause(12)
        shot("home_toolbar_20s")
        app.navigationBars.buttons.firstMatch.tap()
        pause(1.5)
        shot("downloads_sheet")
    }

    /// "Open in Files" should leave the app for the Files app (or explain why not).
    func test6_OpenInFiles() {
        launch(["-moriTab", "settings"])
        pause(2)
        let folderButton = app.buttons["在「文件」中打开"]
        XCTAssertTrue(folderButton.waitForExistence(timeout: 5))
        folderButton.tap()
        pause(3)
        shot("files_app")
    }

    /// Open and close the photo browser so the zoom transition can be recorded.
    func test7_ZoomTransition() {
        launch(["-moriTestURL", "demo:photos"])
        let first = app.descendants(matching: .any)["photo-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        pause(5)
        // Tap close
        app.descendants(matching: .any)["photo-1"].tap()
        pause(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        pause(1.5)
        // Pull-down close
        app.descendants(matching: .any)["photo-4"].tap()
        pause(1.5)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.8)))
        pause(1.5)
    }

    func test4_SettingsDelete() {        launch(["-moriTab", "settings"])
        pause(2)
        shot("settings_top")
        let folderButton = app.buttons["在「文件」中打开"]
        if !folderButton.waitForExistence(timeout: 2) { app.swipeUp() }
        shot("settings_download_section")
        let button = app.buttons["删除全部已下载文件"]
        var tries = 0
        while !button.isHittable && tries < 8 { app.swipeUp(); tries += 1 }
        button.tap()
        pause(1.5)
        shot("settings_delete_confirm")
    }
}
