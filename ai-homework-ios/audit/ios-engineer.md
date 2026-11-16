# Аудит платформенной части iOS: Senior iOS Engineer

Область: `AIHomework/App/*`, `Shared/*`, `AIHomeworkControls/*`, `Features/Capture/*`, `Persistence/*`,
`project.pbxproj`, `Resources/*`, CI (`.github/workflows/ai-homework-ios.yml`, `codemagic.yaml`, `scripts/*`).
Там, где это нужно для выводов о жизненном цикле, памяти и concurrency, я читал и смежные файлы
(`SolveViewModel`, `ImageTools`, `RemoteAPIProvider`, `Deadline`, `Settings/History`).
Всё, что ниже, получено чтением кода. Компиляцию и запуск в этой среде проверить нельзя (нет macOS/Xcode).

## Инвентарь

| Функция | Статус | Основание |
|---|---|---|
| Запуск приложения, сцена, контейнер SwiftData | работает по коду | `AIHomework/App/AIHomeworkApp.swift:4-16` |
| Сохранение настроек (UserDefaults), терпимое чтение старых версий | работает по коду | `AIHomework/App/AppSettings.swift:33-45`, `:56-73` |
| Ключ API в Связке ключей | работает по коду | `AIHomework/Services/KeychainStore.swift:25-44`, `AppSettings.swift:91-97` |
| Язык интерфейса и тема (в приложении) | работает по коду | `AIHomeworkApp.swift:12-13`, `AppSettings.swift:76-111` |
| Камера (UIImagePickerController) | частично: нет обработки отказа в доступе | `Features/Capture/CapturePickers.swift:6-48`, `AppModel.swift:71-81` |
| Галерея (PhotosPicker) | работает по коду, без уменьшения при загрузке | `RootView.swift:41-52` |
| Сканер документов VisionKit | частично: склейка до 4 страниц с сильной потерей разрешения | `CapturePickers.swift:80-118`, `ImageTools.swift:18-34` |
| Вставка из буфера обмена | работает по коду, каждый раз системный запрос на вставку | `AppModel.swift:97-110` |
| Ввод задания текстом | работает по коду | `AppModel.swift:112-114` |
| App Shortcuts (Siri, Spotlight, «Команды») | работает по коду; русские фразы без локализации | `App/AppShortcuts.swift:5-27` |
| Интент «Решить скриншот» для кнопки действия | работает по коду, требует проверки на устройстве | `App/ScreenshotIntent.swift:10-54`, `AppModel.swift:119-128` |
| Интент «Решить задание» с выбором способа ввода | работает по коду | `Shared/QuickActionIntent.swift:32-57` |
| Элементы управления iOS 18 (Пункт управления, кнопка действия) | частично: выполнение интента в процессе приложения не гарантировано | `AIHomeworkControls/AIHomeworkControls.swift:7-37`, `QuickActionIntent.swift:61-76` |
| Быстрое действие с любого экрана (закрытие открытых окон) | работает по коду, держится на задержке 450 мс | `AppModel.swift:131-176` |
| История: запись, избранное, поиск, удаление | работает по коду | `Persistence/SolvedProblem.swift`, `Features/History/HistoryView.swift:182-193` |
| Сохранение фото задания (JPEG 1600 px, миниатюра 360 px) | работает по коду | `SolveViewModel.swift:316-325`, `SolvedProblem.swift:19-20` |
| Миграции схемы SwiftData | отсутствует | `AIHomeworkApp.swift:15` (нет `VersionedSchema`/`SchemaMigrationPlan`) |
| PDF и «Поделиться» | работает по коду | `Services/PDFExporter.swift:10-57`, `TextToolsSection.swift:207-221` |
| Apple Intelligence (iOS 26) за `canImport` и `#available` | работает по коду, если сборка шла с iOS 26 SDK | `Services/AppleIntelligenceProvider.swift:3-5`, `:21`, `:83` |
| Системный перевод (iOS 17.4+) | работает по коду | `Features/Solve/TextToolsSection.swift:182-191` |
| Продолжение запроса при уходе приложения в фон | отсутствует | нет `beginBackgroundTask` во всём проекте |
| Реакция на нехватку памяти | отсутствует | нет подписки на `didReceiveMemoryWarningNotification` |
| Локализация Info.plist и строк интентов (RU/EN) | работает по коду | `Resources/InfoPlist.xcstrings`, `Shared/Localizable.xcstrings` (15 ключей, en+ru) |
| Сборка .ipa в GitHub Actions и публикация источника SideStore | работает (CI зелёный) | `.github/workflows/ai-homework-ios.yml:33-114`, `scripts/make_sidestore_source.py` |
| Запасная сборка в Codemagic | работает по коду, не проверено | `codemagic.yaml` (корень репозитория) |
| Unit- и UI-тесты приложения (не движка) | отсутствует | в `project.pbxproj` только 2 таргета: приложение и расширение (`:180-183`) |

