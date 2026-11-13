import CoreText
import UIKit

/// Экспорт решения в PDF (формат A4). Файл создаётся во временной папке приложения.
@MainActor
enum PDFExporter {
    private static let pageSize = CGSize(width: 595, height: 842)
    private static let margin: CGFloat = 48

    static func export(problem: String, solution: Solution, image: UIImage?, date: Date, l: L10n) throws -> URL {
        let content = attributedContent(problem: problem, solution: solution, date: date, l: l)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let framesetter = CTFramesetterCreateWithAttributedString(content as CFAttributedString)
        let total = content.length

        let data = renderer.pdfData { context in
            var location = 0
            var isFirstPage = true
            var pageNumber = 0
            repeat {
                context.beginPage()
                pageNumber += 1
                var top = margin
                if isFirstPage, let image {
                    top = drawImage(image, top: top) + 16
                }
                isFirstPage = false

                // CoreText рисует в системе координат с началом в левом нижнем углу.
                let textHeight = pageSize.height - top - margin - 16
                let rect = CGRect(x: margin, y: margin + 16, width: pageSize.width - 2 * margin, height: textHeight)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), CGPath(rect: rect, transform: nil), nil)
                let cgContext = context.cgContext
                cgContext.saveGState()
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: pageSize.height)
                cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, cgContext)
                cgContext.restoreGState()

                let footer = NSAttributedString(
                    string: "AI Homework · \(pageNumber)",
                    attributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.gray])
                footer.draw(at: CGPoint(x: margin, y: pageSize.height - margin + 6))

                let visible = CTFrameGetVisibleStringRange(frame)
                // Защита от зацикливания, если на страницу не поместилось ни символа.
                guard visible.length > 0 else { break }
                location += visible.length
            } while location < total
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AI Homework \(formatter.string(from: date)).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Рисует фотографию задания и возвращает нижнюю границу изображения.
    private static func drawImage(_ image: UIImage, top: CGFloat) -> CGFloat {
        let maxWidth = pageSize.width - 2 * margin
        let maxHeight: CGFloat = 230
        let scale = min(maxWidth / max(image.size.width, 1), maxHeight / max(image.size.height, 1), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(x: margin, y: top, width: size.width, height: size.height)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        UIGraphicsGetCurrentContext()?.saveGState()
        path.addClip()
        image.draw(in: rect)
        UIGraphicsGetCurrentContext()?.restoreGState()
        return rect.maxY
    }

    private static func attributedContent(problem: String, solution: Solution, date: Date, l: L10n) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
        let headingFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 11.5)
        let formulaFont = UIFont(name: "Menlo", size: 11) ?? UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let captionFont = UIFont.systemFont(ofSize: 10)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        paragraph.paragraphSpacing = 6
        let indented = NSMutableParagraphStyle()
        indented.lineSpacing = 2.5
        indented.paragraphSpacing = 4
        indented.firstLineHeadIndent = 14
        indented.headIndent = 14

        func add(_ text: String, font: UIFont, color: UIColor = .black, style: NSParagraphStyle = paragraph) {
            result.append(
                NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: l.lang.localeIdentifier)
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        add("\(solution.subject.title(l)) · \(solution.problemType)", font: titleFont)
        add(dateFormatter.string(from: date), font: captionFont, color: .gray)
        add("", font: bodyFont)

        add(l("Условие", "Problem"), font: headingFont, color: .darkGray)
        add(problem, font: bodyFont)
        if !solution.interpretedProblem.isEmpty, solution.interpretedProblem != problem {
            add(l("Распознано как: ", "Interpreted as: ") + solution.interpretedProblem, font: formulaFont, color: .darkGray)
        }

        if !solution.answer.isEmpty {
            add("", font: bodyFont)
            add(l("Ответ", "Answer"), font: headingFont, color: .darkGray)
            add(solution.answer, font: UIFont.systemFont(ofSize: 14, weight: .semibold))
        }
        if !solution.explanation.isEmpty {
            add("", font: bodyFont)
            add(l("Объяснение", "Explanation"), font: headingFont, color: .darkGray)
            add(solution.explanation, font: bodyFont)
        }
        if !solution.steps.isEmpty {
            add("", font: bodyFont)
            add(l("Решение по шагам", "Step-by-step solution"), font: headingFont, color: .darkGray)
            for (index, step) in solution.steps.enumerated() {
                add("\(index + 1). \(step.title)", font: UIFont.systemFont(ofSize: 11.5, weight: .medium))
                if let formula = step.formula, !formula.isEmpty {
                    add(formula, font: formulaFont, style: indented)
                }
                if !step.detail.isEmpty {
                    add(step.detail, font: bodyFont, color: .darkGray, style: indented)
                }
            }
        }
        if !solution.formulas.isEmpty {
            add("", font: bodyFont)
            add(l("Формулы", "Formulas"), font: headingFont, color: .darkGray)
            for formula in solution.formulas {
                add("• " + formula, font: formulaFont)
            }
        }
        if !solution.notes.isEmpty {
            add("", font: bodyFont)
            for note in solution.notes {
                add("⚠︎ " + note, font: captionFont, color: .gray)
            }
        }
        add("", font: bodyFont)
        add(
            l(
                "Создано в приложении AI Homework. Решение получено на устройстве, без отправки данных на серверы.",
                "Created with AI Homework. The solution was produced on device, without sending data to any server."),
            font: captionFont, color: .gray)
        return result
    }
}
