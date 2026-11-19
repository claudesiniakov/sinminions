import Foundation

/// Гимн стража: строки, которые он поёт по очереди.
public enum Anthem {
    public static let lines: [String] = [
        "Мы не просим наград, мы не просим венца,",
        "нам не нужно ни звёзд, ни щедрот, ни дворца,",
        "мы живём за одно — за движенье лица,",
        "за одну полутень на лице. До конца.",
        "За улыбку! За знак! За молчанье — в бой!",
    ]

    /// Сколько секунд длится одна строка на экране.
    public static let secondsPerLine: Double = 4.4

    /// Общая длина песни, секунды.
    public static var duration: Double { Double(lines.count) * secondsPerLine + 1 }
}
