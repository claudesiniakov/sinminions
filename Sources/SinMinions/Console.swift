import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

/// Команды терминала среднего режима.
enum ConsoleCommand: Int, CaseIterable, Identifiable {
    case spotlight, nap, hide, corner, settings
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .spotlight: return "ПОИСК SPOTLIGHT"
        case .nap: return "УСЫПИТЬ НА 1 ЧАС"
        case .hide: return "СКРЫТЬ"
        case .corner: return "ВЕРНУТЬ В УГОЛ"
        case .settings: return "НАСТРОЙКИ"
        }
    }
}

/// Замер состояния Mac для окна мониторинга.
struct SystemSnapshot: Equatable {
    var cpu: Double?
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var battery: Int?
    var onAC = false
    var netDown: Double = 0
    var netUp: Double = 0
    var uptime: Double = 0
    var thermal: ProcessInfo.ThermalState = .nominal
}

/// Читает простые метрики системы; скорости считаются между соседними замерами.
@MainActor
final class SystemMonitor {
    private var lastTicks: CPUTicks?
    private var lastNet: InterfaceCounters?
    private var lastTime: Double?

    func reset() {
        lastTicks = nil
        lastNet = nil
        lastTime = nil
    }

    func sample() -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        let time = ProcessInfo.processInfo.systemUptime

        let ticks = Self.cpuTicks()
        if let old = lastTicks, let ticks { snapshot.cpu = CPUTicks.usage(from: old, to: ticks) }
        lastTicks = ticks

        let net = NetworkCounters.physicalTotal(NetworkCounters.counters())
        if let old = lastNet, let before = lastTime {
            let rate = NetworkCounters.rate(from: old, to: net, seconds: time - before)
            snapshot.netDown = rate.rx
            snapshot.netUp = rate.tx
        }
        lastNet = net
        lastTime = time

        snapshot.memoryTotal = ProcessInfo.processInfo.physicalMemory
        snapshot.memoryUsed = Self.memoryUsed() ?? 0

        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let total = values.volumeTotalCapacity, let free = values.volumeAvailableCapacityForImportantUsage {
            snapshot.diskTotal = UInt64(max(total, 0))
            snapshot.diskUsed = UInt64(max(Int64(total) - free, 0))
        }

        if let power = Self.battery() {
            snapshot.battery = power.percent
            snapshot.onAC = power.onAC
        }
        snapshot.uptime = time
        snapshot.thermal = ProcessInfo.processInfo.thermalState
        return snapshot
    }

    private static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // Порядок состояний: user, system, idle, nice.
        let t = info.cpu_ticks
        return CPUTicks(user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    }

    /// Занятая память: активные, закреплённые и сжатые страницы.
    private static func memoryUsed() -> UInt64? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(max(sysconf(_SC_PAGESIZE), 0))
        let pages = UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * page
    }

    private static func battery() -> (percent: Int, onAC: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery" else { continue }
            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = description["Max Capacity"] as? Int ?? 100
            let onAC = description["Power Source State"] as? String == "AC Power"
            return (maximum > 0 ? current * 100 / maximum : current, onAC)
        }
        return nil
    }
}

@MainActor
@Observable
final class ConsoleModel {
    var selected = 0
    var snapshot = SystemSnapshot()
    @ObservationIgnored var run: (ConsoleCommand) -> Void = { _ in }

    func move(_ delta: Int) {
        let count = ConsoleCommand.allCases.count
        selected = (selected + delta + count) % count
    }

    func runSelected() {
        if let command = ConsoleCommand(rawValue: selected) { run(command) }
    }
}

// MARK: - Оформление терминала

private enum Term {
    static let green = Color(nsColor: CompanionView.Palette.green)
    static let dim = Color(nsColor: CompanionView.Palette.greenDim)
    static let dark = Color(nsColor: CompanionView.Palette.greenDark)
    static let background = Color(nsColor: CompanionView.Palette.rgb(0x0b0f0a))
    static let font = Font.system(size: 13, design: .monospaced)
    static let small = Font.system(size: 11, design: .monospaced)
}

/// Рамка окна терминала: тёмный фон, зелёная рамка, строки развёртки, заголовок.
private struct TerminalFrame<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Term.small)
                .tracking(1)
                .foregroundStyle(Term.dim)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            Rectangle().fill(Term.dark).frame(height: 1)
            content
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Term.background.opacity(0.96))
        .overlay {
            Canvas { context, size in
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.22)))
                    y += 3
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(Rectangle().strokeBorder(Term.dim, lineWidth: 1))
        .shadow(color: Term.green.opacity(0.35), radius: 8)
        .padding(10)
    }
}

struct TerminalView: View {
    var model: ConsoleModel

    var body: some View {
        TerminalFrame(title: "MOTH-OS // ТЕРМИНАЛ") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(ConsoleCommand.allCases) { command in
                    let active = model.selected == command.rawValue
                    HStack(spacing: 8) {
                        Text(active ? ">" : " ")
                        Text(command.title)
                        Spacer(minLength: 0)
                    }
                    .font(Term.font)
                    .foregroundStyle(active ? Term.background : Term.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(active ? Term.green : Color.clear)
                    .shadow(color: active ? .clear : Term.green.opacity(0.5), radius: 3)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { model.selected = command.rawValue }
                    }
                    .onTapGesture {
                        model.selected = command.rawValue
                        model.runSelected()
                    }
                }
                Spacer(minLength: 6)
                Text("↑↓ ВЫБОР · ENTER · ESC ВЫХОД")
                    .font(Term.small)
                    .foregroundStyle(Term.dim)
            }
        }
    }
}

