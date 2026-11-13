import Foundation

/// Размерность физической величины — по ней единица измерения сопоставляется с величиной.
enum PhysicalDimension: String, Sendable, Hashable {
    case length, time, mass, speed, acceleration, force, energy, power, pressure, density
    case volume, area, temperature, voltage, current, resistance, charge, frequency
    case stiffness, momentum, specificHeat
}

/// Единица измерения с коэффициентом перевода в СИ.
struct PhysicalUnit: Sendable {
    let symbols: [String]
    let dimension: PhysicalDimension
    let factor: Double
}

/// Физическая величина: обозначение, единица СИ и слова, по которым её узнают в тексте.
struct PhysicalQuantity: Sendable {
    let id: String
    let symbol: String
    let dimension: PhysicalDimension
    let nameRu: String
    let nameEn: String
    let unitRu: String
    let unitEn: String
    /// Регулярные выражения (в нижнем регистре) для поиска величины в тексте.
    let keywords: [String]

    func name(_ l: L10n) -> String { l(nameRu, nameEn) }
    func unit(_ l: L10n) -> String { l(unitRu, unitEn) }
}

/// Формула из школьного курса. Переменные обозначены одной латинской буквой
/// (так их понимает математический парсер) и сопоставлены с величинами.
struct PhysicsFormula: Sendable {
    let display: String
    let nameRu: String
    let nameEn: String
    /// Буква в выражении → идентификатор величины.
    let variables: [String: String]
    /// Буква искомой величины → выражение для неё.
    let forms: [String: String]
}

/// Табличные свойства веществ.
struct Substance: Sendable {
    let pattern: String
    let nameRu: String
    let nameEn: String
    /// Удельная теплоёмкость, Дж/(кг·°C).
    let specificHeat: Double?
    /// Плотность, кг/м³.
    let density: Double?
}