## Сильные стороны

1. **Согласованные системы координат при обрезке.** Ориентация приводится к `.up` до обрезки
   (`ImageTools.swift:18-34`), выделение хранится в долях от `image.size`, где UIKit уже учёл ориентацию
   (`RegionSelectionView.swift:80-104`), а Vision получает `orientation: .up` (`OCRService.swift:76`).
   Поэтому не возникает типичной ошибки, когда снимок с камеры (`.right`) обрезается повёрнутым.
2. **Тяжёлая работа с изображениями идёт не на главном потоке.** Нормализация, обрезка и JPEG выполняются в
   `Task.detached` (`SolveViewModel.swift:93`, `:129`, `:320`; `SolveCoordinator.swift:103`), Vision работает на
   глобальной очереди (`OCRService.swift:70`). `UncheckedSendable` (`ImageTools.swift:5-11`) используется
   только для неизменяемых `UIImage`/`CGImage`, а `UIGraphicsImageRenderer` можно вызывать с любого потока.
   Это честный обход строгой проверки Swift 6, а не маскировка гонки данных.
3. **Быстрые действия обходятся без App Group и entitlements.** Интент кладёт запрос в «почтовый ящик»
   (`QuickActionIntent.swift:61-76`, `ScreenshotIntent.swift:32-54`), а приложение забирает его в трёх точках:
   `onAppear`, `scenePhase == .active` и уведомление (`RootView.swift:62-68`). Так покрыт холодный запуск, возврат из
   фона и случай, когда приложение уже открыто. `removeObject` перед обработкой исключает двойной запуск.
   Для сайдлоада это важно: переподписи SideStore нечего ломать.
4. **Модель истории почти не требует миграций.** Решение хранится одним JSON-блобом (`SolvedProblem.swift:17-18`,
   `:51-53`), фото лежит во внешнем файле (`@Attribute(.externalStorage)`, `:19`). Структуру `Solution` можно менять,
   не трогая схему SQLite, а крупные данные не раздувают базу.
5. **Доступность API разведена правильно.** Расширение с ControlWidget собирается под iOS 18
   (`project.pbxproj:429`, `:458`), приложение при этом остаётся на iOS 17 (`:366`, `:401`). FoundationModels закрыт
   и `canImport`, и `#available(iOS 26.0, *)` (`AppleIntelligenceProvider.swift:3`, `:21`, `:83`), перевод закрыт
   `#available(iOS 17.4, *)`. В CI `MARKETING_VERSION` переопределяется сразу для всех таргетов (`ai-homework-ios.yml:63`),
   поэтому версии приложения и расширения совпадают, а система этого требует.
