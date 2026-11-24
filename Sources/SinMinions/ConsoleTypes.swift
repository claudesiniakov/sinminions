import AppKit
import SwiftUI
import Observation
import IOKit.ps
import SinMinionsCore

// Типы терминала и монитора: пункты меню, замеры системы, события окон, S.P.E.C.I.A.L., записи чата.
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

/// Строка списка подключений для блока лимитов.
struct LLMConnectionRow: Identifiable, Equatable {
    let connection: LLMConnection
    let isActive: Bool
    var id: UUID { connection.id }
}

/// Окна среднего режима.
enum ConsoleWindow { case terminal, monitor }

enum GesturePhase { case began, changed, ended }

/// Что пользователь делает с окном: замок, перемещение за заголовок, изменение размера за уголок.
enum LayoutEvent {
    case toggleLock
    case move(GesturePhase)
    case resize(GesturePhase)
}

/// Характеристики призрака, как в Fallout. Работают S (размер), P (облик), C (частота реплик), E (сон),
/// I (подключение к нейросети) и A (скорость полёта); L пока без назначения.
enum SpecialStat: Int, CaseIterable, Identifiable {
    case strength, perception, endurance, charisma, intelligence, agility, luck
    var id: Int { rawValue }
    var letter: String { ["S", "P", "E", "C", "I", "A", "L"][rawValue] }
    var title: String {
        [tr("СИЛА"), tr("ВОСПРИЯТИЕ"), tr("ВЫНОСЛИВОСТЬ"), tr("ХАРИЗМА"), tr("ИНТЕЛЛЕКТ"), tr("ЛОВКОСТЬ"), tr("УДАЧА")][rawValue]
    }
    var isActive: Bool { self == .strength || self == .perception || self == .endurance || self == .intelligence || self == .agility || self == .charisma }
}

/// Значения характеристик для экрана S.P.E.C.I.A.L.
struct SpecialState: Equatable {
    var scaleLevel = 1
    var scaleLabel = tr("РАЗМЕР 1,5×")
    var perceptionLevel = 0
    var perceptionLabel = tr("ОБЛИК: КЛАССИЧЕСКИЙ")
    var agilityLevel = Agility.defaultLevel
    var agilityLabel = tr("ОБЫЧНО")
    var enduranceLevel = 1
    var enduranceLabel = tr("ЗАСЫПАЕТ ЧЕРЕЗ 5 МИН")
    var charismaLevel = Charisma.defaultLevel
    var charismaLabel = tr("ОБЫЧНО (2–5 МИН)")
    var intelligenceLabel = "—"
    var intelligenceCount = 0
}

enum ChatEntryKind { case user, assistant, error, info }

struct ChatEntry: Identifiable, Equatable {
    let id = UUID()
    let kind: ChatEntryKind
    let text: String
    /// Кто ответил (для реплик модели): название провайдера на момент ответа.
    var speaker: String? = nil
}
