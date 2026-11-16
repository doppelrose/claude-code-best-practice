# Аудит производительности — Performance Engineer

Область: работа на главном потоке, память (изображения), плавность SwiftUI, движок, сеть, утечки, время запуска.
Метод: чтение кода + микробенчмарк движка (копия `AIHomework/Engine` в отдельной папке scratchpad, `swift build -c release`,
Docker `swift:6.2`, Linux x86-64). Цифры бенчмарка — **Linux на сервере, не iPhone**; это относительные оценки.
Всё про UIKit/SwiftUI/Vision/NaturalLanguage/ImageIO — оценки по коду; на устройстве не измерялось (Instruments
требует Mac, которого у владельца нет — см. «План замеров», там есть способы без Mac).

Сборка: Swift 6, `SWIFT_VERSION = 6.0`, режим изоляции по умолчанию **не** MainActor, `NonisolatedNonsendingByDefault`
не включён → `nonisolated async` функции (например `RemoteAPIProvider.complete`) выполняются вне главного потока.
Release собирается с `-O`, `wholemodule` (`project.pbxproj`, конфигурация Release; CI: `-configuration Release`).

## Карта нагрузки

| Операция | Поток | Ожидаемая стоимость (оценка) | Риск |
|---|---|---|---|
| Запуск: `AppSettings.init` (UserDefaults + JSON + чтение Keychain) `AppSettings.swift:56-66` | main | 1–10 мс (Keychain — межпроцессный вызов) | низкий |
| Запуск: `.modelContainer(for:)` + `@Query` всех записей на `HomeView` `HomeView.swift:9` | main | 5–30 мс при 100 записях, растёт как O(N) | средний (растёт с историей) |
| Показ фото из галереи до нормализации (`RegionSelectionView` получает исходный `UIImage`) | main (декодирование для отображения) | 12 Мп ≈ 48 МБ битмапа, 30–150 мс; 48 Мп ≈ 192 МБ, сотни мс | **высокий** |
| `ImageTools.normalized` (2600 px) `ImageTools.swift:18-34` | фон (`Task.detached`) | 50–300 мс, пик = полный битмап + 20 МБ | средний (память) |
| `DocumentScanner.stack` (до 4 страниц) `CapturePickers.swift:101-118` | **main** | 4 страницы ≈ 50–200 МБ битмапа, 0,2–1 с | **высокий** |
| Vision OCR `.accurate`, 1–2 прохода `OCRService.swift:47-86` | фон (GCD global) | 0,3–2 с на проход для страницы 2600 px | низкий (вне main), но не отменяется |
| Определение предмета `SubjectDetector` | фон | **замерено**: ≈1 мс на типичную задачу, 47 мс на текст 3,5 тыс. символов | низкий |
| Точный решатель `LocalSolverPipeline.solve` через `Deadline.compute` | фон | **замерено**: 0,2–3 мс на задачи из каталога; 11–31 мс на трансцендентные уравнения; 43–51 мс на «страницу» 3,5 тыс. символов | низкий |
| JPEG 1600 px для API `SolveCoordinator.swift:101-106` | фон | 20–60 мс | низкий |
| Сборка запроса (base64 + JSONSerialization) `RemoteAPI.swift:118+` | фон (nonisolated) | **замерено**: 21 мс на JPEG 450 КБ (Linux) | низкий |
| Два сетевых запроса подряд (диспетчер + решение), оба с изображением | сеть | 2 × (загрузка 0,3–0,6 МБ + ответ модели 1–30 с) | **высокий** (задержка) |
| `ModelPrompting.parse` ответа модели `SolveCoordinator.swift:186` | **main** | **замерено**: 19 мс на ответ 24 КБ (Linux), ≈2–5 мс на типичный 2–6 КБ | низкий/средний |
| `LanguageTools.analyze` (NLTagger + UITextChecker + guesses) `SolveCoordinator.swift:204,230`, `ProblemDetailView.swift:69-72` | **main** | 20–500 мс (холодная загрузка моделей NL, до 40 вызовов `guesses`) | **высокий** |
| `UIImage(data:)` полноразмерного фото в body `ProblemDetailView.swift:124` | **main**, при каждом пересчёте body | чтение файла externalStorage + декодирование 1600 px (≈10 МБ) 10–40 мс | **высокий** |
| Миниатюры в `ProblemRow` `HistoryView.swift:231` | **main**, при прокрутке | 1–3 мс на строку | средний |
| Экспорт PDF `PDFExporter.swift:10-57` | **main** (`@MainActor`) | 50–300 мс | средний |
| Бесконечные анимации (AIOrb, пунктир выделения, луч сканирования) | main + render server | постоянные кадры, не даёт ProMotion снизить частоту | средний (батарея) |
| Размытие всего `NavigationStack` под экраном решения `RootView.swift:24-26` | GPU | полноэкранный blur в каждом кадре перехода | средний |
| Ввод в настройках: `save()` и запись в Keychain на каждый символ `SettingsView.swift:77-82` | main | 1–10 мс на символ + перерисовка всего дерева | средний |

## Сильные стороны