enum PhysicsData {
    static let units: [PhysicalUnit] = [
        // Длина
        PhysicalUnit(symbols: ["км", "km"], dimension: .length, factor: 1000),
        PhysicalUnit(symbols: ["м", "m"], dimension: .length, factor: 1),
        PhysicalUnit(symbols: ["дм", "dm"], dimension: .length, factor: 0.1),
        PhysicalUnit(symbols: ["см", "cm"], dimension: .length, factor: 0.01),
        PhysicalUnit(symbols: ["мм", "mm"], dimension: .length, factor: 0.001),
        // Время
        PhysicalUnit(symbols: ["ч", "час", "часа", "часов", "h", "hr", "hour", "hours"], dimension: .time, factor: 3600),
        PhysicalUnit(symbols: ["мин", "минут", "минуты", "min", "minutes"], dimension: .time, factor: 60),
        PhysicalUnit(symbols: ["с", "сек", "секунд", "секунды", "s", "sec", "seconds"], dimension: .time, factor: 1),
        PhysicalUnit(symbols: ["мс", "ms"], dimension: .time, factor: 0.001),
        // Масса
        PhysicalUnit(symbols: ["т", "t"], dimension: .mass, factor: 1000),
        PhysicalUnit(symbols: ["кг", "kg"], dimension: .mass, factor: 1),
        PhysicalUnit(symbols: ["г", "g"], dimension: .mass, factor: 0.001),
        PhysicalUnit(symbols: ["мг", "mg"], dimension: .mass, factor: 1e-6),
        // Скорость
        PhysicalUnit(symbols: ["км/ч", "km/h", "kmh", "kph"], dimension: .speed, factor: 1000.0 / 3600.0),
        PhysicalUnit(symbols: ["м/с", "m/s"], dimension: .speed, factor: 1),
        PhysicalUnit(symbols: ["км/с", "km/s"], dimension: .speed, factor: 1000),
        PhysicalUnit(symbols: ["см/с", "cm/s"], dimension: .speed, factor: 0.01),
        // Ускорение
        PhysicalUnit(symbols: ["м/с²", "м/с^2", "м/с2", "m/s²", "m/s^2", "m/s2"], dimension: .acceleration, factor: 1),
        // Сила
        PhysicalUnit(symbols: ["кН", "kN"], dimension: .force, factor: 1000),
        PhysicalUnit(symbols: ["Н", "н", "N"], dimension: .force, factor: 1),
        PhysicalUnit(symbols: ["мН", "mN"], dimension: .force, factor: 0.001),
        // Энергия
        PhysicalUnit(symbols: ["МДж", "MJ"], dimension: .energy, factor: 1e6),
        PhysicalUnit(symbols: ["кДж", "кдж", "kJ"], dimension: .energy, factor: 1000),
        PhysicalUnit(symbols: ["Дж", "дж", "J"], dimension: .energy, factor: 1),
        // Мощность
        PhysicalUnit(symbols: ["МВт", "MW"], dimension: .power, factor: 1e6),
        PhysicalUnit(symbols: ["кВт", "квт", "kW"], dimension: .power, factor: 1000),
        PhysicalUnit(symbols: ["Вт", "вт", "W"], dimension: .power, factor: 1),
        // Давление
        PhysicalUnit(symbols: ["МПа", "MPa"], dimension: .pressure, factor: 1e6),
        PhysicalUnit(symbols: ["кПа", "кпа", "kPa"], dimension: .pressure, factor: 1000),
        PhysicalUnit(symbols: ["гПа", "hPa"], dimension: .pressure, factor: 100),
        PhysicalUnit(symbols: ["Па", "па", "Pa"], dimension: .pressure, factor: 1),
        // Плотность
        PhysicalUnit(symbols: ["кг/м³", "кг/м^3", "кг/м3", "kg/m³", "kg/m^3", "kg/m3"], dimension: .density, factor: 1),
        PhysicalUnit(symbols: ["г/см³", "г/см^3", "г/см3", "g/cm³", "g/cm^3", "g/cm3"], dimension: .density, factor: 1000),
        // Объём
        PhysicalUnit(symbols: ["м³", "м^3", "м3", "m³", "m^3", "m3"], dimension: .volume, factor: 1),
        PhysicalUnit(symbols: ["дм³", "дм^3", "дм3", "л", "l", "L"], dimension: .volume, factor: 0.001),
        PhysicalUnit(symbols: ["см³", "см^3", "см3", "мл", "cm³", "cm^3", "cm3", "ml"], dimension: .volume, factor: 1e-6),
        // Площадь
        PhysicalUnit(symbols: ["км²", "км^2", "км2", "km²", "km^2"], dimension: .area, factor: 1e6),
        PhysicalUnit(symbols: ["м²", "м^2", "м2", "m²", "m^2", "m2"], dimension: .area, factor: 1),
        PhysicalUnit(symbols: ["дм²", "дм^2", "дм2"], dimension: .area, factor: 0.01),
        PhysicalUnit(symbols: ["см²", "см^2", "см2", "cm²", "cm^2", "cm2"], dimension: .area, factor: 1e-4),
        PhysicalUnit(symbols: ["мм²", "мм^2", "мм2", "mm²", "mm^2"], dimension: .area, factor: 1e-6),
        // Температура (разность температур в °C и К совпадает)
        PhysicalUnit(symbols: ["°C", "°С", "°c", "°с", "°", "градусов", "градуса", "градус", "К", "K"], dimension: .temperature, factor: 1),
        // Электричество
        PhysicalUnit(symbols: ["кВ", "kV"], dimension: .voltage, factor: 1000),
        PhysicalUnit(symbols: ["В", "V"], dimension: .voltage, factor: 1),
        PhysicalUnit(symbols: ["мВ", "mV"], dimension: .voltage, factor: 0.001),
        PhysicalUnit(symbols: ["А", "A"], dimension: .current, factor: 1),
        PhysicalUnit(symbols: ["мА", "mA"], dimension: .current, factor: 0.001),
        PhysicalUnit(symbols: ["кОм", "ком", "kΩ", "kOhm"], dimension: .resistance, factor: 1000),
        PhysicalUnit(symbols: ["Ом", "ом", "Ω", "Ohm", "ohm", "ohms"], dimension: .resistance, factor: 1),
        PhysicalUnit(symbols: ["Кл", "кл", "C"], dimension: .charge, factor: 1),
        PhysicalUnit(symbols: ["мКл", "mC"], dimension: .charge, factor: 0.001),
        // Колебания
        PhysicalUnit(symbols: ["кГц", "kHz"], dimension: .frequency, factor: 1000),
        PhysicalUnit(symbols: ["Гц", "гц", "Hz"], dimension: .frequency, factor: 1),
        // Прочее
        PhysicalUnit(symbols: ["Н/м", "N/m"], dimension: .stiffness, factor: 1),
        PhysicalUnit(symbols: ["кг*м/с", "kg*m/s"], dimension: .momentum, factor: 1),
        PhysicalUnit(
            symbols: ["Дж/(кг*°C)", "Дж/(кг*°С)", "Дж/(кг*К)", "Дж/кг*°C", "Дж/кг*°С", "J/(kg*°C)", "J/(kg*K)"],
            dimension: .specificHeat, factor: 1),
    ]

