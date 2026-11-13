import Foundation

/// Химический элемент.
struct ChemicalElement: Sendable {
    let number: Int
    let symbol: String
    /// Относительная атомная масса (стандартное значение).
    let mass: Double
    let nameRu: String
    let nameEn: String

    func name(_ l: L10n) -> String { l(nameRu, nameEn) }

    /// Округлённая «школьная» атомная масса: целое число, для хлора — 35,5.
    var schoolMass: Rational {
        if symbol == "Cl" { return (try? Rational(71, 2)) ?? Rational(35) }
        return Rational(Int(mass.rounded()))
    }
}

/// Периодическая система: 118 элементов.
enum PeriodicTable {
    static let elements: [ChemicalElement] = [
        ChemicalElement(number: 1, symbol: "H", mass: 1.008, nameRu: "Водород", nameEn: "Hydrogen"),
        ChemicalElement(number: 2, symbol: "He", mass: 4.003, nameRu: "Гелий", nameEn: "Helium"),
        ChemicalElement(number: 3, symbol: "Li", mass: 6.94, nameRu: "Литий", nameEn: "Lithium"),
        ChemicalElement(number: 4, symbol: "Be", mass: 9.012, nameRu: "Бериллий", nameEn: "Beryllium"),
        ChemicalElement(number: 5, symbol: "B", mass: 10.81, nameRu: "Бор", nameEn: "Boron"),
        ChemicalElement(number: 6, symbol: "C", mass: 12.011, nameRu: "Углерод", nameEn: "Carbon"),
        ChemicalElement(number: 7, symbol: "N", mass: 14.007, nameRu: "Азот", nameEn: "Nitrogen"),
        ChemicalElement(number: 8, symbol: "O", mass: 15.999, nameRu: "Кислород", nameEn: "Oxygen"),
        ChemicalElement(number: 9, symbol: "F", mass: 18.998, nameRu: "Фтор", nameEn: "Fluorine"),
        ChemicalElement(number: 10, symbol: "Ne", mass: 20.180, nameRu: "Неон", nameEn: "Neon"),
        ChemicalElement(number: 11, symbol: "Na", mass: 22.990, nameRu: "Натрий", nameEn: "Sodium"),
        ChemicalElement(number: 12, symbol: "Mg", mass: 24.305, nameRu: "Магний", nameEn: "Magnesium"),
        ChemicalElement(number: 13, symbol: "Al", mass: 26.982, nameRu: "Алюминий", nameEn: "Aluminium"),
        ChemicalElement(number: 14, symbol: "Si", mass: 28.085, nameRu: "Кремний", nameEn: "Silicon"),
        ChemicalElement(number: 15, symbol: "P", mass: 30.974, nameRu: "Фосфор", nameEn: "Phosphorus"),
        ChemicalElement(number: 16, symbol: "S", mass: 32.06, nameRu: "Сера", nameEn: "Sulfur"),
        ChemicalElement(number: 17, symbol: "Cl", mass: 35.45, nameRu: "Хлор", nameEn: "Chlorine"),
        ChemicalElement(number: 18, symbol: "Ar", mass: 39.948, nameRu: "Аргон", nameEn: "Argon"),
        ChemicalElement(number: 19, symbol: "K", mass: 39.098, nameRu: "Калий", nameEn: "Potassium"),
        ChemicalElement(number: 20, symbol: "Ca", mass: 40.078, nameRu: "Кальций", nameEn: "Calcium"),
        ChemicalElement(number: 21, symbol: "Sc", mass: 44.956, nameRu: "Скандий", nameEn: "Scandium"),
        ChemicalElement(number: 22, symbol: "Ti", mass: 47.867, nameRu: "Титан", nameEn: "Titanium"),
        ChemicalElement(number: 23, symbol: "V", mass: 50.942, nameRu: "Ванадий", nameEn: "Vanadium"),
        ChemicalElement(number: 24, symbol: "Cr", mass: 51.996, nameRu: "Хром", nameEn: "Chromium"),
        ChemicalElement(number: 25, symbol: "Mn", mass: 54.938, nameRu: "Марганец", nameEn: "Manganese"),
        ChemicalElement(number: 26, symbol: "Fe", mass: 55.845, nameRu: "Железо", nameEn: "Iron"),
        ChemicalElement(number: 27, symbol: "Co", mass: 58.933, nameRu: "Кобальт", nameEn: "Cobalt"),
        ChemicalElement(number: 28, symbol: "Ni", mass: 58.693, nameRu: "Никель", nameEn: "Nickel"),
        ChemicalElement(number: 29, symbol: "Cu", mass: 63.546, nameRu: "Медь", nameEn: "Copper"),
        ChemicalElement(number: 30, symbol: "Zn", mass: 65.38, nameRu: "Цинк", nameEn: "Zinc"),
        ChemicalElement(number: 31, symbol: "Ga", mass: 69.723, nameRu: "Галлий", nameEn: "Gallium"),
        ChemicalElement(number: 32, symbol: "Ge", mass: 72.630, nameRu: "Германий", nameEn: "Germanium"),
        ChemicalElement(number: 33, symbol: "As", mass: 74.922, nameRu: "Мышьяк", nameEn: "Arsenic"),
        ChemicalElement(number: 34, symbol: "Se", mass: 78.971, nameRu: "Селен", nameEn: "Selenium"),
        ChemicalElement(number: 35, symbol: "Br", mass: 79.904, nameRu: "Бром", nameEn: "Bromine"),
        ChemicalElement(number: 36, symbol: "Kr", mass: 83.798, nameRu: "Криптон", nameEn: "Krypton"),
        ChemicalElement(number: 37, symbol: "Rb", mass: 85.468, nameRu: "Рубидий", nameEn: "Rubidium"),
        ChemicalElement(number: 38, symbol: "Sr", mass: 87.62, nameRu: "Стронций", nameEn: "Strontium"),
        ChemicalElement(number: 39, symbol: "Y", mass: 88.906, nameRu: "Иттрий", nameEn: "Yttrium"),
        ChemicalElement(number: 40, symbol: "Zr", mass: 91.224, nameRu: "Цирконий", nameEn: "Zirconium"),
        ChemicalElement(number: 41, symbol: "Nb", mass: 92.906, nameRu: "Ниобий", nameEn: "Niobium"),
        ChemicalElement(number: 42, symbol: "Mo", mass: 95.95, nameRu: "Молибден", nameEn: "Molybdenum"),
        ChemicalElement(number: 43, symbol: "Tc", mass: 98, nameRu: "Технеций", nameEn: "Technetium"),
        ChemicalElement(number: 44, symbol: "Ru", mass: 101.07, nameRu: "Рутений", nameEn: "Ruthenium"),
        ChemicalElement(number: 45, symbol: "Rh", mass: 102.906, nameRu: "Родий", nameEn: "Rhodium"),
        ChemicalElement(number: 46, symbol: "Pd", mass: 106.42, nameRu: "Палладий", nameEn: "Palladium"),
        ChemicalElement(number: 47, symbol: "Ag", mass: 107.868, nameRu: "Серебро", nameEn: "Silver"),
        ChemicalElement(number: 48, symbol: "Cd", mass: 112.414, nameRu: "Кадмий", nameEn: "Cadmium"),
        ChemicalElement(number: 49, symbol: "In", mass: 114.818, nameRu: "Индий", nameEn: "Indium"),
        ChemicalElement(number: 50, symbol: "Sn", mass: 118.710, nameRu: "Олово", nameEn: "Tin"),
        ChemicalElement(number: 51, symbol: "Sb", mass: 121.760, nameRu: "Сурьма", nameEn: "Antimony"),
        ChemicalElement(number: 52, symbol: "Te", mass: 127.60, nameRu: "Теллур", nameEn: "Tellurium"),
        ChemicalElement(number: 53, symbol: "I", mass: 126.904, nameRu: "Иод", nameEn: "Iodine"),
        ChemicalElement(number: 54, symbol: "Xe", mass: 131.293, nameRu: "Ксенон", nameEn: "Xenon"),
        ChemicalElement(number: 55, symbol: "Cs", mass: 132.905, nameRu: "Цезий", nameEn: "Caesium"),
        ChemicalElement(number: 56, symbol: "Ba", mass: 137.327, nameRu: "Барий", nameEn: "Barium"),
        ChemicalElement(number: 57, symbol: "La", mass: 138.905, nameRu: "Лантан", nameEn: "Lanthanum"),
        ChemicalElement(number: 58, symbol: "Ce", mass: 140.116, nameRu: "Церий", nameEn: "Cerium"),
        ChemicalElement(number: 59, symbol: "Pr", mass: 140.908, nameRu: "Празеодим", nameEn: "Praseodymium"),
        ChemicalElement(number: 60, symbol: "Nd", mass: 144.242, nameRu: "Неодим", nameEn: "Neodymium"),
        ChemicalElement(number: 61, symbol: "Pm", mass: 145, nameRu: "Прометий", nameEn: "Promethium"),
        ChemicalElement(number: 62, symbol: "Sm", mass: 150.36, nameRu: "Самарий", nameEn: "Samarium"),
        ChemicalElement(number: 63, symbol: "Eu", mass: 151.964, nameRu: "Европий", nameEn: "Europium"),
        ChemicalElement(number: 64, symbol: "Gd", mass: 157.25, nameRu: "Гадолиний", nameEn: "Gadolinium"),
        ChemicalElement(number: 65, symbol: "Tb", mass: 158.925, nameRu: "Тербий", nameEn: "Terbium"),
        ChemicalElement(number: 66, symbol: "Dy", mass: 162.500, nameRu: "Диспрозий", nameEn: "Dysprosium"),
        ChemicalElement(number: 67, symbol: "Ho", mass: 164.930, nameRu: "Гольмий", nameEn: "Holmium"),
        ChemicalElement(number: 68, symbol: "Er", mass: 167.259, nameRu: "Эрбий", nameEn: "Erbium"),
        ChemicalElement(number: 69, symbol: "Tm", mass: 168.934, nameRu: "Тулий", nameEn: "Thulium"),
        ChemicalElement(number: 70, symbol: "Yb", mass: 173.045, nameRu: "Иттербий", nameEn: "Ytterbium"),
        ChemicalElement(number: 71, symbol: "Lu", mass: 174.967, nameRu: "Лютеций", nameEn: "Lutetium"),
        ChemicalElement(number: 72, symbol: "Hf", mass: 178.49, nameRu: "Гафний", nameEn: "Hafnium"),
        ChemicalElement(number: 73, symbol: "Ta", mass: 180.948, nameRu: "Тантал", nameEn: "Tantalum"),
        ChemicalElement(number: 74, symbol: "W", mass: 183.84, nameRu: "Вольфрам", nameEn: "Tungsten"),
        ChemicalElement(number: 75, symbol: "Re", mass: 186.207, nameRu: "Рений", nameEn: "Rhenium"),
        ChemicalElement(number: 76, symbol: "Os", mass: 190.23, nameRu: "Осмий", nameEn: "Osmium"),
        ChemicalElement(number: 77, symbol: "Ir", mass: 192.217, nameRu: "Иридий", nameEn: "Iridium"),
        ChemicalElement(number: 78, symbol: "Pt", mass: 195.084, nameRu: "Платина", nameEn: "Platinum"),
        ChemicalElement(number: 79, symbol: "Au", mass: 196.967, nameRu: "Золото", nameEn: "Gold"),
        ChemicalElement(number: 80, symbol: "Hg", mass: 200.592, nameRu: "Ртуть", nameEn: "Mercury"),
        ChemicalElement(number: 81, symbol: "Tl", mass: 204.38, nameRu: "Таллий", nameEn: "Thallium"),
        ChemicalElement(number: 82, symbol: "Pb", mass: 207.2, nameRu: "Свинец", nameEn: "Lead"),
        ChemicalElement(number: 83, symbol: "Bi", mass: 208.980, nameRu: "Висмут", nameEn: "Bismuth"),
        ChemicalElement(number: 84, symbol: "Po", mass: 209, nameRu: "Полоний", nameEn: "Polonium"),
        ChemicalElement(number: 85, symbol: "At", mass: 210, nameRu: "Астат", nameEn: "Astatine"),
        ChemicalElement(number: 86, symbol: "Rn", mass: 222, nameRu: "Радон", nameEn: "Radon"),
        ChemicalElement(number: 87, symbol: "Fr", mass: 223, nameRu: "Франций", nameEn: "Francium"),
        ChemicalElement(number: 88, symbol: "Ra", mass: 226, nameRu: "Радий", nameEn: "Radium"),
        ChemicalElement(number: 89, symbol: "Ac", mass: 227, nameRu: "Актиний", nameEn: "Actinium"),
        ChemicalElement(number: 90, symbol: "Th", mass: 232.038, nameRu: "Торий", nameEn: "Thorium"),
        ChemicalElement(number: 91, symbol: "Pa", mass: 231.036, nameRu: "Протактиний", nameEn: "Protactinium"),
        ChemicalElement(number: 92, symbol: "U", mass: 238.029, nameRu: "Уран", nameEn: "Uranium"),
        ChemicalElement(number: 93, symbol: "Np", mass: 237, nameRu: "Нептуний", nameEn: "Neptunium"),
        ChemicalElement(number: 94, symbol: "Pu", mass: 244, nameRu: "Плутоний", nameEn: "Plutonium"),
        ChemicalElement(number: 95, symbol: "Am", mass: 243, nameRu: "Америций", nameEn: "Americium"),
        ChemicalElement(number: 96, symbol: "Cm", mass: 247, nameRu: "Кюрий", nameEn: "Curium"),
        ChemicalElement(number: 97, symbol: "Bk", mass: 247, nameRu: "Берклий", nameEn: "Berkelium"),
        ChemicalElement(number: 98, symbol: "Cf", mass: 251, nameRu: "Калифорний", nameEn: "Californium"),
        ChemicalElement(number: 99, symbol: "Es", mass: 252, nameRu: "Эйнштейний", nameEn: "Einsteinium"),
        ChemicalElement(number: 100, symbol: "Fm", mass: 257, nameRu: "Фермий", nameEn: "Fermium"),
        ChemicalElement(number: 101, symbol: "Md", mass: 258, nameRu: "Менделевий", nameEn: "Mendelevium"),
        ChemicalElement(number: 102, symbol: "No", mass: 259, nameRu: "Нобелий", nameEn: "Nobelium"),
        ChemicalElement(number: 103, symbol: "Lr", mass: 266, nameRu: "Лоуренсий", nameEn: "Lawrencium"),
        ChemicalElement(number: 104, symbol: "Rf", mass: 267, nameRu: "Резерфордий", nameEn: "Rutherfordium"),
        ChemicalElement(number: 105, symbol: "Db", mass: 268, nameRu: "Дубний", nameEn: "Dubnium"),
        ChemicalElement(number: 106, symbol: "Sg", mass: 269, nameRu: "Сиборгий", nameEn: "Seaborgium"),
        ChemicalElement(number: 107, symbol: "Bh", mass: 270, nameRu: "Борий", nameEn: "Bohrium"),
        ChemicalElement(number: 108, symbol: "Hs", mass: 277, nameRu: "Хассий", nameEn: "Hassium"),
        ChemicalElement(number: 109, symbol: "Mt", mass: 278, nameRu: "Мейтнерий", nameEn: "Meitnerium"),
        ChemicalElement(number: 110, symbol: "Ds", mass: 281, nameRu: "Дармштадтий", nameEn: "Darmstadtium"),
        ChemicalElement(number: 111, symbol: "Rg", mass: 282, nameRu: "Рентгений", nameEn: "Roentgenium"),
        ChemicalElement(number: 112, symbol: "Cn", mass: 285, nameRu: "Коперниций", nameEn: "Copernicium"),
        ChemicalElement(number: 113, symbol: "Nh", mass: 286, nameRu: "Нихоний", nameEn: "Nihonium"),
        ChemicalElement(number: 114, symbol: "Fl", mass: 289, nameRu: "Флеровий", nameEn: "Flerovium"),
        ChemicalElement(number: 115, symbol: "Mc", mass: 290, nameRu: "Московий", nameEn: "Moscovium"),
        ChemicalElement(number: 116, symbol: "Lv", mass: 293, nameRu: "Ливерморий", nameEn: "Livermorium"),
        ChemicalElement(number: 117, symbol: "Ts", mass: 294, nameRu: "Теннессин", nameEn: "Tennessine"),
        ChemicalElement(number: 118, symbol: "Og", mass: 294, nameRu: "Оганесон", nameEn: "Oganesson"),
    ]