6. **Секреты хранятся правильно.** Ключ лежит в Связке ключей с `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
   (`KeychainStore.swift:33-36`) и не попадает ни в `UserDefaults`, ни в резервные копии на другое устройство.
   Настройки читаются поле за полем с откатом к значениям по умолчанию (`AppSettings.swift:33-45`), так что
   обновление приложения не сбрасывает их.

## Находки

### IOS-1. Сканер документов: при склейке страниц текст становится нечитаемым, пик памяти приходится на главный поток
- Приоритет: P1
- Файл: `AIHomework/Features/Capture/CapturePickers.swift:81-118`; `AIHomework/Services/ImageTools.swift:18-34`; `AIHomework/Features/Solve/SolveViewModel.swift:89-97`, `:129-135`; `AIHomework/Services/SolveCoordinator.swift:99-106`
- Место в коде: `documentCameraViewController(_:didFinishWith:)`, `DocumentScanner.stack(_:)`, `ImageTools.normalized(_:maxDimension:)`
- Причина: до 4 страниц склеиваются в одну вертикальную полосу в полном разрешении (`format.scale = 1`, `:109-110`).
  Затем `normalized` ограничивает **длинную** сторону до 2600 px. Для страницы примерно 2500×3300 px склейка из 4 страниц
  даёт около 2500×13200, и после уменьшения ширина каждой страницы становится около 490 px. Для API
  (`maxDimension: 1600`) остаётся около 300 px. Страницы после четвёртой отбрасываются молча (`:87`).
  `stack` относится к расширению `View`, то есть выполняется на главном акторе: 4 декодированные страницы плюс битмап
  склейки (около 130 МБ) рисуются на главном потоке.
- Последствия: при сканировании 2–4 страниц OCR почти ничего не находит, ответ модели по картинке становится случайным.
  Интерфейс замирает после нажатия «Сохранить» в сканере, на старых iPhone возможна выгрузка по памяти (jetsam).
  Пользователь не узнаёт, что 5-я и следующие страницы потеряны.
- Решение: (а) ограничивать изображение **бюджетом пикселей**, а не только длинной стороной; (б) уменьшать каждую страницу до склейки
  и делать склейку вне главного потока; (в) предупреждать, если страниц больше 4 (или брать по умолчанию первую). Минимальная правка без смены архитектуры:
  ```swift
  // ImageTools
  static func normalized(_ image: UIImage, maxDimension: CGFloat = 2600, maxPixels: CGFloat = 12_000_000) -> UIImage {
      let size = image.size
      guard size.width > 0, size.height > 0 else { return image }
      let byLongSide = maxDimension / max(size.width, size.height)
      // Для высоких склеек ограничиваем площадь, а не длину, иначе ширина становится крошечной.
      let isTall = max(size.width, size.height) / min(size.width, size.height) > 2.2
      let scale = min(1, isTall ? sqrt(maxPixels / (size.width * size.height)) : byLongSide)
      ...
  }
  // CapturePickers: страницы уменьшаем до ширины ≤ 1800 px до склейки, склеиваем в Task.detached.
  ```
  Для API в `SolveCoordinator.swift:104` и для истории в `SolveViewModel.swift:321` тоже стоит перейти на бюджет около 3 МП.
- Сложность: M
- Статус проверки: проверено чтением кода (арифметика уменьшения); размеры страниц VisionKit и пик памяти требуют проверки на устройстве

### IOS-2. Запрос к API обрывается, если во время решения свернуть приложение
- Приоритет: P1
- Файл: `AIHomework/Features/Solve/SolveViewModel.swift:259-291`; `AIHomework/Services/RemoteAPIProvider.swift:90-141`; `AIHomework/App/RootView.swift:63-65`
- Место в коде: `SolveViewModel.solve(context:)` → `RemoteAPIProvider.send` → `URLSession.shared.data(for:)`
- Причина: в проекте нет `UIApplication.beginBackgroundTask`. Ответ модели приходит за 5–75 секунд
  (`solveTimeout = 75`), а приложение, свёрнутое без фоновой задачи, приостанавливается через несколько секунд. Сокет
  закрывается, и после возврата запрос завершается ошибкой `NSURLErrorNetworkConnectionLost` (−1005). Единственная повторная
  попытка (`:97-100`) начинается заново, а общий лимит `Deadline.run` всё это время продолжает отсчитываться.
  `scenePhase` используется только для быстрых действий, незавершённое решение по нему не восстанавливается.
- Последствия: школьник отправляет задание и переключается в мессенджер, а по возвращении видит «сетевое соединение потеряно»
  или «модель не ответила вовремя». Это одно из правдоподобных объяснений жалобы владельца (вторая версия связана с VPN, повтор её уже учитывает).
- Решение: просить у системы время на завершение (около 30 с) и предлагать повтор после возврата:
  ```swift
  workTask = Task {
      let bg = UIApplication.shared.beginBackgroundTask(withName: "solve")   // истечение: система сама завершит
      defer { UIApplication.shared.endBackgroundTask(bg) }
      ...
  }
  ```
  Кроме того, нужно запоминать, что сбой сети случился, пока приложение было в фоне, и при `scenePhase == .active` автоматически повторять
  запрос один раз или показывать кнопку «Повторить». Фоновый `URLSession` здесь избыточен: он рассчитан на передачу файлов.
- Сложность: S
- Статус проверки: требует проверки на устройстве

### IOS-3. Тексты о приватности расходятся с реальной отправкой данных (вопрос к владельцу)
- Приоритет: P1
- Файл: `AIHomework.xcodeproj/project.pbxproj:361`, `:396`; `AIHomework/Resources/InfoPlist.xcstrings:28`, `:34`; `scripts/make_sidestore_source.py:69`; `AIHomework/Features/Settings/SettingsView.swift:199-200`, `:349-350`
- Место в коде: `NSCameraUsageDescription`, подвал раздела «Нейросеть по API», раздел «Конфиденциальность»
- Причина: системный запрос доступа к камере говорит «Photos are processed on this device / Фотографии обрабатываются на
  этом устройстве». В настройках написано, что фрагмент уходит в API «только когда точные алгоритмы не справились». По коду
  при настроенном API **каждое** задание (текст и JPEG фрагмента) сначала отправляется диспетчеру
  (`SolveCoordinator.swift:101-118`), и только потом решается локальным решателем.
- Последствия: пользователь и родители получают неверные сведения о том, куда уходят фото. Это противоречит заявленному
  требованию владельца «не отправлять фото на внешние серверы». Строка повторена в трёх местах, и при следующей
  правке их легко рассинхронизировать.
- Решение: владельцу нужно выбрать политику: (а) диспетчер получает только текст, а изображение уходит лишь при отсутствии текста;
  (б) отправку изображения включает отдельный переключатель; (в) всё остаётся как есть, но с честным текстом.
  В любом случае тексты нужно исправить, например: «Камера нужна, чтобы сфотографировать задание. Текст распознаётся на iPhone; если вы
  подключили свой API, выделенный фрагмент отправляется на указанный вами адрес». Подвал на `:199` и пункт на `:349`
  следует привести к фактическому порядку. В скрипте строку лучше читать из `InfoPlist.xcstrings`, а не держать копию.
- Сложность: S
- Статус проверки: проверено чтением кода

### IOS-4. Отказ в доступе к камере и ошибки сканера обрабатываются молча
- Приоритет: P2
- Файл: `AIHomework/App/AppModel.swift:67-90`; `AIHomework/Features/Capture/CapturePickers.swift:95-97`
- Место в коде: `openCamera()`, `openScanner()`, `documentCameraViewController(_:didFailWithError:)`
- Причина: проверяется только наличие камеры (`isSourceTypeAvailable`, `VNDocumentCameraViewController.isSupported`),
  статус разрешения (`AVCaptureDevice.authorizationStatus(for: .video)`) не проверяется. Ошибка сканера превращается
  в `onCancel()` без сообщения.
- Последствия: если пользователь однажды нажал «Не разрешать» (или доступ закрыт Экранным временем), камера открывается чёрным экраном
  или сразу закрывается. Объяснения и ссылки в Настройки нет. Кнопка действия «Камера» ведёт себя так же.
- Решение:
  ```swift
  switch AVCaptureDevice.authorizationStatus(for: .video) {
  case .authorized: capture = .camera
  case .notDetermined:
      Task { if await AVCaptureDevice.requestAccess(for: .video) { capture = .camera } else { showCameraDenied() } }
  default: showCameraDenied()   // alert с кнопкой UIApplication.openSettingsURLString и «Выбрать из галереи»
  }
  ```
  В `didFailWithError` нужно передавать текст ошибки в `alertMessage`.
- Сложность: S
- Статус проверки: проверено чтением кода; вид экрана при отказе требует проверки на устройстве

### IOS-5. Изображения из галереи, камеры и буфера декодируются целиком; маленькое выделение теряет разрешение
- Приоритет: P2
- Файл: `AIHomework/App/RootView.swift:46`; `CapturePickers.swift:37`; `AppModel.swift:100`; `SolveViewModel.swift:89-97`, `:129-131`
- Место в коде: `loadTransferable(type: Data.self)` → `UIImage(data:)`; `ImageTools.normalized` перед `crop`
- Причина: фото 24/48 МП (HEIC) декодируется полностью, при показе в `RegionSelectionView` получается 100–200 МБ битмапа.
  Затем ещё одна полная отрисовка уходит на нормализацию. Обрезка делается **после** уменьшения до 2600 px, поэтому
  выделенная мелкая формула на 48-МП фото теряет до 70% пикселей. Реакции на нехватку памяти нет.
- Последствия: пики памяти и возможная выгрузка приложения на устройствах с 4–6 ГБ памяти. OCR работает хуже на мелких выделениях,
  а это прямо связано с жалобой «x читается как ×».
- Решение: декодировать сразу с уменьшением через ImageIO и обрезать по оригиналу:
  ```swift
  static func downsampled(_ data: Data, maxPixel: CGFloat = 4000) -> UIImage? {
      guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
      let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,   // сразу .up
                  kCGImageSourceShouldCacheImmediately: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary
      return CGImageSourceCreateThumbnailAtIndex(src, 0, opts).map { UIImage(cgImage: $0) }
  }
  ```
  В `recognize` сначала выполнять обрезку по оригиналу (после приведения ориентации), а уже потом ограничивать размер. Показывать в UI копию
  размером около 2000 px. При `didReceiveMemoryWarning` освобождать оригинал, если уже есть нормализованная копия.
- Сложность: M
- Статус проверки: проверено чтением кода; пики памяти требуют проверки на устройстве

### IOS-6. Элемент управления (iOS 18) может не довести действие до приложения
- Приоритет: P2
- Файл: `AIHomeworkControls/AIHomeworkControls.swift:15-37`; `Shared/QuickActionIntent.swift:32-76`
- Место в коде: `ControlWidgetButton(action: SolveHomeworkIntent(...))`, `QuickActionInbox.post`
- Причина: интент компилируется в оба таргета и рассчитывает, что при `openAppWhenRun = true` система выполнит `perform()`
  в процессе приложения. Документированный Apple способ открыть приложение из элемента управления — интент, соответствующий `OpenIntent`.
  Если `perform` выполнится в процессе расширения, `UserDefaults.standard` и `NotificationCenter.default` окажутся
  чужими (у расширения свой контейнер). Приложение откроется, но камера не запустится, и ошибки никто не увидит. В iOS 26
  `openAppWhenRun` объявлен устаревшим, рекомендован `supportedModes`.
- Последствия: кнопка действия, назначенная на элемент управления, «просто открывает приложение». На iOS 17 элемент управления отсутствует, это ожидаемо.
- Решение: сначала проверить на устройстве (холодный и тёплый запуск, из Пункта управления и с кнопки действия). Если действие теряется,
  добавить отдельный интент только для элементов управления:
  ```swift
  struct OpenSolveIntent: OpenIntent {          // в Shared, оба таргета
      static let title: LocalizedStringResource = "Solve homework"
      @Parameter(title: "Input method") var target: QuickAction
      init() {}; init(_ a: QuickAction) { target = a }
      @MainActor func perform() async throws -> some IntentResult { QuickActionInbox.post(target); return .result() }
  }
  ```
  `SolveHomeworkIntent` нужно оставить как есть, иначе пользовательские команды со ссылкой на параметр `action` сломаются. App Group вводить не стоит:
  с бесплатным Apple ID это лишняя регистрация в SideStore.
- Сложность: S
- Статус проверки: требует проверки на устройстве

### IOS-7. SwiftData без версионированной схемы и без обработки ошибки открытия хранилища
- Приоритет: P2
- Файл: `AIHomework/App/AIHomeworkApp.swift:15`; `AIHomework/Persistence/SolvedProblem.swift:6-20`
- Место в коде: `.modelContainer(for: SolvedProblem.self)`; объявления свойств `@Model`
- Причина: нет `VersionedSchema`/`SchemaMigrationPlan`, у свойств нет значений по умолчанию в объявлении (они задаются только в `init`).
  При первой несовместимой правке модели (новое необязательное поле без значения по умолчанию, переименование, `@Attribute(.unique)` на `id`)
  лёгкая миграция не сработает. Приложение не может ни перехватить такую ошибку открытия, ни сообщить о ней.
- Последствия: после обновления через SideStore возможен вылет на старте или потеря истории. Без Mac пользователь
  не сможет даже вытащить базу.
- Решение: зафиксировать текущую схему как V1 и создать контейнер явно:
  ```swift
  enum SchemaV1: VersionedSchema {
      static let versionIdentifier = Schema.Version(1, 0, 0)
      static var models: [any PersistentModel.Type] { [SolvedProblem.self] }
  }
  enum HomeworkMigrationPlan: SchemaMigrationPlan {
      static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
      static var stages: [MigrationStage] { [] }
  }
  // AIHomeworkApp: do { try ModelContainer(for: SolvedProblem.self, migrationPlan: HomeworkMigrationPlan.self) }
  // catch { лог + контейнер isStoredInMemoryOnly + баннер «История недоступна» }
  ```
  Свойствам стоит дать значения по умолчанию в объявлении (`var isFavorite = false` и т. п.).
- Сложность: S
- Статус проверки: проверено чтением кода

### IOS-8. Ошибки сохранения в SwiftData и Связку ключей проглатываются
- Приоритет: P2
- Файл: `SolveViewModel.swift:313`, `:329`, `:339`; `HistoryView.swift:185`, `:192`; `ProblemDetailView.swift:79`, `:116`; `SettingsView.swift:80-82`, `:90-91`; `AppSettings.swift:95-97`; `KeychainStore.swift:24-44`
- Место в коде: `try? context.save()`, `KeychainStore.write` с `@discardableResult`
- Причина: ни одна ошибка записи не логируется и не показывается. Ключ записывается в Связку ключей на **каждое нажатие клавиши**
  (`onChange(of: settings.apiKey)`), синхронно на главном потоке. Результат записи отбрасывается.
- Последствия: при заполненном диске или сбое Связки ключей пользователь уверен, что задание сохранено и ключ записан, но после
  перезапуска не находит ни того, ни другого. Диагностировать такое без Mac почти невозможно.
- Решение: единая обёртка `func persist(_ context: ModelContext) -> Bool` с `os.Logger` и toast «Не удалось сохранить».
  Ключ сохранять по `onSubmit`/при закрытии настроек (или с задержкой 0,5 с), при `false` показывать ошибку в разделе API.
- Сложность: S
- Статус проверки: проверено чтением кода

### IOS-9. Две разные реализации «Удалить всю историю»
- Приоритет: P2
- Файл: `AIHomework/Features/Settings/SettingsView.swift:89-93`; `AIHomework/Features/History/HistoryView.swift:188-193`
- Место в коде: `try? context.delete(model: SolvedProblem.self)` и цикл `context.delete(problem)`
- Причина: в настройках используется пакетное удаление на уровне хранилища, которое обходит объекты контекста. На iOS 17 замечено, что после
  него `@Query` не обновляется до перезапуска, а уже загруженные объекты остаются в памяти. В истории удаление
  поштучное и корректно обновляет список.
- Последствия: после «Удалить всё» на главном экране могут оставаться «Последние решения» и счётчик, а нажатие на такую
  карточку открывает «Задание удалено».
- Решение: использовать одну функцию (например, `HistoryStore.deleteAll(context)`) с fetch и поштучным `delete` плюс `save()`.
  Если нужно пакетное удаление, после него вызвать `context.rollback()`/пересоздать запросы.
- Сложность: S
- Статус проверки: требует проверки на устройстве

### IOS-10. Главный экран и экран предмета загружают всю историю вместе с миниатюрами и JSON решений
- Приоритет: P2
- Файл: `AIHomework/Features/Home/HomeView.swift:9`, `:152`, `:210-211`; `AIHomework/Features/Subjects/SubjectView.swift:9`, `:14`; `AIHomework/Features/History/ProblemDetailView.swift:48`, `:124`
- Место в коде: `@Query(sort: \SolvedProblem.createdAt, order: .reverse)` без `fetchLimit` и предиката
- Причина: на главном экране видно 10 карточек, но загружаются все записи (миниатюра около 20–40 КБ хранится в строке и попадает в выборку).
  Фильтрация по предмету идёт в памяти. В `ProblemDetailView` JSON решения и JPEG 1600 px декодируются в `body`
  при каждой перерисовке (например, при показе toast).
- Последствия: с ростом истории (сотни записей за учебный год) главный экран открывается медленнее и потребляет десятки МБ.
- Решение: `FetchDescriptor` с `fetchLimit = 10` для «Последних», `context.fetchCount` для счётчиков,
  `#Predicate { $0.subjectRaw == raw }` в `SubjectView`. В деталях декодировать `solution` и `UIImage` один раз в `.task` и хранить в `@State`.