- **Тяжёлая работа в основном вне главного потока.** OCR — на `DispatchQueue.global(qos: .userInitiated)` (`OCRService.swift:70`); нормализация, обрезка и JPEG — в `Task.detached` (`SolveViewModel.swift:93,129,320`, `SolveCoordinator.swift:103`); определение предмета — `Task.detached` (`SolveCoordinator.swift:48`); точный решатель — `Deadline.compute` в фоне (`SolveCoordinator.swift:219`); сеть и сборка запроса — в `nonisolated` структуре `RemoteAPIProvider`.
- **Изображения ограничены по размеру**: 2600 px для OCR, 1600 px для API и истории, 360 px для миниатюры (`ImageTools.swift:18,49-56`). `UIGraphicsImageRenderer` с `scale = 1`, `opaque = true` — без лишнего альфа-канала и ретина-множителя.
- **SwiftData**: полноразмерное фото помечено `@Attribute(.externalStorage)` (`SolvedProblem.swift:19`) — блоб не попадает в строки SQLite и не грузится при выборке списков.
- **Движок быстрый и защищён от переполнения.** `Rational` использует `multipliedReportingOverflow`/`addingReportingOverflow` (`Rational.swift:132-144`); есть пределы: степень многочлена ≤ 64 (`Polynomial.swift:180`), степень дроби ≤ 4096 (`Rational.swift:192`), делители ≤ 10¹² и ≤ 4000 штук (`Rational.swift:280-291`), кандидатов в корни ≤ 40 000 (`Polynomial.swift:394`), сетка численного поиска ≈ 11,8 тыс. точек + 100 итераций бисекции (`EquationSolver.swift:812-830`). Бенчмарк: 0,2–3 мс на все примеры каталога.
- **Сеть с общим лимитом времени**: `Deadline.run` отменяет запрос (`Deadline.swift:26-39`), одна повторная попытка через 800 мс только для обрыва соединения (`RemoteAPIProvider.swift:84-113`), диспетчеру отведено 25 с, решению 75 с.
- **Нет ручных наблюдателей и таймеров**: ни `addObserver`, ни `Timer`, ни `CADisplayLink`; уведомление получается через `.onReceive` (отписка автоматическая, `RootView.swift:66`); в замыканиях `AppModel` используется `[weak self]` (`AppModel.swift:140,157`).
- **Плоский дизайн дешёвый для GPU**: `AnimatedBackground` — сплошной цвет (`AnimatedBackground.swift:10-12`), поверхности без материалов, теней и размытия (`GlassSurface.swift`).
- **Лимиты в `LanguageTools`**: 4000 символов, 120 слов, 30 сущностей, 40 опечаток (`LanguageTools.swift:51,87,107,117`). `AIOrb` учитывает «Уменьшение движения».
- «Последние решения» на главном экране: `LazyHStack` + `prefix(10)`, в `RecentCard` нет изображений (`HomeView.swift:151-153,294-325`).

## Находки

### PERF-1. Полноразмерное фото декодируется на главном потоке и дважды держится в памяти до нормализации
- Приоритет: P1 (на снимках 48 Мп / ProRAW может дойти до P0 — подтвердить замером)
- Файл: `AIHomework/App/RootView.swift:42-51`; `AIHomework/Features/Solve/SolveViewModel.swift:88-98,118-136`; `AIHomework/Features/Solve/SolveFlowView.swift:168-170`; `AIHomework/Features/Solve/RegionSelectionView.swift:23-28`; `AIHomework/Features/Solve/SolveStages.swift:56,225-230`
- Место в коде: `item.loadTransferable(type: Data.self)` → `UIImage(data:)` → `app.startSolve(.image(image))`; нормализация запускается только в `onAppear` экрана, а `RegionSelectionView` сразу показывает исходный `UIImage`.
- Причина: `UIImage(data:)` декодируется лениво — в момент первой отрисовки, на главном потоке, в полном разрешении. Одновременно `ImageTools.normalized` в фоне декодирует ту же картинку ещё раз. Если пользователь нажмёт «Решить всё изображение» до конца нормализации, `recognize` (`SolveViewModel.swift:130`) начнёт **третье** полное декодирование. `matching: .images` пропускает и RAW/ProRAW (DNG). Миниатюра 64 pt на экране результата (`SolveStages.swift:225-230`) показывает битмап 2600 px.
- Последствия: подвисание при открытии фото (оценка: 30–150 мс для 12 Мп, сотни мс для 48 Мп); пик памяти ≈ 2–3 × (ширина × высота × 4 байта): для 48 Мп это 400–600 МБ → риск завершения системой по памяти (jetsam) на iPhone с 4–6 ГБ.
- Решение: даунсемплинг при загрузке, в фоне, через ImageIO без полного декодирования; создавать сценарий решения уже с готовым изображением ≤ 2600 px:
  ```swift
  nonisolated static func downsampled(_ data: Data, maxPixel: CGFloat = 2600) -> UIImage? {
      guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
      else { return nil }
      let opts: [CFString: Any] = [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,   // сразу .up
          kCGImageSourceShouldCacheImmediately: true,          // декодирование здесь, а не в рендере
          kCGImageSourceThumbnailMaxPixelSize: maxPixel]
      guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
      return UIImage(cgImage: cg)
  }
  ```
  В `RootView` вызывать в `Task.detached`. Для камеры — `await image.byPreparingThumbnail(ofSize:)` вне main. В `recognize` ждать уже идущую нормализацию (хранить её `Task`), а не запускать новую. Для превью 64 pt и 220 pt держать отдельную маленькую копию.
- Сложность: M
- Статус проверки: проверено чтением кода; величину подвисания и пик памяти — требует замера на устройстве (Instruments → Allocations + VM Tracker, Hangs; сценарий: фото 48 Мп из галереи → экран выделения).