    static let quantities: [PhysicalQuantity] = [
        PhysicalQuantity(
            id: "s", symbol: "s", dimension: .length, nameRu: "путь", nameEn: "distance", unitRu: "м", unitEn: "m",
            keywords: ["пут[ьи]", "расстоян\\w*", "прое[хз]\\w*", "прош[её]л\\w*", "пролет\\w*", "пробе[гж]\\w*", "проплы\\w*", "distance", "travel\\w*", "how far"]),
        PhysicalQuantity(
            id: "h", symbol: "h", dimension: .length, nameRu: "высота", nameEn: "height", unitRu: "м", unitEn: "m",
            keywords: ["высот\\w*", "глубин\\w*", "height", "depth", "how high", "how deep"]),
        PhysicalQuantity(
            id: "x", symbol: "x", dimension: .length, nameRu: "удлинение", nameEn: "extension", unitRu: "м", unitEn: "m",
            keywords: ["удлин\\w*", "растя\\w*", "сжат\\w*", "деформац\\w*", "extension", "stretch\\w*", "compress\\w*"]),
        PhysicalQuantity(
            id: "lam", symbol: "λ", dimension: .length, nameRu: "длина волны", nameEn: "wavelength", unitRu: "м", unitEn: "m",
            keywords: ["длин\\w* волны", "wavelength"]),
        PhysicalQuantity(
            id: "t", symbol: "t", dimension: .time, nameRu: "время", nameEn: "time", unitRu: "с", unitEn: "s",
            keywords: ["врем\\w*", "за какое", "как долго", "time", "how long"]),
        PhysicalQuantity(
            id: "T", symbol: "T", dimension: .time, nameRu: "период", nameEn: "period", unitRu: "с", unitEn: "s",
            keywords: ["период\\w*", "period"]),
        PhysicalQuantity(
            id: "m", symbol: "m", dimension: .mass, nameRu: "масса", nameEn: "mass", unitRu: "кг", unitEn: "kg",
            keywords: ["масс\\w*", "mass"]),
        PhysicalQuantity(
            id: "v0", symbol: "v₀", dimension: .speed, nameRu: "начальная скорость", nameEn: "initial speed", unitRu: "м/с", unitEn: "m/s",
            keywords: ["начальн\\w* скорост\\w*", "initial (?:speed|velocity)"]),
        PhysicalQuantity(
            id: "v", symbol: "v", dimension: .speed, nameRu: "скорость", nameEn: "speed", unitRu: "м/с", unitEn: "m/s",
            keywords: ["скорост\\w*", "speed", "velocity", "how fast"]),
        PhysicalQuantity(
            id: "a", symbol: "a", dimension: .acceleration, nameRu: "ускорение", nameEn: "acceleration", unitRu: "м/с²", unitEn: "m/s²",
            keywords: ["ускорен\\w*", "accelerat\\w*"]),
        PhysicalQuantity(
            id: "I", symbol: "I", dimension: .current, nameRu: "сила тока", nameEn: "current", unitRu: "А", unitEn: "A",
            keywords: ["сил\\w* тока", "ток\\w*", "current"]),
        PhysicalQuantity(
            id: "F", symbol: "F", dimension: .force, nameRu: "сила", nameEn: "force", unitRu: "Н", unitEn: "N",
            keywords: ["сил[аыуе]\\b", "силой", "сил\\b", "вес\\w*", "force", "weight"]),
        PhysicalQuantity(
            id: "Ek", symbol: "Eₖ", dimension: .energy, nameRu: "кинетическая энергия", nameEn: "kinetic energy", unitRu: "Дж", unitEn: "J",
            keywords: ["кинетическ\\w*", "kinetic"]),
        PhysicalQuantity(
            id: "Ep", symbol: "Eₚ", dimension: .energy, nameRu: "потенциальная энергия", nameEn: "potential energy", unitRu: "Дж", unitEn: "J",
            keywords: ["потенциальн\\w*", "potential"]),
        PhysicalQuantity(
            id: "Q", symbol: "Q", dimension: .energy, nameRu: "количество теплоты", nameEn: "heat", unitRu: "Дж", unitEn: "J",
            keywords: ["теплот\\w*", "тепла", "heat"]),
        PhysicalQuantity(
            id: "A", symbol: "A", dimension: .energy, nameRu: "работа", nameEn: "work", unitRu: "Дж", unitEn: "J",
            keywords: ["работ\\w*", "work"]),
        PhysicalQuantity(
            id: "N", symbol: "N", dimension: .power, nameRu: "мощность", nameEn: "power", unitRu: "Вт", unitEn: "W",
            keywords: ["мощност\\w*", "power"]),
        PhysicalQuantity(
            id: "p", symbol: "p", dimension: .pressure, nameRu: "давление", nameEn: "pressure", unitRu: "Па", unitEn: "Pa",
            keywords: ["давлен\\w*", "pressure"]),
        PhysicalQuantity(
            id: "rho", symbol: "ρ", dimension: .density, nameRu: "плотность", nameEn: "density", unitRu: "кг/м³", unitEn: "kg/m³",
            keywords: ["плотност\\w*", "density"]),
        PhysicalQuantity(
            id: "V", symbol: "V", dimension: .volume, nameRu: "объём", nameEn: "volume", unitRu: "м³", unitEn: "m³",
            keywords: ["объ[её]м\\w*", "volume"]),
        PhysicalQuantity(
            id: "S", symbol: "S", dimension: .area, nameRu: "площадь", nameEn: "area", unitRu: "м²", unitEn: "m²",
            keywords: ["площад\\w*", "area"]),
        PhysicalQuantity(
            id: "dT", symbol: "Δt", dimension: .temperature, nameRu: "изменение температуры", nameEn: "temperature change", unitRu: "°C", unitEn: "°C",
            keywords: ["на сколько градусов", "изменени\\w* температур\\w*", "temperature change"]),
        PhysicalQuantity(
            id: "U", symbol: "U", dimension: .voltage, nameRu: "напряжение", nameEn: "voltage", unitRu: "В", unitEn: "V",
            keywords: ["напряжен\\w*", "voltage"]),
        PhysicalQuantity(
            id: "R", symbol: "R", dimension: .resistance, nameRu: "сопротивление", nameEn: "resistance", unitRu: "Ом", unitEn: "Ω",
            keywords: ["сопротивлен\\w*", "resistance"]),
        PhysicalQuantity(
            id: "q", symbol: "q", dimension: .charge, nameRu: "заряд", nameEn: "charge", unitRu: "Кл", unitEn: "C",
            keywords: ["заряд\\w*", "charge"]),
        PhysicalQuantity(
            id: "nu", symbol: "ν", dimension: .frequency, nameRu: "частота", nameEn: "frequency", unitRu: "Гц", unitEn: "Hz",
            keywords: ["частот\\w*", "frequency"]),
        PhysicalQuantity(
            id: "k", symbol: "k", dimension: .stiffness, nameRu: "жёсткость", nameEn: "stiffness", unitRu: "Н/м", unitEn: "N/m",
            keywords: ["ж[её]сткост\\w*", "stiffness", "spring constant"]),
        PhysicalQuantity(
            id: "pm", symbol: "p", dimension: .momentum, nameRu: "импульс", nameEn: "momentum", unitRu: "кг·м/с", unitEn: "kg·m/s",
            keywords: ["импульс\\w*", "momentum"]),
        PhysicalQuantity(
            id: "c", symbol: "c", dimension: .specificHeat, nameRu: "удельная теплоёмкость", nameEn: "specific heat",
            unitRu: "Дж/(кг·°C)", unitEn: "J/(kg·°C)",
            keywords: ["тепло[её]мкост\\w*", "specific heat"]),
        PhysicalQuantity(
            id: "g", symbol: "g", dimension: .acceleration, nameRu: "ускорение свободного падения", nameEn: "gravitational acceleration",
            unitRu: "м/с²", unitEn: "m/s²", keywords: []),
    ]

