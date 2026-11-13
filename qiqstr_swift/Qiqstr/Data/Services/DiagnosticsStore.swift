import Foundation
import MetricKit
import Observation

nonisolated struct DiagnosticReport: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case diagnostics, metrics }

    var id: String { file.lastPathComponent }
    var file: URL
    var kind: Kind
    var receivedAt: Date
    var crashes: Int
    var hangs: Int
    var other: Int
}

@MainActor
@Observable
final class DiagnosticsStore: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsStore()

    private static let limit = 30

    private(set) var reports: [DiagnosticReport] = []

    @ObservationIgnored private var isActive = false

    nonisolated static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        MXMetricManager.shared.add(self)
        Self.save(diagnostics: MXMetricManager.shared.pastDiagnosticPayloads)
        reload()
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        reports = urls.compactMap(Self.report(at:)).sorted { $0.receivedAt > $1.receivedAt }
    }

    func delete(_ report: DiagnosticReport) {
        try? FileManager.default.removeItem(at: report.file)
        reload()
    }

    func deleteAll() {
        reports.forEach { try? FileManager.default.removeItem(at: $0.file) }
        reload()
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        Self.save(diagnostics: payloads)
        Task { @MainActor in self.reload() }
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            Self.write(payload.jsonRepresentation(), kind: .metrics, date: payload.timeStampEnd, counts: (0, 0, 0))
        }
        Self.prune()
        Task { @MainActor in self.reload() }
    }

    nonisolated private static func save(diagnostics payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let other = (payload.cpuExceptionDiagnostics?.count ?? 0) + (payload.diskWriteExceptionDiagnostics?.count ?? 0) + (payload.appLaunchDiagnostics?.count ?? 0)
            write(payload.jsonRepresentation(), kind: .diagnostics, date: payload.timeStampEnd, counts: (crashes, hangs, other))
        }
        prune()
    }

    nonisolated private static func write(_ data: Data, kind: DiagnosticReport.Kind, date: Date, counts: (Int, Int, Int)) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Int(date.timeIntervalSince1970)
        let name = "\(kind.rawValue)-\(stamp)-\(counts.0)-\(counts.1)-\(counts.2).json"
        let url = directory.appendingPathComponent(name)
        guard !fm.fileExists(atPath: url.path) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    nonisolated private static func prune() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let sorted = urls.compactMap(report(at:)).sorted { $0.receivedAt > $1.receivedAt }
        sorted.dropFirst(limit).forEach { try? FileManager.default.removeItem(at: $0.file) }
    }

    nonisolated private static func report(at url: URL) -> DiagnosticReport? {
        guard url.pathExtension == "json" else { return nil }
        let parts = url.deletingPathExtension().lastPathComponent.split(separator: "-").map(String.init)
        guard parts.count == 5, let kind = DiagnosticReport.Kind(rawValue: parts[0]), let stamp = Double(parts[1]),
              let crashes = Int(parts[2]), let hangs = Int(parts[3]), let other = Int(parts[4]) else { return nil }
        return DiagnosticReport(file: url, kind: kind, receivedAt: Date(timeIntervalSince1970: stamp), crashes: crashes, hangs: hangs, other: other)
    }
}
