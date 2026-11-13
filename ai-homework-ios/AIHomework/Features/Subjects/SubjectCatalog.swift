import Foundation

/// Что приложение честно умеет по каждому предмету и примеры заданий.
extension Subject {
    func capabilities(_ l: L10n) -> [String] {
        switch self {
        case .math:
            return [
                l("Вычисления с дробями, степенями, корнями, процентами", "Arithmetic with fractions, powers, roots and percentages"),
                l("Уравнения: линейные, квадратные, высших степеней, дробные, с модулем", "Equations: linear, quadratic, higher degree, rational, with absolute value"),
                l("Неравенства методом интервалов, двойные неравенства", "Inequalities by the interval method, double inequalities"),
                l("Системы линейных и простых нелинейных уравнений", "Systems of linear and simple nonlinear equations"),
                l("Упрощение, разложение на множители, НОД и НОК", "Simplification, factoring, GCD and LCM"),
                l("Производные и простые интегралы", "Derivatives and simple integrals"),
                l("Тригонометрия с точными табличными значениями", "Trigonometry with exact table values"),
            ]
        case .physics:
            return [
                l("Задачи «в одну формулу»: механика, давление, работа, энергия", "Single-formula problems: mechanics, pressure, work, energy"),
                l("Теплота, закон Ома, мощность и работа тока", "Heat, Ohm's law, electric power and work"),
                l("Автоматический перевод единиц в СИ", "Automatic conversion to SI units"),
                l("Табличные данные: g, плотности и теплоёмкости веществ", "Table data: g, densities and specific heats"),
            ]
        case .chemistry:
            return [
                l("Уравнивание реакций (расстановка коэффициентов)", "Balancing chemical equations"),
                l("Молярная масса и массовые доли элементов", "Molar mass and mass fractions"),
                l("Количество вещества, масса, объём газа, число молекул", "Amount of substance, mass, gas volume, number of molecules"),
                l("Таблица Менделеева — все 118 элементов", "Periodic table — all 118 elements"),
            ]
        case .informatics:
            return [
                l("Перевод чисел между системами счисления (2–16)", "Number base conversion (2–16)"),
                l("Единицы измерения информации", "Units of information"),
            ]
        case .russian, .english, .literature:
            return [
                l("Проверка орфографии системным словарём", "Spell checking with the system dictionary"),
                l("Части речи и начальные формы слов", "Parts of speech and base word forms"),
                l("Перевод и системный словарь на устройстве", "On-device translation and dictionary"),
                l("Развёрнутые ответы — с локальной языковой моделью", "Full answers — with an on-device language model"),
            ]
        case .history, .social, .biology, .geography, .other:
            return [
                l("Развёрнутые ответы — с локальной языковой моделью", "Full answers — with an on-device language model"),
                l("Без модели: имена, места и даты в тексте, перевод", "Without a model: names, places and dates in the text, translation"),
            ]
        }
    }

    func examples(_ l: L10n) -> [String] {
        switch self {
        case .math:
            return [
                l("Решите уравнение x² − 5x + 6 = 0", "Solve the equation x² − 5x + 6 = 0"),
                l("Решите неравенство (x + 1)/(x − 2) ≥ 0", "Solve the inequality (x + 1)/(x − 2) ≥ 0"),
                l("Решите систему уравнений: x + y = 5, x − y = 1", "Solve the system: x + y = 5, x − y = 1"),
                l("Найдите производную функции f(x) = x·sin(x)", "Find the derivative of f(x) = x·sin(x)"),
                l("Упростите выражение (a + b)² − (a − b)²", "Simplify (a + b)² − (a − b)²"),
                l("Вычислите 3/4 − 1/6 + 2", "Calculate 3/4 − 1/6 + 2"),
            ]
        case .physics:
            return [
                l("Автомобиль проехал 150 км за 2 ч. Найдите скорость автомобиля.", "A car travels 150 km in 2 h. Find the speed."),
                l(
                    "Какое количество теплоты необходимо для нагревания 2 кг воды от 20 °C до 100 °C?",
                    "What force is needed to accelerate a mass of 5 kg at 2 m/s^2?"),
                l("Сопротивление проводника 10 Ом, напряжение на нём 220 В. Найдите силу тока.", "Convert 72 km/h to m/s"),
            ]
        case .chemistry:
            return [
                l("Расставьте коэффициенты: Al + HCl → AlCl3 + H2", "Balance: Al + HCl → AlCl3 + H2"),
                l("Найдите молярную массу H2SO4", "Find the molar mass of H2SO4"),
                l("Найдите массовую долю кислорода в H2O", "Find the mass percent of oxygen in H2O"),
                l("Какой объём занимают 2 моль CO2?", "Balance: Fe + O2 → Fe2O3"),
            ]
        case .informatics:
            return [
                l("Переведите число 45 в двоичную систему счисления", "Convert 255 from decimal to hexadecimal"),
                l("Переведите 1011 из двоичной системы в десятичную", "Convert 1011 from binary to decimal"),
                l("Сколько бит в 2 Кбайт?", "How many bits are in 2 KB?"),
            ]
        case .russian:
            return [
                l("Выполните морфологический разбор слова «бегущий»", "Do a morphological analysis of the Russian word «бегущий»"),
                l("Найдите грамматическую основу: Осенний лес стоял тихо.", "Find the subject and predicate: Осенний лес стоял тихо."),
            ]
        case .english:
            return [
                l("Put the verb into Past Simple: I (go) to school yesterday.", "Put the verb into Past Simple: I (go) to school yesterday."),
                l("Переведите на английский: Я люблю читать книги.", "Translate into English: Я люблю читать книги."),
            ]
        case .history:
            return [l("Назовите причины Отечественной войны 1812 года.", "Name the causes of the War of 1812.")]
        case .social:
            return [l("Что такое инфляция и как она влияет на экономику?", "What is inflation and how does it affect the economy?")]
        case .biology:
            return [l("Опишите процесс фотосинтеза.", "Describe the process of photosynthesis.")]
        case .geography:
            return [l("Чем отличается климат тундры от климата тайги?", "How does the tundra climate differ from the taiga climate?")]
        case .literature:
            return [l("Какие средства выразительности использует Пушкин в «Зимнем утре»?", "What literary devices does Pushkin use in “Winter Morning”?")]
        case .other:
            return []
        }
    }
}
