#!/usr/bin/env python3
"""Проверяет, что все строки интерфейса из кода есть в таблице переводов.

Ключ — русский литерал в `tr("…")`/`trf("…")`. Скрипт ищет такие литералы в `Sources`
(кроме сгенерированного `Translations.swift`) и сверяет с `l10n/strings.tsv`.

Код возврата 1 — есть строки без перевода (это ошибка: в интерфейсе останется русский
текст при английском/немецком/испанском). Неиспользованные ключи — только предупреждение:
часть из них используется через наборы реплик, а не прямым вызовом.

Запуск: python3 scripts/check-l10n.py
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
tsv = root / "l10n/strings.tsv"

keys = []
rows = []
for line in tsv.read_text(encoding="utf-8").splitlines():
    if not line or line.startswith("#"):
        continue
    parts = line.split("\t")
    assert len(parts) == 4, line
    rows.append(parts)
    keys.append(parts[0])
def decode(raw: str) -> str:
    """В TSV переводы строк записаны как \\n — приводим к тому же виду, что и литерал в коде."""
    out = []
    i = 0
    while i < len(raw):
        ch = raw[i]
        if ch == "\\" and i + 1 < len(raw):
            nxt = raw[i + 1]
            mapping = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
            if nxt in mapping:
                out.append(mapping[nxt])
                i += 2
                continue
        out.append(ch)
        i += 1
    return "".join(out)

known = {decode(k) for k in keys}
# Пустой перевод — такая же ошибка, как отсутствующий: в интерфейсе окажется пустая подпись.
empty = [p[0] for p in rows if any(not cell.strip() for cell in p[1:])]

literal = re.compile(r'\btrf?\("((?:[^"\\]|\\.)*)"')
used: set[str] = set()
for path in sorted((root / "Sources").rglob("*.swift")):
    if path.name == "Translations.swift":
        continue
    text = path.read_text(encoding="utf-8")
    for match in literal.finditer(text):
        raw = match.group(1)
        # В исходниках литерал записан с экранированием, в TSV — как есть.
        value = (raw.replace('\\"', '"').replace("\\n", "\n")
                    .replace("\\t", "\t").replace("\\\\", "\\"))
        used.add(value)

missing = sorted(used - known)
if empty:
    print(f"Пустой перевод у {len(empty)} строк(и):")
    for text in empty:
        print("  •", text)
    sys.exit(1)
if missing:
    print(f"Нет перевода для {len(missing)} строк(и) из кода:")
    for text in missing:
        print("  •", text)
    print("Добавьте их в l10n/strings.tsv и запустите python3 scripts/gen-l10n.py")
    sys.exit(1)

unused = [k for k in keys if k not in used]
print(f"Строк в коде: {len(used)}, ключей в таблице: {len(keys)}, не встречаются напрямую: {len(unused)}")
