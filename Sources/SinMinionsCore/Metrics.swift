import Foundation
import Darwin

public struct InterfaceCounters: Equatable, Sendable {
    public var rx: UInt64
    public var tx: UInt64

    public init(rx: UInt64 = 0, tx: UInt64 = 0) {
        self.rx = rx
        self.tx = tx
    }
}

public enum NetworkCounters {
    /// 64-битные счётчики байтов по всем интерфейсам (sysctl NET_RT_IFLIST2).
    public static func counters() -> [String: InterfaceCounters] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }

        var result: [String: InterfaceCounters] = [:]
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE) + 1)
                    if if_indextoname(UInt32(info.ifm_index), &name) != nil {
                        result[String(cString: name)] = InterfaceCounters(
                            rx: info.ifm_data.ifi_ibytes,
                            tx: info.ifm_data.ifi_obytes
                        )
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    /// Сумма по физическим интерфейсам (Wi-Fi, Ethernet): туннели и служебные не считаем,
    /// иначе один и тот же трафик попадёт в сумму дважды.
    public static func physicalTotal(_ counters: [String: InterfaceCounters]) -> InterfaceCounters {
        counters.reduce(into: InterfaceCounters()) { total, entry in
            guard entry.key.hasPrefix("en") else { return }
            total.rx += entry.value.rx
            total.tx += entry.value.tx
        }
    }

    /// Скорость в байтах в секунду между двумя замерами; сброс счётчика даёт 0.
    public static func rate(from old: InterfaceCounters, to new: InterfaceCounters, seconds: Double) -> (rx: Double, tx: Double) {
        guard seconds > 0 else { return (0, 0) }
        let rx = new.rx >= old.rx ? Double(new.rx - old.rx) : 0
        let tx = new.tx >= old.tx ? Double(new.tx - old.tx) : 0
        return (rx / seconds, tx / seconds)
    }
}

/// Счётчики процессорного времени с момента загрузки.
public struct CPUTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// Доля занятого времени между двумя замерами, 0…1; nil — замеры совпали или счётчик сбросился.
    public static func usage(from old: CPUTicks, to new: CPUTicks) -> Double? {
        guard new.user >= old.user, new.system >= old.system, new.idle >= old.idle, new.nice >= old.nice else { return nil }
        let busy = (new.user - old.user) + (new.system - old.system) + (new.nice - old.nice)
        let total = busy + (new.idle - old.idle)
        guard total > 0 else { return nil }
        return Double(busy) / Double(total)
    }
}

/// Текстовые индикаторы в стиле терминала.
public enum Gauge {
    /// Полоса из закрашенных и пустых клеток: `██████░░░░`.
    public static func bar(_ fraction: Double, width: Int = 10) -> String {
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        let filled = Int((clamped * Double(width)).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    public static func percent(_ fraction: Double) -> String {
        let clamped = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        return "\(Int((clamped * 100).rounded()))%"
    }
}

public enum MetricFormat {
    static func number(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// «12,4 ГБ», «810 МБ», «15 КБ».
    public static func bytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b >= 1e9 { return number(b / 1e9) + tr(" ГБ") }
        if b >= 1e6 { return String(Int((b / 1e6).rounded())) + tr(" МБ") }
        return String(Int((b / 1e3).rounded())) + tr(" КБ")
    }

    /// Скорость: «1,2 МБ/с», «340 КБ/с», «0 КБ/с».
    public static func rate(_ bytesPerSecond: Double) -> String {
        let b = max(bytesPerSecond, 0)
        if b >= 1e6 { return number(b / 1e6) + tr(" МБ/с") }
        return String(Int((b / 1e3).rounded())) + tr(" КБ/с")
    }

    /// Время работы: «3д 04ч», «4ч 12м», «12м».
    public static func uptime(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        let days = total / 86400, hours = total % 86400 / 3600, minutes = total % 3600 / 60
        if days > 0 { return trf("%@д ", "\(days)") + String(format: "%02d", hours) + tr("ч") }
        if hours > 0 { return trf("%@ч ", "\(hours)") + String(format: "%02d", minutes) + tr("м") }
        return trf("%@м", "\(minutes)")
    }
}