### PERF-2. Склейка страниц сканера выполняется на главном потоке в полном разрешении
- Приоритет: P1 (для 3–4 страниц может стать P0)
- Файл: `AIHomework/Features/Capture/CapturePickers.swift:80-118`
- Место в коде: `documentCameraViewController(_:didFinishWith:)` → `scan.imageOfPage(at:)` для 4 страниц → `DocumentScanner.stack(pages)` через `UIGraphicsImageRenderer`.
- Причина: делегат `@MainActor`; все 4 страницы держатся в полном разрешении одновременно; итоговый холст = ширина × сумма высот, `format.opaque` не задан (лишний альфа-канал). Потом `normalized` ужимает длинную сторону склейки до 2600 px — при 4 страницах ширина падает до ≈ 490 px, и текст для OCR становится мелким (страдает и качество).
- Последствия: оценка 0,2–1 с зависания при закрытии сканера; пик памяти 150–400 МБ.
- Решение: вынести в `Task.detached`; сначала ужать каждую страницу до ширины ≈ 1600–2000 px (`preparingThumbnail(of:)`), задать `format.opaque = true`; лучше не склеивать, а распознавать страницы по отдельности и объединять текст (это вопрос архитектуры — согласовать с владельцем).
- Сложность: M
- Статус проверки: проверено чтением кода; длительность — требует замера (Hangs + Allocations, сценарий «сканер, 4 страницы»).

### PERF-3. `LanguageTools.analyze` синхронно выполняется на главном потоке
- Приоритет: P1
- Файл: `AIHomework/Services/LanguageTools.swift:47-145`; вызовы: `AIHomework/Services/SolveCoordinator.swift:204,230`; `AIHomework/Features/History/ProblemDetailView.swift:69-72`
- Место в коде: `enum LanguageTools` помечен `@MainActor`; `SolveCoordinator.outcome(...)` (тоже `@MainActor`) вызывает его для русского, английского и литературы; `ProblemDetailView` — в `.task` при каждом открытии записи.
- Причина: `NLLanguageRecognizer`, `NLTokenizer`, `NLTagger` с тремя схемами (лемма для каждого слова, отдельный проход по именам по всему тексту до 4000 символов) и `UITextChecker` с `guesses` до 40 раз. При первом вызове загружаются языковые модели NL.
- Последствия: оценка 20–500 мс на главном потоке — подвисание в момент появления результата и во время анимации перехода на экран записи истории.
- Решение: вынести NL-часть в `nonisolated static func` и вызывать через `Task.detached`. Если `UITextChecker` в SDK требует главного потока — оставить на main только `rangeOfMisspelledWord`, а `guesses` получать лениво по нажатию на слово. Результат анализа кэшировать (в `@State`, или хранить в `SolvedProblem`), а не пересчитывать при каждом открытии записи.
- Сложность: M
- Статус проверки: проверено чтением кода; длительность — требует замера (Time Profiler, фильтр по главному потоку; `os_signpost` вокруг `analyze`; сценарий: текст на русском ≈ 2000 символов, холодный запуск).

### PERF-4. Экран записи истории декодирует фото и JSON решения при каждом пересчёте body
- Приоритет: P1
- Файл: `AIHomework/Features/History/ProblemDetailView.swift:48,87,124,151`; `AIHomework/Persistence/SolvedProblem.swift:51-53`
- Место в коде: `if let data = problem.imageData, let image = UIImage(data: data)` внутри `problemCard`; `problem.solution` (это `JSONDecoder().decode` на каждое обращение) вызывается и в `content`, и в `toolbar`.
- Причина: `imageData` хранится как `externalStorage` → при обращении синхронно читается файл; `UIImage(data:)` создаёт **новый** объект при каждом вызове body, поэтому SwiftUI снова декодирует его для отображения. Body пересчитывается при показе и скрытии всплывающего сообщения (2 раза на каждое «Скопировано»), при установке `analysis`, при переключении «Избранного», при любом сохранении контекста (`@Query`).
- Последствия: оценка 10–40 мс на главном потоке за каждый пересчёт → рывки анимаций всплывающего сообщения и закладки.
- Решение: в `.task(id: problem.id)` один раз загрузить и подготовить картинку вне main (`Task.detached { UIImage(data:)?.preparingThumbnail(of: CGSize(width: 1000, height: 480)) }`) в `@State var preview: UIImage?`; `Solution` декодировать один раз в `@State`.
- Сложность: S
- Статус проверки: проверено чтением кода; стоимость — требует замера (SwiftUI instrument → View Body; Time Profiler на `UIImage(data:)`/`ImageIO`).