- Сложность: S
- Статус проверки: проверено чтением кода; влияние на скорость требует проверки на устройстве

### IOS-11. Лимит времени не срабатывает, если операция не реагирует на отмену; зависшие вычисления продолжают работать
- Приоритет: P2
- Файл: `AIHomework/Engine/Core/Deadline.swift:11-22`, `:26-39`; `AIHomework/Services/SolveCoordinator.swift:182-184`; `AIHomework/Services/OCRService.swift:68-86`
- Место в коде: `Deadline.run` (`withThrowingTaskGroup`), `Deadline.compute`, `OCRService.perform`
- Причина: группа задач не завершается, пока не закончатся **все** дочерние задачи. `cancelAll()` только просит
  отмену, поэтому `Deadline.run` вернётся вовремя, только если операция кооперативно отменяется (у `URLSession` так и есть,
  у `LanguageModelSession.respond` это не проверено). `Deadline.compute` по истечении времени просто перестаёт ждать, а
  вычисление продолжает занимать ядро. OCR вообще не отменяется (continuation на глобальной очереди без проверки отмены).
- Последствия: возможное «бесконечно решает» с Apple Intelligence. После закрытия экрана нагрев и расход батареи от
  брошенных вычислений, а при повторных попытках они накапливаются.
- Решение: в `run` возвращать результат через continuation с `ResumeOnce` (как в `compute`) и не ждать проигравшую задачу.
  В решателях периодически проверять флаг отмены (передавать `@Sendable () -> Bool`). В `OCRService.perform` хранить
  `VNRecognizeTextRequest` и вызывать `cancel()` в `withTaskCancellationHandler`. Поведение `run` с неотменяемой операцией можно
  проверить тестом прямо в SwiftPM на Linux.
