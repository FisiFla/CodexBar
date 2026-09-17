import AppKit
import CodexBarCore
import Foundation
import XCTest
@testable import CodexBar

/// Native rendering proof for #3709: when the env var is set, runs the real account-switch
/// scheduling path with menu card rendering enabled on a live AppKit process and captures
/// before/after PNGs of the usage card plus a transcript. Skipped in the normal suite.
@MainActor
final class StatusMenuCodexAccountSwitchNativeProofTests: XCTestCase {
    func test_accountSwitchRendersFetchedUsageInStillOpenCard() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let proofDirectory = environment["CODEXBAR_ACCOUNT_SWITCH_PROOF_DIR"] else {
            throw XCTSkip("Set CODEXBAR_ACCOUNT_SWITCH_PROOF_DIR to capture the native account-switch proof")
        }
        guard environment["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] == "1",
              environment["CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] != "1"
        else { return XCTFail("Native proof requires keychain prompt suppression") }

        StatusItemController.menuCardRenderingEnabled = true
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer { StatusItemController.setMenuRefreshEnabledForTesting(false) }

        let suite = "StatusMenuCodexAccountSwitchNativeProofTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        settings.multiAccountMenuLayout = .segmented
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(
                provider: provider,
                metadata: metadata,
                enabled: provider == .codex || provider == .claude)
        }

        let managedAccountID = try XCTUnwrap(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111"))
        let managedAccount = ManagedCodexAccount(
            id: managedAccountID,
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 2)
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let managedStore = FileManagedCodexAccountStore(fileURL: storeURL)
        try managedStore.storeAccounts(ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [managedAccount]))
        defer {
            settings._test_managedCodexAccountStoreURL = nil
            settings._test_liveSystemCodexAccount = nil
            try? FileManager.default.removeItem(at: storeURL)
        }

        settings._test_managedCodexAccountStoreURL = storeURL
        settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        settings.codexActiveSource = .liveSystem

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        store._setSnapshotForTesting(Self.snapshot(email: "live@example.com", percent: 11), provider: .codex)
        store.lastCodexAccountScopedRefreshGuard = store.currentCodexAccountScopedRefreshGuard(
            preferCurrentSnapshot: false)
        let blocker = AccountSwitchProofFetchBlocker()
        let baseSpec = try XCTUnwrap(store.providerSpecs[.codex])
        let strategy = AccountSwitchProofFetchStrategy(blocker: blocker)
        let baseDescriptor = baseSpec.descriptor
        let descriptor = ProviderDescriptor(
            id: .codex,
            metadata: baseDescriptor.metadata,
            branding: baseDescriptor.branding,
            tokenCost: baseDescriptor.tokenCost,
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .cli, .oauth],
                pipeline: ProviderFetchPipeline { _ in [strategy] }),
            cli: baseDescriptor.cli)
        store.providerSpecs[.codex] = ProviderSpec(
            style: baseSpec.style,
            isEnabled: baseSpec.isEnabled,
            descriptor: descriptor,
            makeFetchContext: baseSpec.makeFetchContext)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let switcher = try XCTUnwrap(menu.items.compactMap { $0.view as? CodexAccountSwitcherView }.first)
        let managedVisibleAccount = try XCTUnwrap(settings.codexVisibleAccountProjection.visibleAccounts
            .first { $0.storedAccountID == managedAccountID })

        // A hosted chart submenu the user opened after selecting the account must survive the
        // delayed rebuild.
        let submenu = controller.makeHostedSubviewPlaceholderMenu(
            chartID: StatusItemController.costHistoryChartID,
            provider: .codex)
        controller.openMenus[ObjectIdentifier(submenu)] = submenu

        var transcript: [String] = []
        func publishedEmail() -> String {
            store.snapshots[.codex]?.identity?.accountEmail ?? "<nil>"
        }

        transcript.append("before select: published email \(publishedEmail())")
        try Self.writePNG(
            Self.renderFirstMenuCardPNG(menu: menu, controller: controller),
            to: proofDirectory,
            name: "before-account-switch.png")
        transcript.append("before PNG captured")

        switcher._test_selectAccount(id: managedVisibleAccount.id)
        transcript.append("selected managed account; published email \(publishedEmail())")

        // Drain the pre-fetch rebuilds triggered by selection and the early refresh phases.
        let prefetchDeadline = ContinuousClock.now + .seconds(5)
        while controller.menuNeedsRefresh(menu), ContinuousClock.now < prefetchDeadline {
            await Task.yield()
        }
        transcript.append("pre-fetch drained: published email \(publishedEmail())")

        // The account-scoped fetch completes while the menu stays open.
        await blocker.waitUntilStarted()
        await blocker.resume(with: .success(Self.snapshot(email: "managed@example.com", percent: 17)))
        transcript.append("fetch resumed with managed@example.com snapshot (17%)")

        let rebuildDeadline = ContinuousClock.now + .seconds(5)
        while store.snapshots[.codex]?.identity?.accountEmail != "managed@example.com"
            || controller.menuNeedsRefresh(menu),
            ContinuousClock.now < rebuildDeadline
        {
            await Task.yield()
        }
        let submenuStillOpen = controller.openMenus[ObjectIdentifier(submenu)] === submenu
        transcript.append("after fetch: published email \(publishedEmail())")
        transcript.append("hosted submenu still open: \(submenuStillOpen)")

        try Self.writePNG(
            Self.renderFirstMenuCardPNG(menu: menu, controller: controller),
            to: proofDirectory,
            name: "after-account-switch.png")
        transcript.append("after PNG captured")

        try (transcript.joined(separator: "\n") + "\n").write(
            to: URL(fileURLWithPath: proofDirectory, isDirectory: true)
                .appendingPathComponent("transcript.txt"),
            atomically: true,
            encoding: .utf8)

        // The fetched usage for the new account must be published and rendered without closing
        // the menu, and the hosted submenu must not have been dismissed.
        XCTAssertEqual(publishedEmail(), "managed@example.com")
        XCTAssertTrue(menu.items.contains { $0.view != nil }, "usage card view must still be planted")
        XCTAssertTrue(submenuStillOpen, "open hosted submenu must survive the delayed rebuild")
    }

    private static func snapshot(email: String, percent: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: percent,
                windowMinutes: 300,
                resetsAt: Date().addingTimeInterval(300),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: percent,
                windowMinutes: 10080,
                resetsAt: Date().addingTimeInterval(86400),
                resetDescription: nil),
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: email,
                accountOrganization: nil,
                loginMethod: "Plus"))
    }

    private static func renderFirstMenuCardPNG(menu: NSMenu, controller: StatusItemController) -> Data? {
        controller.refreshMenuCardHeights(in: menu)
        for item in menu.items {
            guard let view = item.view else { continue }
            let width = max(view.fittingSize.width, StatusItemController.menuCardBaseWidth)
            let height = max(view.fittingSize.height, view.frame.height, 1)
            view.frame = CGRect(origin: .zero, size: NSSize(width: width, height: height))
            let window = NSWindow(
                contentRect: view.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            defer { window.contentView = nil; window.close() }
            window.layoutIfNeeded()
            view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: representation)
            return representation.representation(using: .png, properties: [:])
        }
        return nil
    }

    private static func writePNG(_ data: Data?, to proofDirectory: String, name: String) throws {
        let url = URL(fileURLWithPath: proofDirectory, isDirectory: true).appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        if let data {
            try data.write(to: url, options: .atomic)
        } else {
            try Data("render failed".utf8).write(to: url, options: .atomic)
        }
    }
}

@MainActor
private final class AccountSwitchProofFetchBlocker {
    private var waiters: [CheckedContinuation<Result<UsageSnapshot, Error>, Never>] = []
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var startCount = 0

    func awaitResult() async throws -> UsageSnapshot {
        let result = await withCheckedContinuation { continuation in
            self.waiters.append(continuation)
            self.startCount += 1
            for waiter in self.startedWaiters {
                waiter.resume()
            }
            self.startedWaiters.removeAll()
        }
        return try result.get()
    }

    func waitUntilStarted() async {
        if self.startCount > 0 { return }
        await withCheckedContinuation { continuation in
            self.startedWaiters.append(continuation)
        }
    }

    func resume(with result: Result<UsageSnapshot, Error>) {
        for waiter in self.waiters {
            waiter.resume(returning: result)
        }
        self.waiters.removeAll()
    }
}

private struct AccountSwitchProofFetchStrategy: ProviderFetchStrategy {
    let blocker: AccountSwitchProofFetchBlocker

    var id: String {
        "account-switch-proof-codex"
    }

    var kind: ProviderFetchKind {
        .cli
    }

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let snapshot = try await self.blocker.awaitResult()
        return self.makeResult(usage: snapshot, sourceLabel: "account-switch-proof-codex")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