### PERF-5. Изображение отправляется в API дважды, два последовательных запроса без потоковой передачи
- Приоритет: P1 (воспринимаемая задержка; связано с жалобой «бесконечно решает»)
- Файл: `AIHomework/Services/SolveCoordinator.swift:99-106,114-145,172-185`; `AIHomework/Services/RemoteAPIProvider.swift:51-74`
- Место в коде: `remote.route(text:..., image: imageData, ...)`, затем `provider.generate(..., image: image, ...)` с тем же JPEG 1600 px q=0.82.
- Причина: диспетчер и решатель — два независимых полных запроса; каждый несёт base64 изображения (+33 % к размеру JPEG). Ответ ждём целиком (нет потоковой передачи).
- Последствия: при слабом мобильном канале (отдача ≈ 1 Мбит/с) загрузка 0,4–0,6 МБ занимает 3–5 с **дважды**, плюс два ожидания ответа модели. На экране только счётчик секунд.
- Решение (без смены архитектуры): (1) диспетчеру отправлять изображение поменьше (768 px, q=0.6) или только текст, когда OCR уверен (`ocrConfidence ≥ 0.85`) и текст непустой; (2) сжимать изображение один раз под оба размера; (3) по возможности включить потоковую передачу (`"stream": true`), чтобы показывать ответ по мере генерации; (4) обдумать протокол «один запрос»: модель либо возвращает маршрут `local`, либо сразу решение (менять с согласия владельца).
- Сложность: M
- Статус проверки: проверено чтением кода; задержку — требует замера (Instruments → Network; `os_signpost` на «routing start/end», «solve start/end»; сценарий: LTE с ограничением через Network Link Conditioner «3G»/«LTE»).

### PERF-6. `@Query` без лимита на главном экране и ещё в двух живых экранах
- Приоритет: P2 (растёт с размером истории)
- Файл: `AIHomework/Features/Home/HomeView.swift:9,152,210-212`; `AIHomework/Features/History/HistoryView.swift:8`; `AIHomework/Features/Subjects/SubjectView.swift:9,13-15`
- Место в коде: `@Query(sort: \SolvedProblem.createdAt, order: .reverse) private var problems`; в body `problems.filter { $0.isFavorite }.count` и `problems.count`.
- Причина: главный экран (он всегда в стеке навигации) выбирает **все** записи вместе с `thumbnailData` и `solutionData` (не externalStorage), чтобы показать 10 карточек и два числа. Ещё два `@Query` на все записи живут, пока открыты «История» или «Предмет». Каждое `context.save()` (решение, «Избранное») заставляет все живые запросы перевыбирать данные на главном потоке.
- Последствия: время запуска и потребление памяти растут как O(N): при 1000 записей это оценочно 10–40 МБ (миниатюра 15–40 КБ + JSON решения) и десятки мс на выборку.
- Решение:
  ```swift
  static var recent: FetchDescriptor<SolvedProblem> {
      var d = FetchDescriptor<SolvedProblem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
      d.fetchLimit = 10
      return d
  }
  @Query(HomeView.recent) private var recent: [SolvedProblem]
  // счётчики: try? context.fetchCount(FetchDescriptor<SolvedProblem>(predicate: #Predicate { $0.isFavorite }))
  ```
  В `SubjectView` — `#Predicate { $0.subjectRaw == raw }` и `fetchLimit = 5`. Тяжёлые блобы (миниатюра, JSON) при росте можно вынести в отдельную сущность со связью.
- Сложность: M
- Статус проверки: проверено чтением кода; масштаб — требует замера (сгенерировать 1000 записей в отладочной сборке; App Launch + Allocations; Core Data instrument / `-com.apple.CoreData.SQLDebug 1`).

### PERF-7. Миниатюры истории декодируются в body на главном потоке во время прокрутки
- Приоритет: P2
- Файл: `AIHomework/Features/History/HistoryView.swift:229-244` (также используется в `SubjectView.swift:144-146`)
- Место в коде: `if let data = problem.thumbnailData, let image = UIImage(data: data) { Image(uiImage: image) ... }`
- Причина: при каждом появлении строки и каждом пересчёте body создаётся новый `UIImage`, и JPEG 360 px декодируется на main. Хранится 360 px, а показывается 48 pt (144 px @3x).
- Последствия: оценка 1–3 мс на строку; при быстрой прокрутке на 120 Гц (бюджет кадра 8,3 мс) 2–4 новые строки в одном кадре дают рывки.
- Решение: кэш декодированных миниатюр (`NSCache<NSUUID, UIImage>`), асинхронная подготовка `await UIImage(data:)?.byPreparingForDisplay()` в `.task(id: problem.id)` строки; новые миниатюры сохранять в 144–160 px.
- Сложность: S
- Статус проверки: требует замера на устройстве (Animation Hitches при прокрутке 500 записей; Time Profiler → `ImageIO`/`AppleJPEG` на главном потоке).

### PERF-8. Фильтрация истории считается несколько раз за один body, поиск — O(N) на каждый символ
- Приоритет: P2
- Файл: `AIHomework/Features/History/HistoryView.swift:17-34,54,110,119`; `AIHomework/Persistence/SolvedProblem.swift:64-69`
- Место в коде: вычисляемые `filtered` и `sections` (вызывает `filtered`) плюс `filtered.isEmpty` в `overlay` → две полные фильтрации и `Dictionary(grouping:)` за один пересчёт; `matches` три раза делает `lowercased()` на запись.
- Причина: вычисляемые свойства в body без мемоизации; нет задержки (debounce) у `.searchable`.
- Последствия: при 500–1000 записях оценочно 2–10 мс на символ запроса — заметно при наборе.
- Решение: в body один раз `let items = filtered; let groups = group(items)`; поиск через `localizedStandardContains` (без `lowercased()` копий) или `#Predicate` в `@Query`; задержка 200–300 мс для поиска (`.task(id: search)` + `Task.sleep`).
- Сложность: S
- Статус проверки: проверено чтением кода; стоимость — требует замера (SwiftUI instrument → View Body duration для `HistoryView`).

