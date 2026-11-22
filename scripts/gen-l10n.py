#!/usr/bin/env python3
"""Собирает Sources/SinMinionsCore/Translations.swift из l10n/strings.tsv.

Формат TSV: ключ<TAB>en<TAB>de<TAB>es. Ключ — русский текст в том виде, как он записан
в исходниках (`\\n` — перевод строки, `%@` — подстановка). Запуск: python3 scripts/gen-l10n.py
"""
import pathlib

root = pathlib.Path(__file__).resolve().parent.parent
rows = []
for line in (root / "l10n/strings.tsv").read_text().splitlines():
    if not line or line.startswith("#"):
        continue
    parts = line.split("\t")
    assert len(parts) == 4, line
    assert all('"#' not in p for p in parts), line
    for translated in parts[1:]:
        assert translated.count("%@") == parts[0].count("%@"), line
    rows.append(parts)

body = "\n".join("\t".join(r) for r in rows)
swift = f'''// Создано scripts/gen-l10n.py из l10n/strings.tsv — правьте TSV и запускайте скрипт.
import Foundation

/// Переводы строк интерфейса и реплик: ключ — русский текст.
enum Translations {{
    static let en = column(1)
    static let de = column(2)
    static let es = column(3)

    private static func column(_ index: Int) -> [String: String] {{
        var result: [String: String] = [:]
        for line in table.split(separator: "\\n") {{
            let parts = line.split(separator: "\\t", omittingEmptySubsequences: false)
            guard parts.count == 4 else {{ continue }}
            result[unescape(parts[0])] = unescape(parts[index])
        }}
        return result
    }}

    private static func unescape(_ text: Substring) -> String {{
        text.replacingOccurrences(of: "\\\\n", with: "\\n")
    }}

    private static let table = #"""
{body}
"""#
}}
'''
(root / "Sources/SinMinionsCore/Translations.swift").write_text(swift)
print(f"{len(rows)} строк")
