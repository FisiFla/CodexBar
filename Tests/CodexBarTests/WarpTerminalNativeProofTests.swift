#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import CodexBar

@Suite("Warp terminal native proof", .serialized)
struct WarpTerminalNativeProofTests {
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["CODEXBAR_WARP_TERMINAL_PROOF_DIR"] != nil
            && ProcessInfo.processInfo.environment["CODEXBAR_WARP_PROOF_STAGE"] == nil,
        "Set CODEXBAR_WARP_TERMINAL_PROOF_DIR to run live Warp proof"))
    @MainActor
    func `cold and running Warp execute commands and clean configs`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let proofDirectory = try URL(fileURLWithPath: #require(
            environment["CODEXBAR_WARP_TERMINAL_PROOF_DIR"]), isDirectory: true)
        try FileManager.default.createDirectory(
            at: proofDirectory,
            withIntermediateDirectories: true)

        let bundleIdentifier = TerminalApp.warp.bundleIdentifier
        let applicationURL = try #require(
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier))
        let configDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".warp/tab_configs", isDirectory: true)
        let baselineConfigs = Self.generatedConfigs(in: configDirectory)
        try #require(environment["CI"] == "true", "Run this proof only on the disposable CI runner")

        let initialReceipt = """
        # Warp terminal native proof

        - Feature head: `\(environment["CODEXBAR_WARP_FEATURE_HEAD"] ?? "unknown")`
        - Warp bundle identifier: `\(bundleIdentifier)`
        - Warp application: `\(applicationURL.path)`
        - Runner profile primed: pending
        - Cold-start result: pending
        - Already-running result: pending
        - Generated configs remaining after cleanup: pending
        """
        try initialReceipt.write(
            to: proofDirectory.appendingPathComponent("receipt.md"),
            atomically: true,
            encoding: .utf8)

        // A brand-new Warp profile may still be initializing when its first URI arrives.
        // Open it once without a URI, then terminate it before exercising the cold-start route.
        let primingConfiguration = NSWorkspace.OpenConfiguration()
        primingConfiguration.activates = true
        _ = try await NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: primingConfiguration)
        try await Self.waitUntil(timeout: .seconds(20)) {
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }
        try await Task.sleep(for: .seconds(8))
        _ = Self.captureScreen(to: proofDirectory.appendingPathComponent("warp-profile-prime.png"))

        for application in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            _ = application.terminate()
            if !application.isTerminated {
                _ = application.forceTerminate()
            }
        }
        try await Self.waitUntil(timeout: .seconds(20)) {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
        }

        let coldMarker = proofDirectory.appendingPathComponent("cold-start.txt")
        let warmMarker = proofDirectory.appendingPathComponent("already-running.txt")
        let coldValue = "cold-start-ok-\(UUID().uuidString)"
        let warmValue = "already-running-ok \"quoted\" 'apostrophe' \\ slash — \(UUID().uuidString)"

        let launcher = TerminalLauncher()
        let coldResult = await launcher.launch(
            .warp,
            command: Self.markerCommand(value: coldValue, destination: coldMarker))
        #expect(coldResult == .selected)
        try await Task.sleep(for: .seconds(5))
        _ = Self.captureScreen(to: proofDirectory.appendingPathComponent("warp-cold-start.png"))
        try Self.captureGeneratedConfigs(
            in: configDirectory,
            baseline: baselineConfigs,
            to: proofDirectory,
            prefix: "cold")
        do {
            try await Self.waitForMarker(coldMarker, expected: coldValue, timeout: .seconds(55))
        } catch {
            _ = Self.captureScreen(to: proofDirectory.appendingPathComponent("warp-cold-timeout.png"))
            throw error
        }

        let coldApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        #expect(coldApplications.count == 1)
        let configsAfterCold = Self.generatedConfigs(in: configDirectory).subtracting(baselineConfigs)
        #expect(configsAfterCold.count <= 1)

        let warmResult = await launcher.launch(
            .warp,
            command: Self.markerCommand(value: warmValue, destination: warmMarker))
        #expect(warmResult == .selected)
        try await Self.waitForMarker(warmMarker, expected: warmValue, timeout: .seconds(60))

        let warmApplications = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        #expect(warmApplications.count == 1)
        #expect(warmApplications.first?.processIdentifier == coldApplications.first?.processIdentifier)
        let configsAfterWarm = Self.generatedConfigs(in: configDirectory).subtracting(baselineConfigs)
        #expect(!configsAfterWarm.isEmpty)
        #expect(configsAfterWarm.subtracting(configsAfterCold).count == 1)

        let screenshotURL = proofDirectory.appendingPathComponent("warp-already-running.png")
        let screenshotStatus = Self.captureScreen(to: screenshotURL)
        #expect(screenshotStatus == 0)

        try await Self.waitUntil(timeout: .seconds(80)) {
            Self.generatedConfigs(in: configDirectory).subtracting(baselineConfigs).isEmpty
        }

        let coldMarkerValue = try String(contentsOf: coldMarker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let warmMarkerValue = try String(contentsOf: warmMarker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let receipt = """
        # Warp terminal native proof

        - Feature head: `\(environment["CODEXBAR_WARP_FEATURE_HEAD"] ?? "unknown")`
        - Warp bundle identifier: `\(bundleIdentifier)`
        - Warp application: `\(applicationURL.path)`
        - Runner profile primed: yes (no-login onboarding complete)
        - Cold-start result: `\(coldResult)`
        - Cold-start marker: `\(coldMarkerValue)`
        - Cold-start Warp PID count: `\(coldApplications.count)`
        - Already-running result: `\(warmResult)`
        - Already-running marker: `\(warmMarkerValue)`
        - Already-running Warp PID count: `\(warmApplications.count)`
        - Generated configs observed: `\(configsAfterWarm.map(\.lastPathComponent).sorted().joined(separator: ", "))`
        - Generated configs remaining after cleanup: `0`
        - Screenshot command exit: `\(screenshotStatus)`
        """
        try receipt.write(
            to: proofDirectory.appendingPathComponent("receipt.md"),
            atomically: true,
            encoding: .utf8)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXBAR_WARP_PROOF_STAGE"] == "leave"))
    @MainActor
    func `interrupted process leaves a real routed config`() async throws {
        let environment = ProcessInfo.processInfo.environment
        try #require(environment["CI"] == "true")
        let output = try URL(fileURLWithPath: #require(environment["CODEXBAR_WARP_TERMINAL_PROOF_DIR"]))
        let marker = output.appendingPathComponent("interrupted-marker.txt")
        #expect(await TerminalLauncher().launch(.warp, command: Self.markerCommand(
            value: "interrupted-launch-ok", destination: marker)) == .selected)
        try await Self.waitForMarker(marker, expected: "interrupted-launch-ok", timeout: .seconds(45))
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".warp/tab_configs")
        #expect(!Self.generatedConfigs(in: directory).isEmpty)
        // Return before the cleanup timer; this test process exits between workflow stages.
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEXBAR_WARP_PROOF_STAGE"] == "cleanup"))
    @MainActor
    func `next process cleans an interrupted launch`() async throws {
        let environment = ProcessInfo.processInfo.environment
        try #require(environment["CI"] == "true")
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".warp/tab_configs")
        let leftovers = Self.generatedConfigs(in: directory)
        try #require(!leftovers.isEmpty, "The prior process must leave a config behind")
        TerminalLauncher().cleanUpAbandonedConfigs()
        try await Self.waitUntil(timeout: .seconds(75)) {
            leftovers.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
        }
        let output = try URL(fileURLWithPath: #require(environment["CODEXBAR_WARP_TERMINAL_PROOF_DIR"]))
        try "Interrupted-process cleanup passed\n".write(
            to: output.appendingPathComponent("restart-receipt.txt"), atomically: true, encoding: .utf8)
    }

    private static func generatedConfigs(in directory: URL) -> Set<URL> {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil)) ?? []
        return Set(files.filter {
            $0.pathExtension == "toml" && $0.deletingPathExtension().lastPathComponent.hasPrefix("codexbar_")
        })
    }

    private static func markerCommand(value: String, destination: URL) -> String {
        "printf '%s\\n' \(self.shellQuote(value)) > \(self.shellQuote(destination.path))"
    }

    private static func captureGeneratedConfigs(
        in directory: URL,
        baseline: Set<URL>,
        to proofDirectory: URL,
        prefix: String) throws
    {
        let configs = self.generatedConfigs(in: directory).subtracting(baseline)
        for (index, config) in configs.sorted(by: { $0.path < $1.path }).enumerated() {
            let destination = proofDirectory.appendingPathComponent("\(prefix)-config-\(index).toml")
            try FileManager.default.copyItem(at: config, to: destination)
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func waitForMarker(_ url: URL, expected: String, timeout: Duration) async throws {
        try await self.waitUntil(timeout: timeout) {
            guard let value = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return value.trimmingCharacters(in: .whitespacesAndNewlines) == expected
        }
    }

    @MainActor
    private static func waitUntil(
        timeout: Duration,
        predicate: @MainActor () -> Bool) async throws
    {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !predicate() {
            if clock.now >= deadline {
                throw ProofError.timeout
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func captureScreen(to url: URL) -> Int32 {
        guard let processID = NSRunningApplication.runningApplications(
            withBundleIdentifier: TerminalApp.warp.bundleIdentifier).first?.processIdentifier,
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
            let window = windows.first(where: {
                ($0[kCGWindowOwnerPID as String] as? Int32) == processID
                    && ($0[kCGWindowLayer as String] as? Int) == 0
            }),
            let windowID = window[kCGWindowNumber as String] as? UInt32
        else { return 1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l", String(windowID), url.path]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch { return -1 }
    }

    private enum ProofError: Error {
        case timeout
    }
}
#endif