### PERF-9. Бесконечные анимации работают там, где они не нужны
- Приоритет: P2 (батарея, нагрев, частота ProMotion)
- Файл: `AIHomework/DesignSystem/AnimatedBackground.swift:53-73`; `AIHomework/Features/Home/HomeView.swift:75`; `AIHomework/Features/Solve/SolveFlowView.swift:65,261-263,281,311-316`; `AIHomework/Features/Solve/RegionSelectionView.swift:69-73`; `AIHomework/DesignSystem/Components.swift:253-280`
- Место в коде:
  - `AIOrb`: «дыхание» `repeatForever` 3,2 с на главном экране, всё время пока он видим; не останавливается в `onDisappear` (главный экран остаётся в стеке под «Историей»).
  - Ошибка логики: в `startAnimations()` `breathing = true` выставляется повторно, когда значение уже `true` → новая длительность не применяется, и после перехода к результату орб в верхней панели продолжает «дышать» с периодом 1,0 с; `rotation` с `repeatForever` при `isActive = false` заменяется анимацией к 0, но поведение замены `repeatForever` в SwiftUI ненадёжно.
  - `RegionSelectionView`: `dashPhase` анимируется бесконечно с момента появления, даже когда выделения нет.
  - На экране решения одновременно два `AIOrb` (вращение + дыхание), `ProgressView` и счётчик секунд с `withAnimation` раз в секунду.
  - `ShimmerBar` нигде не используется (мёртвый код, на работу не влияет).
- Причина: анимации SwiftUI на `@State` интерполируются в процессе приложения → обновление графа в каждом кадре; система не может снизить частоту экрана до 10–24 Гц.
- Последствия: постоянная нагрузка CPU/GPU на главном экране и на экране результата; на ProMotion — 120 Гц вместо адаптивной низкой частоты.
- Решение: в `onDisappear` сбрасывать состояние без анимации (`var t = Transaction(); t.disablesAnimations = true; withTransaction(t) { breathing = false; rotation = 0 }`); в `startAnimations` сначала сбрасывать `breathing = false`, затем запускать нужную анимацию; на главном экране и в результате оставить орб неподвижным (или iOS 18+: `.symbolEffect(.breathe)` — анимация в Core Animation); `dashPhase` запускать только при `selection != nil`.
- Сложность: S
- Статус проверки: проверено чтением кода; влияние — требует замера (Instruments → Animation Hitches + Core Animation FPS на главном экране в покое; Energy Log; ожидаемо: в покое частота кадров должна падать до минимальной).

### PERF-10. Размытие и масштабирование всего стека навигации под экраном решения
- Приоритет: P2
- Файл: `AIHomework/App/RootView.swift:24-31`
- Место в коде: `.scaleEffect(app.activeFlow == nil ? 1 : 0.94).blur(radius: app.activeFlow == nil ? 0 : 8)`, анимируется `withAnimation(Theme.spring)` из `AppModel.startSolve/closeFlow`.
- Причина: анимированное гауссово размытие всего экрана — отдельный проход отрисовки в каждом кадре перехода; после перехода размытый слой остаётся в иерархии под непрозрачным `SolveFlowView`, всё время пока открыт сценарий решения.
- Последствия: риск рывков при открытии и закрытии решения (оценка — на старых iPhone без ProMotion заметнее); лишняя работа GPU.
- Решение: анимировать только `opacity`/`scale`; после завершения перехода скрывать стек (`.opacity(app.activeFlow == nil ? 1 : 0)` с задержкой или `.hidden()`), либо показывать сценарий через `fullScreenCover`.
- Сложность: S
- Статус проверки: требует замера на устройстве (Animation Hitches: «открыть камеру → выбрать фото» и «закрыть»; Core Animation → Color Offscreen-Rendered).

### PERF-11. Слишком широкая зависимость наблюдения у настроек; сохранение и запись в Keychain на каждый символ
- Приоритет: P2
- Файл: `AIHomework/App/AppSettings.swift:52,76-84,103-111`; `AIHomework/App/AIHomeworkApp.swift:12-13`; `AIHomework/Features/Settings/SettingsView.swift:77-82`
- Место в коде: всё состояние — одно поле `var data: SettingsData`; почти каждый экран читает `app.l` → `settings.language` → `settings.data`; тело `App` читает `settings.locale` и `colorScheme`. В настройках: `.onChange(of: settings.data) { settings.save() }` и `.onChange(of: settings.apiKey) { settings.saveAPIKey() }`.
- Причина: Observation отслеживает свойство `data` целиком → ввод адреса или модели API делает недействительными тело `App`, `RootView`, `HomeView` и все видимые экраны. Каждый символ ключа — синхронный `SecItemUpdate` (межпроцессный вызов к `securityd`) на main.
- Последствия: оценка 1–10 мс на символ + перерисовка дерева под листом настроек → задержка ввода, особенно на старых устройствах.
- Решение: вынести `language`/`appearance` в отдельные хранимые свойства `@Observable` (тогда зависимость будет точечной); `save()` — с задержкой 300–500 мс; ключ сохранять по `onSubmit` / при закрытии листа.
- Сложность: S
- Статус проверки: проверено чтением кода; влияние — требует замера (SwiftUI instrument → View Body counts при вводе 30 символов в поле адреса).