- Сложность: M
- Статус проверки: проверено чтением кода; поведение FoundationModels при отмене требует проверки на устройстве

### IOS-12. CI публикует сборку без проверки тестов и не защищён от «тихой» потери функций
- Приоритет: P2
- Файл: `.github/workflows/ai-homework-ios.yml:33`, `:44-47`, `:78`, `:73-82`; `codemagic.yaml:10`
- Место в коде: джоб `ipa`, шаги «Select newest Xcode», «Package .ipa», «Publish for SideStore»
- Причина: (1) у `ipa` нет `needs: engine-tests`, поэтому релиз `ai-homework-latest` обновляется и при упавших тестах движка;
  (2) «новейший» Xcode выбирается через `sort -V`, это может оказаться бета или версия без iOS 26 SDK, и тогда
  `#if canImport(FoundationModels)` молча выключит Apple Intelligence (`AppleIntelligenceProvider.swift:3`), а сборка останется зелёной;
  в Codemagic `xcode: latest` даёт ту же неопределённость; (3) отсутствие расширения не роняет сборку (`ls ... || echo`);
  (4) dSYM из архива не сохраняется, поэтому журналы сбоев с iPhone (Настройки → Конфиденциальность → Аналитика) нельзя символизировать.
- Последствия: на iPhone через обновление SideStore может прийти сборка с регрессией движка или без системной модели.
- Решение:
  ```yaml
  ipa:
    needs: engine-tests
    steps:
      - run: sudo xcode-select -s /Applications/Xcode_26.1.app      # закреплённая стабильная версия
      - run: xcodebuild -showsdks | grep -q 'iphoneos26' || { echo "::error::нужен iOS 26 SDK"; exit 1; }
      ...
      - run: test -d "$APP/PlugIns/AIHomeworkControls.appex"
      - uses: actions/upload-artifact@v4
        with: { name: AIHomework-dSYM, path: ai-homework-ios/build/AIHomework.xcarchive/dSYMs }
  ```
