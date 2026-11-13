import Foundation

/// Результат определения предмета.
struct SubjectGuess: Sendable, Equatable {
    var subject: Subject
    /// Уверенность от 0 до 1.
    var confidence: Double
    /// Альтернативы в порядке убывания правдоподобия.
    var ranked: [Subject]
}

/// Определение школьного предмета по тексту задания.
///
/// Работает на словарях основ слов и структурных признаках (формулы, единицы измерения,
/// химические формулы). На устройстве результат может уточняться моделью Core ML,
/// если она установлена, — см. `SubjectClassifierService` в слое сервисов.
struct SubjectDetector: Sendable {
    init() {}

    /// Основы слов (в нижнем регистре) и их вес. Сопоставление — по началу слова.
    private static let lexicon: [Subject: [(stems: [String], weight: Double)]] = [
        .math: [
            (["уравнен", "неравенств", "производн", "интеграл", "первообразн", "логарифм", "дискриминант", "многочлен", "дроб", "знаменател", "числител"], 3),
            (["вычисл", "упрост", "выражени", "множител", "процент", "нод", "нок", "корен", "степен", "функци", "график", "сократ"], 2),
            (["треугольник", "окружност", "периметр", "площад", "гипотенуз", "катет", "синус", "косинус", "тангенс", "угол", "угла", "прям", "парабол"], 2),
            (["equation", "inequalit", "derivative", "integral", "simplif", "factor", "polynomial", "fraction", "logarithm", "quadratic"], 3),
            (["calculate", "evaluate", "solve", "percent", "triangle", "perimeter", "angle", "expression"], 1.5),
        ],
        .physics: [
            (["скорост", "ускорен", "давлен", "плотност", "мощност", "напряжен", "сопротивлен", "теплот", "теплоёмкост", "теплоемкост", "импульс", "кинетическ", "потенциальн"], 3),
            (["сила", "силу", "силы", "силой", "масс", "энерги", "работ", "заряд", "частот", "колебан", "волн", "ток", "проводник", "тело", "тела", "движ", "автомобил", "поезд", "нагрев", "падени"], 1.5),
            (["velocity", "acceleration", "pressure", "density", "voltage", "resistance", "momentum", "kinetic", "wavelength", "frequency"], 3),
            (["force", "mass", "energy", "power", "speed", "current", "charge", "heat"], 1.5),
        ],
        .chemistry: [
            (["молярн", "моль", "молекул", "реакци", "оксид", "кислот", "щёлоч", "щелоч", "основани", "соль", "соли", "раствор", "валентност", "окислен", "восстановит", "электролит", "катион", "анион", "изотоп"], 3),
            (["вещест", "химическ", "элемент", "атом", "массовая доля", "массовую долю", "уравняйте", "коэффициент"], 2),
            (["molar", "mole", "molecule", "reaction", "oxide", "acid", "solution", "valence", "oxidation", "isotope", "balance the"], 3),
            (["chemical", "compound", "element", "atom"], 1.5),
        ],
        .russian: [
            (["орфограмм", "подлежащ", "сказуем", "падеж", "склонен", "спряжен", "морфологическ", "синтаксическ", "фонетическ", "пунктуаци", "причасти", "деепричасти", "наречи", "местоимен", "прилагательн", "существительн", "суффикс", "приставк", "однокоренн"], 3),
            (["запят", "предложени", "словосочетан", "разбор", "ударени", "пропущенн", "букв", "вставьте", "глагол", "часть речи", "части речи", "синоним", "антоним", "правописан", "диктант", "сочинени", "изложени"], 2),
        ],
        .english: [
            (["present simple", "past simple", "present perfect", "present continuous", "past continuous", "future simple", "passive voice", "irregular verb", "fill in the gap", "put the verb", "open the brackets", "choose the correct", "translate"], 3),
            (["английск", "переведите на англ", "на английский", "артикл", "времена глагол", "tense", "grammar", "vocabulary", "preposition", "pronoun", "adjective", "adverb", "sentence", "complete the"], 2),
        ],
        .history: [
            (["революци", "император", "царь", "царя", "князь", "князя", "восстани", "династи", "реформ", "крепостн", "монарх", "государ", "империя", "империи", "древн", "средневеков", "крестов", "вов", "ссср", "битв", "сражени"], 3),
            (["век", "веке", "века", "году", "годах", "войн", "истори", "правлени", "правил"], 1.5),
            (["revolution", "emperor", "empire", "dynasty", "medieval", "ancient", "battle", "treaty", "reign", "world war"], 3),
            (["century", "war", "history", "king", "queen"], 1.5),
        ],
        .social: [
            (["обществознан", "конституци", "гражданин", "гражданск", "правоотношен", "правонарушен", "демократи", "социальн", "политическ", "экономическ", "налог", "бюджет", "инфляци", "безработиц", "предпринимател", "мораль", "нравствен"], 3),
            (["обществ", "государств", "право", "права", "закон", "власт", "рынок", "рынка", "спрос", "предложени", "семья", "личност"], 1.5),
            (["constitution", "citizen", "democracy", "government", "economy", "inflation", "unemployment", "society", "taxes"], 2.5),
        ],
        .biology: [
            (["клетк", "организм", "фотосинтез", "хромосом", "генетик", "эволюци", "млекопитающ", "растени", "бактери", "вирус", "фермент", "митоз", "мейоз", "экосистем", "днк", "рнк", "белок", "белки"], 3),
            (["животн", "орган", "ткан", "вид", "популяци", "ген"], 1.2),
            (["cell", "organism", "photosynthesis", "chromosome", "genetic", "evolution", "mammal", "bacteria", "enzyme", "mitosis", "ecosystem", "dna", "protein"], 3),
        ],
        .geography: [
            (["материк", "океан", "климат", "рельеф", "широт", "долгот", "полушари", "экватор", "столиц", "населени", "природн", "зона", "тундр", "тайг", "степь", "пустын", "вулкан", "атмосфер", "гидросфер", "литосфер"], 2.5),
            (["географи", "карт", "страна", "страны", "река", "реки", "гор", "море", "озер"], 1.2),
            (["continent", "ocean", "climate", "latitude", "longitude", "equator", "capital", "population", "volcano", "geography"], 2.5),
        ],
        .literature: [
            (["стихотворен", "поэм", "роман", "повест", "рассказ", "произведени", "лирическ", "герой", "героя", "сюжет", "композици", "метафор", "эпитет", "олицетворен", "писател", "поэт", "автор", "пушкин", "лермонтов", "толст", "достоевск", "гогол", "чехов", "тургенев"], 2.5),
            (["poem", "novel", "author", "character", "plot", "metaphor", "shakespeare", "literature", "poet"], 2.5),
        ],
        .informatics: [
            (["алгоритм", "программ", "двоичн", "восьмеричн", "шестнадцатеричн", "систем счислен", "системе счислен", "систему счислен", "бит", "байт", "кбайт", "мбайт", "массив", "цикл", "переменн", "логическ", "python", "паскал"], 3),
            (["algorithm", "binary", "hexadecimal", "octal", "bit", "byte", "array", "loop", "boolean", "program"], 2.5),
        ],
    ]

