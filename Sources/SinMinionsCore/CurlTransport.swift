import Foundation

/// Запасной транспорт: запросы к GigaChat через системный `curl`.
///
/// Встроенный сетевой клиент macOS 27 обрывает рукопожатие с серверами GigaChat уже после успешной
/// проверки сертификата, а `curl` с тем же корнем Минцифры соединяется. Секреты передаются curl
/// через стандартный ввод (`--config -`), а не аргументами, поэтому в списке процессов их не видно.
/// `--cacert` оставляет доверенным только корень Минцифры — для этих хостов этого достаточно.
public enum CurlTransport {
    public struct Failure: Error, Equatable {
        public let exitCode: Int32
        public let message: String
    }

    /// Коды выхода curl, при которых имеет смысл попробовать другой транспорт (ошибки TLS и сертификата).
    public static let tlsExitCodes: Set<Int32> = [35, 51, 53, 54, 58, 59, 60, 64, 66, 77, 80, 82, 83, 90, 91]

    /// Строка в двойных кавычках конфигурационного файла curl.
    static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default: result.append(character)
            }
        }
        return result
    }

    public static func config(for request: URLRequest, caFile: String) -> String {
        var lines = [
            "silent",
            "show-error",
            "tlsv1.2",
            "proto = \"=https\"",
            "max-time = \(Int(request.timeoutInterval.rounded()))",
            "cacert = \"\(escape(caFile))\"",
            "url = \"\(escape(request.url?.absoluteString ?? ""))\"",
            "request = \"\(escape(request.httpMethod ?? "GET"))\"",
        ]
        for (name, value) in (request.allHTTPHeaderFields ?? [:]).sorted(by: { $0.key < $1.key }) {
            lines.append("header = \"\(escape(name + ": " + value))\"")
        }
        if let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
            // data-raw, а не data: значение, начинающееся с «@», не читается как имя файла.
            lines.append("data-raw = \"\(escape(text))\"")
        }
        lines.append("write-out = \"\\n%{http_code}\"")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Вывод curl: тело ответа, перевод строки и код ответа.
    static func parse(_ output: Data) -> (body: Data, status: Int)? {
        guard let newline = output.lastIndex(of: 0x0A),
              let text = String(data: output[output.index(after: newline)...], encoding: .utf8),
              let status = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return (output[output.startIndex..<newline], status)
    }

    /// Файл с корнем Минцифры в папке приложения (доступ только владельцу); при расхождении переписывается.
    static func caFile() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = base.appendingPathComponent("SinMinions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let file = directory.appendingPathComponent("russian_trusted_root_ca.pem")
        let wanted = Data(RussianTrustedRoot.pem.utf8)
        if (try? Data(contentsOf: file)) != wanted {
            try wanted.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        return file
    }

    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var cancelled = false

        func set(_ process: Process) {
            lock.lock()
            self.process = process
            let stop = cancelled
            lock.unlock()
            if stop { process.terminate() }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let current = process
            lock.unlock()
            current?.terminate()
        }
    }

    public static func run(_ request: URLRequest) async throws -> (Data, Int) {
        let file: URL
        do {
            file = try caFile()
        } catch {
            throw Failure(exitCode: -1, message: tr("не удалось подготовить сертификат: ") + error.localizedDescription)
        }
        let config = config(for: request, caFile: file.path)
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try execute(config: config, box: box) })
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    private static func execute(config: String, box: ProcessBox) throws -> (Data, Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["--config", "-"]
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            throw Failure(exitCode: -1, message: tr("curl не запустился: ") + error.localizedDescription)
        }
        box.set(process)
        try? input.fileHandleForWriting.write(contentsOf: Data(config.utf8))
        try? input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let line = errorText.split(separator: "\n").first.map(String.init) ?? tr("без пояснения")
            throw Failure(exitCode: process.terminationStatus, message: line)
        }
        guard let parsed = parse(data) else { throw Failure(exitCode: -2, message: tr("неожиданный вывод curl")) }
        return (parsed.body, parsed.status)
    }
}