- Сложность: S
- Статус проверки: проверено чтением кода

### IOS-13. Логика быстрых действий продублирована и держится на задержке 450 мс; алерт и галерея показываются одновременно
- Приоритет: P3
- Файл: `AIHomework/App/AppModel.swift:76-79`, `:131-146`, `:148-176`
- Место в коде: `dismissPresentations(then:)` и `perform(_:)`; ветка «камеры нет» в `openCamera()`
- Причина: закрытие окон написано дважды (`perform` не использует `dismissPresentations`). Пауза 450 мс подобрана
  вручную под длительность анимации. В `openCamera` одновременно выставляются `alertMessage` и `isPhotoPickerPresented`,
  а SwiftUI покажет только одно из двух окон.
- Последствия: на медленном устройстве или при включённом «Уменьшении движения» новое окно иногда не появляется. Код легко рассинхронизировать.
- Решение: в `perform` вызывать `dismissPresentations { … }`; вместо таймера ждать `onDismiss` у `.sheet/.fullScreenCover`
  (или повторять попытку до двух раз). В ветке без камеры показывать алерт с кнопкой «Выбрать фото».
- Сложность: S
- Статус проверки: проверено чтением кода

### IOS-14. Вставка из буфера каждый раз вызывает системный запрос «Разрешить вставку»
- Приоритет: P3
- Файл: `AIHomework/App/AppModel.swift:97-110`
- Место в коде: `pasteFromClipboard()` → `pasteboard.image` / `pasteboard.string`
- Причина: программное чтение `UIPasteboard` начиная с iOS 16 показывает запрос, пока пользователь не разрешит вставку
  в настройках приложения.
