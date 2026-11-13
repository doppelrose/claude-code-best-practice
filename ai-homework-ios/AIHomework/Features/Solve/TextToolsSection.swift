import SwiftUI
import Translation
import UIKit

/// Локальные инструменты для языковых заданий: орфография, части речи, имена, перевод, словарь.
/// Всё это — возможности самой iOS, без языковой модели и без сети.
struct TextToolsSection: View {
    let analysis: TextAnalysis
    let sourceText: String
    let l: L10n

    @State private var isTranslationPresented = false
    @State private var dictionaryTerm: DictionaryTerm?
    @State private var showAllWords = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(l("Анализ текста на устройстве", "On-device text analysis"), systemImage: "text.magnifyingglass")
                .font(.headline)

            summaryRow

            if analysis.spellCheckAvailable {
                spellingBlock
            }
            if !analysis.words.isEmpty {
                wordsBlock
            }
            if !analysis.entities.isEmpty {
                entitiesBlock
            }
            actions
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .modifier(TranslationSheet(isPresented: $isTranslationPresented, text: sourceText))
        .sheet(item: $dictionaryTerm) { term in
            DictionaryView(term: term.value)
                .ignoresSafeArea()
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            if let language = analysis.languageName {
                statChip(title: l("Язык", "Language"), value: language)
            }
            statChip(title: l("Предложений", "Sentences"), value: "\(analysis.sentenceCount)")
            statChip(title: l("Слов", "Words"), value: "\(analysis.wordCount)")
        }
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private var spellingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l("Орфография", "Spelling")).font(.subheadline.weight(.semibold))
            if analysis.misspellings.isEmpty {
                Label(
                    l("Системный словарь не нашёл опечаток.", "The system dictionary found no misspellings."),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.green)
            } else {
                ForEach(analysis.misspellings) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.word)
                            .font(.callout.weight(.medium))
                            .underline(true, pattern: .dot, color: .red)
                        if !item.suggestions.isEmpty {
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                            Text(item.suggestions.joined(separator: ", "))
                                .font(.callout)
                                .foregroundStyle(.green)
                        }
                    }
                }
                Text(
                    l(
                        "Это проверка по системному словарю: она находит опечатки, но не проверяет пунктуацию и грамматику.",
                        "This is a system dictionary check: it finds typos but does not verify punctuation or grammar.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var wordsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l("Части речи и начальные формы", "Parts of speech and base forms")).font(.subheadline.weight(.semibold))
            let visible = showAllWords ? analysis.words : Array(analysis.words.prefix(12))
            ForEach(visible) { word in
                HStack(alignment: .firstTextBaseline) {
                    Text(word.word).font(.callout.weight(.medium))
                    if let lemma = word.lemma {
                        Text("← " + lemma).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(word.partOfSpeech)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if analysis.words.count > 12 {
                Button {
                    Haptics.tap()
                    withAnimation(Theme.spring) { showAllWords.toggle() }
                } label: {
                    Text(showAllWords ? l("Показать меньше", "Show less") : l("Показать все слова (\(analysis.words.count))", "Show all words (\(analysis.words.count))"))
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.pressable)
            }
            Text(
                l(
                    "Разметка выполнена системным анализатором NaturalLanguage и может ошибаться в сложных случаях.",
                    "Tagging is done by the system NaturalLanguage analyzer and may be wrong in tricky cases.")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var entitiesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l("Имена и названия в тексте", "Names in the text")).font(.subheadline.weight(.semibold))
            FlowLayout(spacing: 8) {
                ForEach(analysis.entities) { entity in
                    HStack(spacing: 5) {
                        Text(entity.text).font(.footnote.weight(.medium))
                        Text(entity.kind).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if TranslationSheet.isSupported {
                GlassButton(title: l("Перевести", "Translate"), systemImage: "translate") {
                    Haptics.tap()
                    isTranslationPresented = true
                }
            }
            if let term = analysis.singleTerm, LanguageTools.hasDictionaryDefinition(for: term) {
                GlassButton(title: l("В словаре", "Look up"), systemImage: "character.book.closed") {
                    Haptics.tap()
                    dictionaryTerm = DictionaryTerm(value: term)
                }
            }
        }
    }
}

private struct DictionaryTerm: Identifiable {
    let value: String
    var id: String { value }
}

/// Системный перевод на устройстве (iOS 17.4+).
struct TranslationSheet: ViewModifier {
    @Binding var isPresented: Bool
    let text: String

    static var isSupported: Bool {
        if #available(iOS 17.4, *) { return true }
        return false
    }

    func body(content: Content) -> some View {
        if #available(iOS 17.4, *) {
            content.translationPresentation(isPresented: $isPresented, text: text)
        } else {
            content
        }
    }
}

/// Системный словарь (на устройстве).
struct DictionaryView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}

/// Стандартное меню «Поделиться».
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Файл для передачи в меню «Поделиться».
struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