    static let quantityByID: [String: PhysicalQuantity] = Dictionary(uniqueKeysWithValues: quantities.map { ($0.id, $0) })

    /// Обозначения в записи «m = 2 кг» → идентификатор величины.
    static let symbolToQuantity: [String: String] = [
        "m": "m", "v": "v", "v0": "v0", "v₀": "v0", "t": "t", "s": "s", "l": "s", "S": "S", "h": "h", "F": "F", "a": "a",
        "A": "A", "N": "N", "P": "N", "p": "p", "ρ": "rho", "V": "V", "U": "U", "I": "I", "R": "R", "q": "q", "Q": "Q",
        "k": "k", "c": "c", "T": "T", "λ": "lam", "ν": "nu", "x": "x", "g": "g",
    ]

    static let formulas: [PhysicsFormula] = [
        PhysicsFormula(
            display: "v = s/t", nameRu: "скорость равномерного движения", nameEn: "speed of uniform motion",
            variables: ["v": "v", "s": "s", "t": "t"], forms: ["v": "s/t", "s": "v*t", "t": "s/v"]),
        PhysicsFormula(
            display: "ρ = m/V", nameRu: "плотность вещества", nameEn: "density",
            variables: ["r": "rho", "m": "m", "V": "V"], forms: ["r": "m/V", "m": "r*V", "V": "m/r"]),
        PhysicsFormula(
            display: "F = m·a", nameRu: "второй закон Ньютона", nameEn: "Newton's second law",
            variables: ["F": "F", "m": "m", "a": "a"], forms: ["F": "m*a", "m": "F/a", "a": "F/m"]),
        PhysicsFormula(
            display: "F = m·g", nameRu: "сила тяжести", nameEn: "gravity force",
            variables: ["F": "F", "m": "m", "g": "g"], forms: ["F": "m*g", "m": "F/g"]),
        PhysicsFormula(
            display: "p = F/S", nameRu: "давление твёрдого тела", nameEn: "pressure",
            variables: ["p": "p", "F": "F", "S": "S"], forms: ["p": "F/S", "F": "p*S", "S": "F/p"]),
        PhysicsFormula(
            display: "p = ρ·g·h", nameRu: "давление столба жидкости", nameEn: "hydrostatic pressure",
            variables: ["p": "p", "r": "rho", "g": "g", "h": "h"], forms: ["p": "r*g*h", "h": "p/(r*g)", "r": "p/(g*h)"]),
        PhysicsFormula(
            display: "A = F·s", nameRu: "механическая работа", nameEn: "mechanical work",
            variables: ["A": "A", "F": "F", "s": "s"], forms: ["A": "F*s", "F": "A/s", "s": "A/F"]),
        PhysicsFormula(
            display: "N = A/t", nameRu: "мощность", nameEn: "power",
            variables: ["N": "N", "A": "A", "t": "t"], forms: ["N": "A/t", "A": "N*t", "t": "A/N"]),
        PhysicsFormula(
            display: "N = F·v", nameRu: "мощность при движении", nameEn: "power in motion",
            variables: ["N": "N", "F": "F", "v": "v"], forms: ["N": "F*v", "F": "N/v", "v": "N/F"]),
        PhysicsFormula(
            display: "Eₖ = m·v²/2", nameRu: "кинетическая энергия", nameEn: "kinetic energy",
            variables: ["K": "Ek", "m": "m", "v": "v"], forms: ["K": "m*v^2/2", "m": "2*K/v^2", "v": "sqrt(2*K/m)"]),
        PhysicsFormula(
            display: "Eₚ = m·g·h", nameRu: "потенциальная энергия", nameEn: "potential energy",
            variables: ["P": "Ep", "m": "m", "g": "g", "h": "h"], forms: ["P": "m*g*h", "h": "P/(m*g)", "m": "P/(g*h)"]),
        PhysicsFormula(
            display: "Q = c·m·Δt", nameRu: "количество теплоты при нагревании", nameEn: "heat for heating",
            variables: ["Q": "Q", "c": "c", "m": "m", "d": "dT"],
            forms: ["Q": "c*m*d", "m": "Q/(c*d)", "d": "Q/(c*m)", "c": "Q/(m*d)"]),
        PhysicsFormula(
            display: "I = U/R", nameRu: "закон Ома для участка цепи", nameEn: "Ohm's law",
            variables: ["I": "I", "U": "U", "R": "R"], forms: ["I": "U/R", "U": "I*R", "R": "U/I"]),
        PhysicsFormula(
            display: "P = U·I", nameRu: "мощность электрического тока", nameEn: "electric power",
            variables: ["N": "N", "U": "U", "I": "I"], forms: ["N": "U*I", "U": "N/I", "I": "N/U"]),
        PhysicsFormula(
            display: "A = U·I·t", nameRu: "работа электрического тока", nameEn: "work of electric current",
            variables: ["A": "A", "U": "U", "I": "I", "t": "t"], forms: ["A": "U*I*t", "U": "A/(I*t)", "I": "A/(U*t)", "t": "A/(U*I)"]),
        PhysicsFormula(
            display: "Q = I²·R·t", nameRu: "закон Джоуля — Ленца", nameEn: "Joule's law",
            variables: ["Q": "Q", "I": "I", "R": "R", "t": "t"],
            forms: ["Q": "I^2*R*t", "R": "Q/(I^2*t)", "t": "Q/(I^2*R)", "I": "sqrt(Q/(R*t))"]),
        PhysicsFormula(
            display: "I = q/t", nameRu: "сила тока", nameEn: "electric current",
            variables: ["I": "I", "q": "q", "t": "t"], forms: ["I": "q/t", "q": "I*t", "t": "q/I"]),
        PhysicsFormula(
            display: "a = (v − v₀)/t", nameRu: "ускорение", nameEn: "acceleration",
            variables: ["a": "a", "v": "v", "u": "v0", "t": "t"], forms: ["a": "(v-u)/t", "v": "u+a*t", "t": "(v-u)/a", "u": "v-a*t"]),
        PhysicsFormula(
            display: "s = a·t²/2", nameRu: "путь при равноускоренном движении из состояния покоя", nameEn: "distance under constant acceleration from rest",
            variables: ["s": "s", "a": "a", "t": "t"], forms: ["s": "a*t^2/2", "a": "2*s/t^2", "t": "sqrt(2*s/a)"]),
        PhysicsFormula(
            display: "h = g·t²/2", nameRu: "свободное падение", nameEn: "free fall",
            variables: ["h": "h", "g": "g", "t": "t"], forms: ["h": "g*t^2/2", "t": "sqrt(2*h/g)"]),
        PhysicsFormula(
            display: "λ = v/ν", nameRu: "длина волны", nameEn: "wavelength",
            variables: ["L": "lam", "v": "v", "n": "nu"], forms: ["L": "v/n", "v": "L*n", "n": "v/L"]),
        PhysicsFormula(
            display: "T = 1/ν", nameRu: "период и частота колебаний", nameEn: "period and frequency",
            variables: ["T": "T", "n": "nu"], forms: ["T": "1/n", "n": "1/T"]),
        PhysicsFormula(
            display: "F = k·x", nameRu: "закон Гука", nameEn: "Hooke's law",
            variables: ["F": "F", "k": "k", "x": "x"], forms: ["F": "k*x", "k": "F/x", "x": "F/k"]),
        PhysicsFormula(
            display: "p = m·v", nameRu: "импульс тела", nameEn: "momentum",
            variables: ["p": "pm", "m": "m", "v": "v"], forms: ["p": "m*v", "m": "p/v", "v": "p/m"]),
        PhysicsFormula(
            display: "F = ρ·g·V", nameRu: "сила Архимеда", nameEn: "buoyant force",
            variables: ["F": "F", "r": "rho", "g": "g", "V": "V"], forms: ["F": "r*g*V", "V": "F/(r*g)", "r": "F/(g*V)"]),
    ]