- Последствия: лишний шаг в самом быстром сценарии «скопировал скриншот → вставил».
- Решение: на главном экране использовать `PasteButton(supportedContentTypes: [.image, .plainText])`, он работает без запроса.
  Программное чтение оставить только для быстрого действия «Вставить» с кнопки действия.
- Сложность: S
- Статус проверки: требует проверки на устройстве

### IOS-15. Фразы App Shortcuts не локализованы; устаревший `openAppWhenRun`
- Приоритет: P3
- Файл: `AIHomework/App/AppShortcuts.swift:9-21`; `Shared/QuickActionIntent.swift:37`; `AIHomework/App/ScreenshotIntent.swift:15`
- Место в коде: `phrases: [...]`
- Причина: русские и английские фразы лежат в одном массиве, а `AppShortcuts.xcstrings` нет. Система считает все фразы фразами
  языка разработки (en), поэтому Siri на русском, скорее всего, их не распознает, а русские строки в английской таблице не нужны.
  `openAppWhenRun` объявлен устаревшим в iOS 26 и при сборке с новым SDK даёт предупреждения.
- Последствия: голосовой запуск на русском не работает; команды в «Командах» и Spotlight при этом работают.
- Решение: оставить в коде английские фразы и добавить `AppShortcuts.xcstrings` с переводом `ru`. Заменить `openAppWhenRun` на
  `supportedModes`, когда минимальная версия это позволит, или оставить и принять предупреждение.
- Сложность: S
- Статус проверки: требует проверки на устройстве

### IOS-16. Особенности сайдлоада: потеря данных при смене Apple ID, рассинхронизация источника SideStore
- Приоритет: P3
- Файл: `AIHomework.xcodeproj/project.pbxproj:372`, `:436`; `scripts/make_sidestore_source.py:43`, `:52`, `:66-71`; `.github/workflows/ai-homework-ios.yml:3-5`
- Место в коде: `PRODUCT_BUNDLE_IDENTIFIER = com.example.aihomework`, `appPermissions`, `tintColor`
- Причина: SideStore добавляет к bundle ID идентификатор команды. При входе под другим Apple ID получится другое приложение
  с новым контейнером и новой группой Связки ключей, и история и ключ API останутся в старом. Права доступа к приватным данным продублированы в
  `source.json` вручную. Если в Info.plist появится новый `NS…UsageDescription` (например, для сохранения в Фото),
  а скрипт не обновят, SideStore может отказаться ставить обновление. В скрипте старый цвет `#7C5CFC` вместо акцента `#5e6ad2`,
  комментарий workflow всё ещё упоминает Sideloadly.
- Последствия: неожиданная потеря истории; неустановимое обновление после безобидной правки.
- Решение: в README предупредить: «не меняйте Apple ID в SideStore, иначе история будет потеряна». Добавить экспорт/импорт истории
  в файл (JSON+JPEG через `fileExporter`), без сервера и авторизации. В CI генерировать `privacy` из собранного `Info.plist`
  (`plutil -extract`), цвет и комментарий обновить.