### PERF-12. Экспорт PDF синхронно на главном потоке
- Приоритет: P2
- Файл: `AIHomework/Services/PDFExporter.swift:5-57`; вызовы: `AIHomework/Features/History/ProblemDetailView.swift:149-160`, `AIHomework/Features/Solve/SolveFlowView.swift:135-147`
- Место в коде: `@MainActor enum PDFExporter`; в истории ещё и `UIImage(data:)` полноразмерного фото прямо в обработчике нажатия.
- Причина: CoreText-вёрстка, отрисовка изображения 1600–2600 px в PDF и запись файла — на main.
- Последствия: оценка 50–300 мс зависания при нажатии «PDF» (длинные решения, фото).
- Решение: снять `@MainActor` (CoreText и `UIGraphicsPDFRenderer` можно вызывать вне main), выполнять в `Task.detached`, передавать изображение, заранее уменьшенное до ≈ 1000 px; показывать индикатор на кнопке.
- Сложность: M
- Статус проверки: проверено чтением кода; длительность — требует замера (Hangs / Time Profiler, сценарий: решение из 20+ шагов с фото).

### PERF-13. Брошенная по таймауту работа точного решателя продолжает занимать поток пула
- Приоритет: P2
- Файл: `AIHomework/Engine/Core/Deadline.swift:11-22`; `AIHomework/Engine/Math/Rational.swift:257-272`; `AIHomework/Engine/Math/Algebra.swift:104-106`
- Место в коде: `Task.detached(priority: .userInitiated) { gate.resume(work()) }` и второй `Task.detached`, который спит `seconds` и не отменяется.
- Причина: синхронная работа в `Task.detached` занимает поток кооперативного пула (их столько, сколько ядер), отмены нет — после 6 с результат отбрасывается, но CPU продолжает работать. Повторные «Заново» складывают такие задачи. В движке нет проверок отмены. `IntegerMath.primeFactors` перебирает делители до √n: **замерено** 1,3 с на n ≈ 10¹⁸ (Linux); условие `divisor * divisor <= n` переполнится (и приложение упадёт с trap) для простых n > 3 037 000 499² — теоретический случай; `simplifySquareRoot` (вызов из `Algebra.swift:106`) не ограничивает входное число. Задача «разложить на множители» ограничена 12 цифрами (`MathSolver.swift:863`) — там безопасно.
- Последствия: сейчас риск низкий (типичные решения 0,2–50 мс по бенчмарку), но любая будущая регрессия алгоритма превратится в фоновый расход CPU и голодание пула (в нём же выполняются нормализация изображения, определение предмета, продолжения сети).
- Решение: выполнять точный решатель на отдельной `DispatchQueue(label:qos:.userInitiated)`, а не в кооперативном пуле; передавать в движок флаг отмены (`ManagedAtomic<Bool>`/класс с lock) и проверять его в циклах `NumericRootFinder` и перебора; отменять задачу-таймер, когда работа завершилась первой; в `primeFactors` писать `while divisor <= n / divisor` и ограничить число итераций (например, 10⁷).
- Сложность: S
- Статус проверки: проверено чтением кода и микробенчмарком движка (Linux, release).

### PERF-14. Синхронное чтение буфера обмена и файла скриншота на главном потоке (в том числе на пути запуска с кнопки действия)
- Приоритет: P2
- Файл: `AIHomework/App/AppModel.swift:97-110`; `AIHomework/App/ScreenshotIntent.swift:46-53`; `AIHomework/App/RootView.swift:62-68`
- Место в коде: `pasteboard.hasImages, let image = pasteboard.image`; `Data(contentsOf: fileURL)` + `UIImage(data:)` в `ScreenshotInbox.consume()`, который вызывается из `onAppear` корневого экрана.
- Причина: `UIPasteboard.image` — синхронная передача данных между процессами (фото из «Фото» может весить десятки МБ); чтение PNG-скриншота (3–8 МБ) и его декодирование (≈ 14 МБ битмапа для 1290×2796) — на main, прямо на пути «кнопка действия → экран выделения».
- Последствия: оценка 10–60 мс для скриншота, до сотен мс для большого изображения в буфере; задержка ключевого сценария «одним нажатием».
- Решение: `UIPasteboard.general.itemProviders.first?.loadDataRepresentation(for: .image)` асинхронно; файл скриншота читать и даунсемплить в фоне (см. PERF-1), сценарий открывать с уже подготовленным изображением.
- Сложность: S
- Статус проверки: требует замера (`os_signpost` от `SolveScreenshotIntent.perform` до первого кадра `RegionSelectionView`; App Launch template при запуске через «Команды»).

### PERF-15. Одно изображение кодируется в JPEG трижды
- Приоритет: P3
- Файл: `AIHomework/Services/SolveCoordinator.swift:99-106`; `AIHomework/Features/Solve/SolveViewModel.swift:316-325`
- Место в коде: JPEG 1600 px/0.82 для API, затем снова 1600 px/0.8 и 360 px для истории — каждый раз заново через `normalized` (перерисовка).
- Причина: результат кодирования для API не передаётся в `save`.
- Последствия: оценка 30–100 мс лишнего CPU в фоне на каждое решение, лишний пик памяти.
- Решение: вернуть `imageData` из `SolveCoordinator` в `SolveOutcome` и сохранить его же; миниатюру делать из уже уменьшенной копии.
- Сложность: S
- Статус проверки: проверено чтением кода.