    func detect(_ text: String) -> SubjectGuess {
        let lower = text.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        var scores: [Subject: Double] = [:]

        for (subject, groups) in SubjectDetector.lexicon {
            var score = 0.0
            for group in groups {
                for stem in group.stems {
                    if stem.contains(" ") {
                        if lower.contains(stem) { score += group.weight }
                    } else if stem.count <= 3 {
                        // Короткие основы — только целое слово («ток», «бит», «ген»).
                        if words.contains(stem) { score += group.weight }
                    } else if words.contains(where: { $0.hasPrefix(stem) }) {
                        score += group.weight
                    }
                }
            }
            if score > 0 { scores[subject] = score }
        }

        // Структурные признаки.
        let symbols = lower.filter { !$0.isWhitespace }
        if !symbols.isEmpty {
            let mathCharacters = symbols.filter { $0.isNumber || "+-*/=^<>√()²³·×÷−≤≥".contains($0) }
            let density = Double(mathCharacters.count) / Double(symbols.count)
            if density > 0.5 {
                scores[.math, default: 0] += 5
            } else if density > 0.25 {
                scores[.math, default: 0] += 2.5
            }
        }
        if MathTextExtractor.fragments(in: text).contains(where: { fragment in
            fragment.contains(where: { "=<>≤≥^²³√".contains($0) }) && fragment.contains(where: { $0.isLetter })
        }) {
            scores[.math, default: 0] += 2.5
        }
        let givens = PhysicsSolver(lang: .ru).extractGivens(MathNormalizer.normalize(text))
        if givens.count >= 2 {
            scores[.physics, default: 0] += 3.5
        } else if givens.count == 1 {
            scores[.physics, default: 0] += 1
        }
        switch ChemistrySolver.formulaEvidence(in: text) {
        case .reaction: scores[.chemistry, default: 0] += 7
        case .formula: scores[.chemistry, default: 0] += 4
        case .none: break
        }
        // Текст без кириллицы, состоящий из слов, — вероятно, задание по английскому.
        if !lower.hasCyrillic, words.filter({ $0.count >= 3 && $0.allSatisfy { $0.isLetter } }).count >= 4 {
            scores[.english, default: 0] += 1.5
        }

        let ranked = scores.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key.rawValue < rhs.key.rawValue
        }
        guard let best = ranked.first, best.value >= 1.5 else {
            return SubjectGuess(subject: .other, confidence: 0, ranked: [.other])
        }
        let second = ranked.dropFirst().first?.value ?? 0
        let confidence = min(1, best.value / (best.value + second + 1.5))
        return SubjectGuess(subject: best.key, confidence: confidence, ranked: ranked.map { $0.key })
    }
}

extension ChemistrySolver {
    enum FormulaEvidence: Sendable {
        case none, formula, reaction
    }

    /// Есть ли в тексте химические формулы — признак для определения предмета.
    static func formulaEvidence(in text: String) -> FormulaEvidence {
        ChemistrySolver(lang: .ru).evidence(in: text)
    }
}
