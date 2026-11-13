import Foundation
import NaturalLanguage
import UIKit

/// Результат локального анализа текста — то, что устройство умеет без языковой модели.
struct TextAnalysis: Sendable, Equatable {
    struct Misspelling: Sendable, Equatable, Identifiable {
        var id: String { word }
        var word: String
        var suggestions: [String]
    }

    struct TaggedWord: Sendable, Equatable, Identifiable {
        var id: Int
        var word: String
        var lemma: String?
        var partOfSpeech: String
    }

    struct Entity: Sendable, Equatable, Identifiable {
        var id: String { kind + ":" + text }
        var text: String
        var kind: String
    }

    var languageName: String?
    var languageCode: String?
    var sentenceCount: Int
    var wordCount: Int
    var misspellings: [Misspelling]
    /// Проверялась ли орфография (словарь нужного языка может отсутствовать на устройстве).
    var spellCheckAvailable: Bool
    var words: [TaggedWord]
    var entities: [Entity]
    /// Одно слово или термин — для него можно открыть системный словарь.
    var singleTerm: String?

    var isEmpty: Bool {
        wordCount == 0
    }
}

/// Инструменты анализа текста на устройстве: NaturalLanguage и системная проверка орфографии.
///
/// Это не «решение» задания, а честные вспомогательные данные: части речи, начальные формы,
/// возможные опечатки, имена и названия в тексте.
@MainActor
enum LanguageTools {
    static func analyze(_ text: String, lang: AppLanguage) -> TextAnalysis {
        let l = L10n(lang)
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4_000))

        // Язык текста.
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.russian, .english]
        recognizer.processString(trimmed)
        let language = recognizer.dominantLanguage
        let languageName: String?
        switch language {
        case .some(.russian): languageName = l("русский", "Russian")
        case .some(.english): languageName = l("английский", "English")
        default: languageName = nil
        }

        // Предложения и слова.
        let sentenceTokenizer = NLTokenizer(unit: .sentence)
        sentenceTokenizer.string = trimmed
        let sentenceCount = sentenceTokenizer.tokens(for: trimmed.startIndex..<trimmed.endIndex).count

        // Части речи и начальные формы.
        var words: [TextAnalysis.TaggedWord] = []
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
        tagger.string = trimmed
        if let language {
            tagger.setLanguage(language, range: trimmed.startIndex..<trimmed.endIndex)
        }
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            let word = String(trimmed[range])
            guard word.contains(where: { $0.isLetter }) else { return true }
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
            words.append(
                TextAnalysis.TaggedWord(
                    id: words.count, word: word,
                    lemma: lemma.flatMap { $0.lowercased() == word.lowercased() ? nil : $0 },
                    partOfSpeech: partOfSpeechName(tag, l)))
            return words.count < 120
        }

        // Имена, места, организации.
        var entities: [TextAnalysis.Entity] = []
        tagger.enumerateTags(
            in: trimmed.startIndex..<trimmed.endIndex, unit: .word, scheme: .nameType,
            options: [.omitWhitespace, .omitPunctuation, .joinNames]
        ) { tag, range in
            let kind: String?
            switch tag {
            case .some(.personalName): kind = l("Человек", "Person")
            case .some(.placeName): kind = l("Место", "Place")
            case .some(.organizationName): kind = l("Организация", "Organization")
            default: kind = nil
            }
            if let kind {
                let entity = TextAnalysis.Entity(text: String(trimmed[range]), kind: kind)
                if !entities.contains(entity) { entities.append(entity) }
            }
            return entities.count < 30
        }

        // Орфография.
        let checkerLanguage = spellCheckLanguage(for: language, fallback: lang)
        var misspellings: [TextAnalysis.Misspelling] = []
        if let checkerLanguage {
            let checker = UITextChecker()
            let nsText = trimmed as NSString
            var offset = 0
            while offset < nsText.length, misspellings.count < 40 {
                let range = checker.rangeOfMisspelledWord(
                    in: trimmed, range: NSRange(location: 0, length: nsText.length), startingAt: offset, wrap: false,
                    language: checkerLanguage)
                guard range.location != NSNotFound, range.length > 0 else { break }
                let word = nsText.substring(with: range)
                // Формулы, числа и аббревиатуры не считаем опечатками.
                let isOrdinaryWord = word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "’" || $0 == "'" } && word.count > 1
                    && word != word.uppercased()
                if isOrdinaryWord, !misspellings.contains(where: { $0.word == word }) {
                    let guesses = checker.guesses(forWordRange: range, in: trimmed, language: checkerLanguage) ?? []
                    misspellings.append(TextAnalysis.Misspelling(word: word, suggestions: Array(guesses.prefix(4))))
                }
                offset = range.location + range.length
            }
        }

        let singleTerm = words.count <= 3 && !trimmed.isEmpty && trimmed.count <= 40 ? trimmed : nil
        return TextAnalysis(
            languageName: languageName,
            languageCode: language?.rawValue,
            sentenceCount: sentenceCount,
            wordCount: words.count,
            misspellings: misspellings,
            spellCheckAvailable: checkerLanguage != nil,
            words: words,
            entities: entities,
            singleTerm: singleTerm)
    }

    /// Код языка для `UITextChecker`, если его словарь установлен в системе.
    private static func spellCheckLanguage(for language: NLLanguage?, fallback: AppLanguage) -> String? {
        let available = UITextChecker.availableLanguages
        let prefix: String
        switch language {
        case .some(.russian): prefix = "ru"
        case .some(.english): prefix = "en"
        default: prefix = fallback == .ru ? "ru" : "en"
        }
        let preferred = prefix == "ru" ? "ru_RU" : "en_US"
        if available.contains(preferred) { return preferred }
        return available.first { $0.hasPrefix(prefix) }
    }

    private static func partOfSpeechName(_ tag: NLTag?, _ l: L10n) -> String {
        switch tag {
        case .some(.noun): return l("существительное", "noun")
        case .some(.verb): return l("глагол", "verb")
        case .some(.adjective): return l("прилагательное", "adjective")
        case .some(.adverb): return l("наречие", "adverb")
        case .some(.pronoun): return l("местоимение", "pronoun")
        case .some(.determiner): return l("определитель", "determiner")
        case .some(.particle): return l("частица", "particle")
        case .some(.preposition): return l("предлог", "preposition")
        case .some(.number): return l("числительное", "numeral")
        case .some(.conjunction): return l("союз", "conjunction")
        case .some(.interjection): return l("междометие", "interjection")
        default: return l("другое", "other")
        }
    }

    /// Есть ли в системном словаре статья для слова.
    static func hasDictionaryDefinition(for term: String) -> Bool {
        UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term)
    }
}