### PERF-16. OCR не отменяется и проходит дважды последовательно
- Приоритет: P3
- Файл: `AIHomework/Services/OCRService.swift:47-58,68-86`
- Место в коде: `withCheckedThrowingContinuation` + `DispatchQueue.global().async { handler.perform([request]) }`; второй проход без языковой коррекции при `mathDensity ≥ 0.18`.
- Причина: отмена `Task` (закрытие экрана) не доходит до `VNRequest`; для формул выполняются два полных прохода `.accurate`.
- Последствия: после закрытия сценария Vision ещё 0,3–2 с (оценка) жжёт CPU/ANE; для формул задержка ×2.
- Решение: `withTaskCancellationHandler { ... } onCancel: { request.cancel() }`; для формул — сразу запускать оба запроса одним `handler.perform([withCorrection, withoutCorrection])` (одна подготовка изображения) и выбирать результат.
- Сложность: S
- Статус проверки: проверено чтением кода; длительность проходов — требует замера (Time Profiler, `os_signpost` вокруг `perform`).

### PERF-17. Искусственные минимальные задержки увеличивают время до результата
- Приоритет: P3
- Файл: `AIHomework/Features/Solve/SolveViewModel.swift:145-147,277-278`; `AIHomework/Features/Solve/RegionSelectionView.swift:128-133`
- Место в коде: минимум 0,9 с на распознавание, 0,8 с на решение, 0,35 с после обводки.
- Причина: чтобы анимация «не мелькала».
- Последствия: точная задача, которая реально решается за ≈ 0,5 с (OCR + решатель за единицы мс), показывается не раньше чем через ≈ 2 с.
- Решение: оставить короткий минимум (≈ 0,3 с) или применять его, только если анимация уже успела начаться; это решение по UX — согласовать с владельцем.
- Сложность: S
- Статус проверки: проверено чтением кода.

### PERF-18. Регулярные выражения компилируются при каждом вызове; разбор ответа модели — на главном потоке
- Приоритет: P3
- Файл: `AIHomework/Engine/Core/TextUtilities.swift:21-37`; `AIHomework/Engine/Core/ModelPrompting.swift:99-124,167-177`; вызов `AIHomework/Services/SolveCoordinator.swift:186`
- Место в коде: `try? NSRegularExpression(pattern:options:)` внутри `Rx.ranges`/`Rx.replace`; в `appendStep` — две регулярки на каждую строку ответа.
- Причина: кэша скомпилированных выражений нет.
- Последствия: **замерено** (Linux): компиляция + поиск ≈ 8 мкс за вызов — для движка пренебрежимо; `ModelPrompting.parse` ответа 24 КБ ≈ 19 мс, типичного (2–6 КБ) ≈ 2–5 мс — на 120 Гц это может стоить кадр в момент показа результата.
- Решение: кэш `[String: NSRegularExpression]` под `NSLock` в `Rx`; `parse` вызывать в `Task.detached` (функция чистая, `Solution` — `Sendable`).
- Сложность: S
- Статус проверки: проверено чтением кода и микробенчмарком.

### PERF-19. Тактильный отклик: генераторы создаются на каждый вызов без `prepare()`, отклик срабатывает дважды
- Приоритет: P3
- Файл: `AIHomework/Services/Haptics.swift:39-48`; `AIHomework/DesignSystem/Buttons.swift:13-15`
- Место в коде: `UIImpactFeedbackGenerator(style:)` на каждое касание; `PressableButtonStyle` вызывает `Haptics.tap()` при нажатии, и многие действия вызывают `Haptics.tap()/press()` ещё раз.
- Причина: без `prepare()` Taptic Engine «просыпается» с задержкой; двойной вызов.
- Последствия: заметная задержка или «смазанный» отклик; мелкие затраты на main.
- Решение: держать по одному генератору на стиль, вызывать `prepare()` в начале жеста; убрать дублирующий отклик (или из стиля кнопки, или из действий).
- Сложность: S
- Статус проверки: проверено чтением кода.

### PERF-20. Нет инструментирования производительности
- Приоритет: P3
- Файл: весь проект (поиск `os_signpost|OSSignposter|MetricKit` — 0 совпадений)
- Место в коде: —
- Причина: без меток нельзя измерить этапы и поймать регрессии, тем более без Mac.
- Последствия: жалобы вида «бесконечно решает» невозможно разложить на этапы (OCR / диспетчер / сеть / модель).
- Решение: `OSSignposter(subsystem: "aihomework", category: "solve")` с интервалами `ingest`, `normalize`, `ocr`, `route`, `exact`, `model`, `save`; `MXMetricManager` (MetricKit) — подписка на `MXAppLaunchMetric`, `MXHangDiagnostic`, `MXMemoryMetric` с сохранением отчётов в файл и кнопкой «Поделиться диагностикой» в настройках (работает без Mac).
- Сложность: S
- Статус проверки: проверено чтением кода.

### PERF-21. Запуск: синхронное чтение Keychain и выборка истории на пути к первому кадру
- Приоритет: P3
- Файл: `AIHomework/App/AIHomeworkApp.swift:6,15`; `AIHomework/App/AppSettings.swift:56-66,91-93`; `AIHomework/Features/Home/HomeView.swift:9-34`
- Место в коде: `@State private var app = AppModel()` → `AppSettings.init` → `loadAPIKey()` → `SecItemCopyMatching`; `.modelContainer(for:)`; `@Query` всех записей; 7 модификаторов `.staggered` и `AIOrb` в первом кадре.
- Причина: всё синхронно на main до первого кадра.
- Последствия: оценочно укладывается в 400 мс при небольшой истории; растёт с историей (см. PERF-6).
- Решение: ключ читать лениво при первом обращении к `remoteConfig`; главный экран — с `fetchLimit` (PERF-6).
- Сложность: S
- Статус проверки: требует замера (App Launch template; MetricKit `MXAppLaunchMetric.histogrammedTimeToFirstDraw`).