- Сложность: S (тексты, CI); M (экспорт истории)
- Статус проверки: проверено чтением кода; проверка прав в SideStore требует проверки на устройстве

### IOS-17. Временные файлы и «зависшие» быстрые действия не очищаются
- Приоритет: P3
- Файл: `AIHomework/Services/PDFExporter.swift:55-56`; `Shared/QuickActionIntent.swift:66-76`; `AIHomework/App/ScreenshotIntent.swift:39-53`
- Место в коде: запись PDF в `temporaryDirectory`; `QuickActionInbox.post/consume`
- Причина: PDF-файлы накапливаются в `tmp`, пока их не удалит система. Запрос быстрого действия хранится в `UserDefaults` без
  отметки времени: если приложение выгрузили до обработки, камера откроется при следующем обычном запуске, хоть через неделю.
- Последствия: неожиданное открытие камеры при запуске, мелкий расход места.
- Решение: сохранять `Date()` вместе с действием и игнорировать запросы старше 60 с. Удалять старые PDF перед созданием нового
  (или писать в подпапку `tmp/Exports` и очищать её при старте).
- Сложность: S
- Статус проверки: проверено чтением кода

## Рекомендуемые тесты

Unit-тесты, которые можно добавить в существующий SwiftPM-пакет (запускаются на Linux в CI):
- `Deadline.run` с операцией, игнорирующей отмену: функция должна вернуть ошибку не позже `seconds + 0.2` с (IOS-11).
- `Deadline.compute`: после тайм-аута повторный вызов не ждёт предыдущий.

Нужен отдельный таргет `AIHomeworkTests` (XCTest/Swift Testing на симуляторе; `xcodebuild test -destination 'platform=iOS Simulator,name=iPhone 16'`
на том же бесплатном раннере `macos-15`):
- `ImageTools`: снимок `.right` 4032×3024 → `.up`, стороны поменялись местами; `crop` по `(0.5, 0.5, 0.5, 0.5)` даёт правый нижний квадрант
  после нормализации; склейка 4 страниц 2500×3300 после `normalized` имеет ширину ≥ 1000 px (IOS-1).
- `DocumentScanner.stack`: 1 страница возвращается без изменений, пустой массив не приводит к падению.
- `SettingsData`: чтение JSON старой версии без новых полей, с неизвестным значением enum, повреждённого JSON.
- `KeychainStore`: запись, чтение, перезапись, пустая строка удаляет запись.
- `QuickActionInbox`/`ScreenshotInbox`: `post` → `consume` возвращает значение один раз; второй `consume` даёт `nil`;
  флаг без файла даёт `nil`; после добавления TTL старое действие игнорируется (IOS-17).
- SwiftData на контейнере в памяти: вставка, `save`, чтение по `id`, `update(with:)`, `solution == nil` при повреждённом
  `solutionData`, `matches(_:)`; удаление всего обновляет `@Query`/fetch (IOS-9).
- Миграция: файл хранилища V1 (фикстура) открывается с текущей схемой и с планом миграции (IOS-7).
- `SolveViewModel` с подменённым координатором: `cancel()` во время решения не создаёт запись; при ошибке `save` показывается сообщение (IOS-8);
  `recognize` без текста и с настроенным API переходит к решению по картинке.
- `AppModel.perform`: при открытом `activeFlow` поток закрывается, затем выставляется `capture`; `pasteFromClipboard`
  с подменённым `UIPasteboard(name:create:)`.

UI-тесты (XCUITest на симуляторе):
- Запуск → «Ввести» → `2x+5=11` → результат → запись появилась в истории → «Удалить всё» в настройках → история пуста и на главном экране.
- Галерея: фото, добавленное через `xcrun simctl addmedia`, проходит выделение (жест перетаскивания) → распознавание.
- Аргумент запуска `-UITestImage <путь>` для проверки экрана выделения без камеры.
- Настройки сохраняются после перезапуска (язык, тема, адрес API; ключ остаётся в Связке ключей).

Ручная проверка на iPhone (без Mac, по чек-листу):
- Отказ в доступе к камере → понятное сообщение (IOS-4).
- Сканер: 1, 2 и 4 страницы → распознанный текст (IOS-1).
- Свернуть приложение на 20 и на 60 с во время решения по API (IOS-2).
- Элемент управления из Пункта управления и с кнопки действия: холодный и тёплый запуск (IOS-6); команда «Снимок экрана → Решить скриншот».
- Установка на устройство с iOS 17 (расширение рассчитано на iOS 18): приложение ставится и запускается.
- Обновление через источник SideStore поверх старой версии: история и ключ сохранились.
- Журналы `JetsamEvent` в «Аналитике» после сканирования 4 страниц и после фото 48 МП (IOS-1, IOS-5).
