import SwiftUI
import Combine

/// Drives the `SessionCollector` on a background timer and publishes snapshots to the UI.
@MainActor
final class StatsStore: ObservableObject {
    @Published var stats: DashStats = .empty
    @Published var loaded: Bool = false
    @Published var metrics: NotchMetrics
    @Published var hover: Bool = false            // cursor is over the widget
    @Published var dashboardHeight: CGFloat = 380 // measured expanded body height
    @Published var updateAvailable: String? = nil // latest release tag if newer than us
    var onMenu: (() -> Void)?                     // in-widget "⋯" button → show control menu
    @Published var mode: WidgetMode = WidgetMode(rawValue:
        UserDefaults.standard.string(forKey: "seeubot.mode") ?? "") ?? .hanging {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "seeubot.mode") }
    }

    func toggleMode() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { mode = mode.next }
    }

    // Only ever touched on `queue`, so accessing it off the main actor is safe.
    nonisolated(unsafe) private let collector = SessionCollector()
    private let queue = DispatchQueue(label: "seeubot.collector", qos: .utility)
    // Drop a tick if a previous collect() is still running (only touched on `queue`).
    nonisolated(unsafe) private var collecting = false
    private var timer: Timer?
    private let interval: TimeInterval

    init(interval: TimeInterval = 3, metrics: NotchMetrics) {
        self.interval = interval
        self.metrics = metrics
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func updateMetrics(_ m: NotchMetrics) { metrics = m }

    nonisolated private func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            // Skip if the previous collect hasn't finished — prevents a serial-queue
            // backlog if a probe is ever slow.
            if self.collecting { return }
            self.collecting = true
            defer { self.collecting = false }
            let snapshot = self.collector.collect()
            Task { @MainActor in
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                    self.stats = snapshot
                }
                self.loaded = true
            }
        }
    }

    deinit { timer?.invalidate() }
}