**Замечание вне области (передать эксперту по корректности движка):** при бенчмарке `x^2 + 1000000001x + 1 = 0`
и `x^2 + 3000000001x + 1 = 0` движок отвечает «Действительных корней нет» с примечаниями «Значение x ≈ −1000000001 / x ≈ 0
не прошло проверку подстановкой и отброшено», хотя дискриминант положителен (для `x^2 + 100001x + 1 = 0` ответ верный).
Похоже, проверка подстановкой в `Double` отбрасывает верные корни при больших коэффициентах. На производительность не влияет.

## План замеров

Ограничение: Instruments требует Mac. Варианты без Mac: (а) встроенная диагностика — `OSSignposter` + собственный
журнал длительностей (`ContinuousClock`) с экспортом из настроек; (б) MetricKit (`MXHangDiagnostic`, `MXAppLaunchMetric`,
`MXAnimationMetric.scrollHitchTimeRatio`, `MXMemoryMetric.peakMemoryUsage`) — отчёты приходят раз в сутки;
(в) iOS «Настройки → Для разработчиков → Обнаружение зависаний» (Hang Detection) — доступно при включённом режиме
разработчика, который нужен для сайдлоада; наличие пункта проверить на устройстве. С Mac — Instruments по таблице ниже.

| # | Сценарий | Инструмент | Метрика | Целевой бюджет |
|---|---|---|---|---|
| 1 | Холодный запуск, история 0 / 100 / 1000 записей | App Launch template; MetricKit `timeToFirstDraw` | время до первого кадра | **< 400 мс** до первого кадра на iPhone 12+; рост от 0 до 1000 записей < 100 мс |
| 2 | Кнопка действия → «Сделать снимок экрана» → «Решить скриншот» → экран выделения | `os_signpost` от `SolveScreenshotIntent.perform` до появления `RegionSelectionView`; Hangs | время до интерактивности | < 700 мс после открытия приложения; нет зависаний > 100 мс |
| 3 | Фото из галереи 12 / 24 / 48 Мп и ProRAW → экран выделения → «Решить всё» | Allocations + VM Tracker (Dirty Memory), Hangs, Time Profiler (main) | пик памяти, зависания | пик **< 300 МБ** для 48 Мп; нет зависаний > 100 мс на main |
| 4 | Сканер, 1 и 4 страницы | то же | пик памяти, длительность на main | < 250 МБ; нет зависаний > 250 мс |
| 5 | Распознавание: обычный текст и формулы (два прохода) | `os_signpost` «ocr», Time Profiler | длительность OCR | ориентир < 1,5 с на фрагмент; отмена при закрытии < 100 мс |
| 6 | Решение по API на Wi-Fi и через Network Link Conditioner (LTE, 3G) | Network instrument; signposts «route», «model» | размер тела запроса, время каждого этапа | тело диспетчера < 150 КБ; первая обратная связь (маршрут) < 3 с на LTE |
| 7 | Текстовое задание по русскому языку ≈ 2000 символов (холодный и горячий старт) | Time Profiler, фильтр главного потока; signpost вокруг `LanguageTools.analyze` | время на main | **0 мс** на main после переноса; до переноса — зафиксировать базовую цифру |
| 8 | Прокрутка истории 500 записей с миниатюрами, быстрый свайп | Animation Hitches; Core Animation FPS; MetricKit `scrollHitchTimeRatio` | доля времени с рывками, FPS | **120 FPS** на ProMotion (60 FPS на остальных); hitch ratio **< 5 мс/с** |
| 9 | Поиск в истории (500 записей), ввод 10 символов | SwiftUI instrument (View Body), Time Profiler | длительность body на символ | < 4 мс на символ |
| 10 | Экран записи истории: открыть, «Скопировать» (всплывающее сообщение), «Избранное» | SwiftUI instrument → View Body; Time Profiler (`ImageIO` на main) | число и длительность пересчётов body | нет декодирования изображений на main; body < 2 мс |
| 11 | Экспорт PDF длинного решения с фото | Hangs | длительность на main | нет зависаний > 100 мс (после переноса в фон) |
| 12 | Главный экран в покое 30 с; экран результата в покое 30 с | Core Animation FPS; Energy Log; Animation Hitches | частота кадров в покое | частота падает до минимальной (нет постоянных кадров от `AIOrb`) |
| 13 | Открытие и закрытие сценария решения | Animation Hitches; Core Animation (Offscreen-Rendered) | рывки перехода | hitch ratio < 5 мс/с, без offscreen-проходов на весь экран |
| 14 | Ввод 30 символов в поле адреса/ключа API | SwiftUI instrument (View Body counts); Time Profiler (`SecItemUpdate`) | перерисовки и вызовы Keychain на символ | перерисовывается только лист настроек; 0 вызовов Keychain при вводе |
| 15 | Длительная работа: 20 решений подряд с закрытием посреди процесса | Allocations (Generations), Leaks | рост памяти между поколениями | нет роста после закрытия сценария; `SolveViewModel` освобождается |

Движок отдельно: микробенчмарк (как в этом аудите) можно закрепить тестом производительности `XCTestCase.measure`
в `EngineTests` с порогом, например, «все примеры каталога < 20 мс суммарно» — это работает на Linux в CI.
