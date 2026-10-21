import XCTest
@testable import WorkLogCore

final class ProjectVisibilityTests: XCTestCase {
    private func withDefaults(_ work: (UserDefaults) throws -> Void) rethrows {
        let suite = "ProjectVisibilityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try work(defaults)
    }

    func testPersistsFullPathsAndRestoresProjectsIndividually() {
        withDefaults { defaults in
            var visibility = ProjectVisibility(defaults: defaults)
            XCTAssertTrue(visibility.hiddenPaths.isEmpty)
            visibility.setHidden(true, for: "/work/client-a/app")
            visibility.setHidden(true, for: "/work/client-b/app")
            visibility.setHidden(true, for: "/work/client-a/app")

            var reopened = ProjectVisibility(defaults: defaults)
            XCTAssertEqual(reopened.hiddenPaths.count, 2)
            reopened.setHidden(false, for: "/work/client-a/app")
            let again = ProjectVisibility(defaults: defaults)
            XCTAssertFalse(again.isHidden("/work/client-a/app"))
            XCTAssertTrue(again.isHidden("/work/client-b/app"))
        }
    }

    func testRestoreAllPreservesOtherPreferences() {
        withDefaults { defaults in
            defaults.set("ja", forKey: "appLanguage")
            var visibility = ProjectVisibility(defaults: defaults)
            visibility.setHidden(true, for: "/work/a")
            visibility.setHidden(true, for: "/work/b")
            visibility.showAll()
            XCTAssertTrue(ProjectVisibility(defaults: defaults).hiddenPaths.isEmpty)
            XCTAssertEqual(defaults.string(forKey: "appLanguage"), "ja")
        }
    }

    func testDemoDoesNotReadOrOverwriteSavedVisibility() {
        withDefaults { defaults in
            var saved = ProjectVisibility(defaults: defaults)
            saved.setHidden(true, for: "/real/project")
            var demo = ProjectVisibility(defaults: defaults, persists: false)
            XCTAssertTrue(demo.hiddenPaths.isEmpty)
            demo.setHidden(true, for: "/demo/project")
            demo.showAll()
            XCTAssertEqual(ProjectVisibility(defaults: defaults).hiddenPaths, ["/real/project"])
        }
    }
}