    static let substances: [Substance] = [
        Substance(pattern: "(?<![а-яё])вод(а|ы|у|е|ой)(?![а-яё])|\\bwater\\b", nameRu: "вода", nameEn: "water", specificHeat: 4200, density: 1000),
        Substance(pattern: "(?<![а-яё])(л[её]д|льда|льду|льдом)(?![а-яё])|\\bice\\b", nameRu: "лёд", nameEn: "ice", specificHeat: 2100, density: 900),
        Substance(pattern: "желез\\w*|\\biron\\b", nameRu: "железо", nameEn: "iron", specificHeat: 460, density: 7800),
        Substance(pattern: "(?<![а-яё])стал[ьи]|стальн\\w*|\\bsteel\\b", nameRu: "сталь", nameEn: "steel", specificHeat: 500, density: 7800),
        Substance(pattern: "алюмини\\w*|alumin\\w*", nameRu: "алюминий", nameEn: "aluminium", specificHeat: 920, density: 2700),
        Substance(pattern: "(?<![а-яё])мед[ьи]|медн\\w*|\\bcopper\\b", nameRu: "медь", nameEn: "copper", specificHeat: 400, density: 8900),
        Substance(pattern: "свин(ец|ца|цу|цом|цов\\w*)|\\blead\\b", nameRu: "свинец", nameEn: "lead", specificHeat: 140, density: 11300),
        Substance(pattern: "ртут\\w*|\\bmercury\\b", nameRu: "ртуть", nameEn: "mercury", specificHeat: 140, density: 13600),
        Substance(pattern: "керосин\\w*|kerosene", nameRu: "керосин", nameEn: "kerosene", specificHeat: 2100, density: 800),
        Substance(pattern: "(?<![а-яё])спирт\\w*|\\balcohol\\b", nameRu: "спирт", nameEn: "alcohol", specificHeat: 2500, density: 800),
        Substance(pattern: "бензин\\w*|gasoline|petrol", nameRu: "бензин", nameEn: "gasoline", specificHeat: nil, density: 710),
        Substance(pattern: "(?<![а-яё])золот\\w*|\\bgold\\b", nameRu: "золото", nameEn: "gold", specificHeat: 130, density: 19300),
        Substance(pattern: "серебр\\w*|\\bsilver\\b", nameRu: "серебро", nameEn: "silver", specificHeat: 250, density: 10500),
        Substance(pattern: "(?<![а-яё])воздух\\w*|\\bair\\b", nameRu: "воздух", nameEn: "air", specificHeat: 1000, density: 1.29),
        Substance(pattern: "кирпич\\w*|\\bbrick\\b", nameRu: "кирпич", nameEn: "brick", specificHeat: 880, density: 1800),
        Substance(pattern: "(?<![а-яё])стекл\\w*|\\bglass\\b", nameRu: "стекло", nameEn: "glass", specificHeat: 840, density: 2500),
    ]
}