    static let bySymbol: [String: ChemicalElement] = Dictionary(uniqueKeysWithValues: elements.map { ($0.symbol, $0) })

    static func element(_ symbol: String) -> ChemicalElement? {
        bySymbol[symbol]
    }

    /// Основа русского названия: «кислород», «натри», «сер», «марган».
    private static func russianStem(_ name: String) -> String {
        let lower = name.lowercased()
        if lower.hasSuffix("ец") { return String(lower.dropLast(2)) }
        if let last = lower.last, "аоьйяе".contains(last), lower.count >= 4 { return String(lower.dropLast()) }
        return lower
    }

    /// Поиск элемента по названию в тексте («кислорода», «oxygen»).
    /// Побеждает самое раннее упоминание, при равенстве — более длинная основа («серебр» против «сер»).
    static func element(mentionedIn lower: String) -> ChemicalElement? {
        var best: (element: ChemicalElement, position: Int, length: Int)?
        for element in elements {
            var stems = [russianStem(element.nameRu), element.nameEn.lowercased()]
            if element.symbol == "I" { stems.append("йод") }
            if element.symbol == "Al" { stems.append("aluminum") }
            if element.symbol == "S" { stems.append("sulphur") }
            for stem in stems {
                guard let range = lower.range(of: stem) else { continue }
                // Основа должна начинать слово.
                if range.lowerBound > lower.startIndex, lower[lower.index(before: range.lowerBound)].isLetter { continue }
                let position = lower.distance(from: lower.startIndex, to: range.lowerBound)
                if best == nil || position < (best?.position ?? Int.max)
                    || (position == best?.position && stem.count > (best?.length ?? 0))
                {
                    best = (element, position, stem.count)
                }
            }
        }
        return best?.element
    }
}
