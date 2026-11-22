import Foundation

/// Чистая логика обычного терминала: приглашение, встроенная «cd», очистка вывода от управляющих кодов.
public enum ShellText {
    /// Приглашение как в Терминале macOS: «user@host ~/Projects %».
    public static func prompt(user: String, host: String, cwd: String, home: String) -> String {
        "\(user)@\(host) \(abbreviate(cwd, home: home)) %"
    }

    /// «/Users/me/Projects» → «~/Projects».
    public static func abbreviate(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Аргумент встроенной «cd»; nil — строка не «cd». Пустая строка — в домашнюю папку.
    public static func cdArgument(_ line: String) -> String? {
        let text = line.trimmingCharacters(in: .whitespaces)
        if text == "cd" { return "" }
        guard text.hasPrefix("cd ") else { return nil }
        // «cd x && y», «cd x; y» — уже не просто смена папки: отдаём оболочке целиком.
        if text.contains("&&") || text.contains(";") || text.contains("|") { return nil }
        var argument = text.dropFirst(3).trimmingCharacters(in: .whitespaces)
        if argument.count >= 2, let first = argument.first, first == argument.last, first == "\"" || first == "'" {
            argument = String(argument.dropFirst().dropLast())
        }
        return argument.replacingOccurrences(of: "\\ ", with: " ")
    }

    /// Куда перейти по «cd»: «~», «-», относительный и абсолютный путь. Результат — нормализованный путь.
    public static func resolve(_ argument: String, cwd: String, home: String, previous: String?) -> String {
        let target: String
        switch argument {
        case "", "~": target = home
        case "-": target = previous ?? cwd
        default:
            if argument.hasPrefix("~/") {
                target = home + argument.dropFirst(1)
            } else if argument.hasPrefix("/") {
                target = argument
            } else {
                target = cwd + "/" + argument
            }
        }
        return normalize(target)
    }

    /// Убирает «.», «..» и повторные «/».
    public static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Убирает цветовые и прочие управляющие последовательности ANSI и возвраты каретки.
    public static func stripANSI(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()
        while let scalar = pending {
            pending = iterator.next()
            if scalar == "\u{1B}" {
                // CSI: ESC [ … буква; OSC: ESC ] … BEL или ESC \; прочее: ESC и один символ.
                guard let kind = pending else { break }
                pending = iterator.next()
                if kind == "[" {
                    while let next = pending {
                        pending = iterator.next()
                        if (0x40...0x7E).contains(next.value) { break }
                    }
                } else if kind == "]" {
                    while let next = pending {
                        pending = iterator.next()
                        if next == "\u{07}" { break }
                        if next == "\u{1B}" { pending = iterator.next(); break }
                    }
                }
                continue
            }
            if scalar == "\r" || scalar == "\u{07}" { continue }
            if scalar == "\u{08}" {
                if !result.isEmpty { result.removeLast() }
                continue
            }
            result.unicodeScalars.append(scalar)
        }
        return result
    }
}