struct MonitorView: View {
    var model: ConsoleModel

    private func fraction(_ part: UInt64, _ whole: UInt64) -> Double {
        whole > 0 ? Double(part) / Double(whole) : 0
    }

    private var thermal: String {
        switch model.snapshot.thermal {
        case .nominal: return "НОРМА"
        case .fair: return "ПОВЫШЕН"
        case .serious: return "ВЫСОКИЙ"
        case .critical: return "КРИТИЧЕСКИЙ"
        @unknown default: return "—"
        }
    }

    private func gauge(_ label: String, _ value: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                Spacer(minLength: 4)
                Text(value)
            }
            Text(Gauge.bar(fraction, width: 30))
                .foregroundStyle(Term.dim)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 4)
            Text(value)
        }
    }

    var body: some View {
        let s = model.snapshot
        TerminalFrame(title: "СИСТЕМА // МОНИТОР") {
            VStack(alignment: .leading, spacing: 9) {
                gauge("ЦП", s.cpu.map { Gauge.percent($0) } ?? "…", s.cpu ?? 0)
                gauge("ПАМЯТЬ", "\(MetricFormat.bytes(s.memoryUsed)) / \(MetricFormat.bytes(s.memoryTotal))",
                      fraction(s.memoryUsed, s.memoryTotal))
                gauge("ДИСК", "\(MetricFormat.bytes(s.diskUsed)) / \(MetricFormat.bytes(s.diskTotal))",
                      fraction(s.diskUsed, s.diskTotal))
                if let battery = s.battery {
                    gauge(s.onAC ? "БАТАРЕЯ ⚡" : "БАТАРЕЯ", "\(battery)%", Double(battery) / 100)
                }
                Rectangle().fill(Term.dark).frame(height: 1)
                line("СЕТЬ ↓", MetricFormat.rate(s.netDown))
                line("СЕТЬ ↑", MetricFormat.rate(s.netUp))
                line("НАГРЕВ", thermal)
                line("В РАБОТЕ", MetricFormat.uptime(s.uptime))
            }
            .font(Term.small)
            .foregroundStyle(Term.green)
            .shadow(color: Term.green.opacity(0.45), radius: 3)
        }
    }
}

// MARK: - Окна

/// Окно терминала: принимает клавиатуру, не активируя приложение.
final class ConsolePanel: NSPanel {
    var onKey: (UInt16) -> Bool = { _ in false }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !onKey(event.keyCode) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        _ = onKey(53)
    }
}

/// Терминал и монитор среднего режима.
@MainActor
final class ConsoleController: NSObject, NSWindowDelegate {
    /// Размеры окон вместе с полями под свечение (10 pt с каждой стороны).
    static let terminalSize = CGSize(width: 400, height: 250)
    static let monitorWidth: CGFloat = 300
    static let monitorMinHeight: CGFloat = 330

    let model = ConsoleModel()
    private let terminal: ConsolePanel
    private let monitor: NSPanel
    private let sampler = SystemMonitor()
    private var timer: Timer?
    private(set) var isOpen = false

    var onCommand: (ConsoleCommand) -> Void = { _ in }
    /// Esc или щелчок мимо терминала.
    var onDismiss: () -> Void = {}

    override init() {
        terminal = ConsolePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        monitor = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        for panel in [terminal, monitor] {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.alphaValue = 0
        }
        monitor.ignoresMouseEvents = true
        terminal.contentView = NSHostingView(rootView: TerminalView(model: model))
        monitor.contentView = NSHostingView(rootView: MonitorView(model: model))
        terminal.delegate = self
        terminal.onKey = { [weak self] code in self?.handleKey(code) ?? false }
        model.run = { [weak self] command in self?.onCommand(command) }
    }

    func setCollectionBehavior(_ behavior: NSWindow.CollectionBehavior) {
        terminal.collectionBehavior = behavior
        monitor.collectionBehavior = behavior
    }

    func open(terminalFrame: CGRect, monitorFrame: CGRect) {
        isOpen = true
        model.selected = 0
        sampler.reset()
        model.snapshot = sampler.sample()
        terminal.setFrame(terminalFrame, display: true)
        monitor.setFrame(monitorFrame, display: true)
        monitor.orderFrontRegardless()
        terminal.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            terminal.animator().alphaValue = 1
            monitor.animator().alphaValue = 1
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isOpen else { return }
                self.model.snapshot = self.sampler.sample()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        timer?.invalidate()
        timer = nil
        terminal.alphaValue = 0
        monitor.alphaValue = 0
        terminal.orderOut(nil)
        monitor.orderOut(nil)
    }

    private func handleKey(_ code: UInt16) -> Bool {
        guard isOpen else { return false }
        switch code {
        case 126: model.move(-1)
        case 125: model.move(1)
        case 36, 76: model.runSelected()
        case 53: onDismiss()
        default: return false
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        if isOpen { onDismiss() }
    }
}
