# Аудит архитектуры (SwiftUI Architect)

Область: `AIHomework/App`, `AIHomework/Features/**`, `AIHomework/DesignSystem`, связи Features ↔ Services ↔ Engine, асинхронность, дублирование, расширяемость, тестируемость.
Метод: чтение кода (компилировать SwiftUI здесь нельзя). Номера строк — по текущему состоянию файлов.

## Инвентарь

| Компонент / слой | Статус | Основание (file:line) |
|---|---|---|
| Точка входа, `AppModel` в `@Environment`, SwiftData-контейнер | работает по коду | `App/AIHomeworkApp.swift:6-15`, `App/AppModel.swift:26-46` |
| Навигация `NavigationStack(path:)` + `AppRoute` | работает по коду | `App/AppModel.swift:11-15`, `App/RootView.swift:14-23` |
| Сценарий решения поверх навигации (ZStack-оверлей, не sheet/cover) | работает по коду, доступность и клавиатура требуют проверки на устройстве | `App/RootView.swift:13-32` |
| `matchedGeometryEffect` «орба» Home ↔ Solve | работает по коду; анимация требует проверки на устройстве | `Features/Home/HomeView.swift:73-80`, `Features/Solve/SolveFlowView.swift:65-66` |
| `SolveViewModel`: машина этапов selecting→recognizing→review→solving→result | работает по коду | `Features/Solve/SolveViewModel.swift:8-16, 109-113` |
| Выделение области (лассо + маркеры) | работает по коду; маркеры почти не успевают пригодиться (ARCH-2) | `Features/Solve/RegionSelectionView.swift:108-136, 154-197` |
| Камера / сканер / галерея / буфер обмена | работает по коду, требует проверки на устройстве | `Features/Capture/CapturePickers.swift`, `App/RootView.swift:37-52`, `App/AppModel.swift:71-110` |
| Быстрые действия (интенты, Пункт управления, скриншот) | частично: «почтовые ящики» в `UserDefaults.standard` + задержка 450 мс; требует проверки на устройстве | `Shared/QuickActionIntent.swift:61-77`, `App/ScreenshotIntent.swift:32-54`, `App/AppModel.swift:119-176` |
| История / детали / предметы / настройки | работает по коду | `Features/History/*`, `Features/Subjects/*`, `Features/Settings/SettingsView.swift` |
| `SolveCoordinator` (диспетчер → точный решатель → API → Apple Intelligence → отказ) | работает по коду, **не покрыт тестами и не подменяем** | `Services/SolveCoordinator.swift:31-211` |
| Точка расширения `LanguageModelProvider` | частично: `providers()` не используется в `solve()` | `Services/LanguageModelProvider.swift:25-40`, `Services/SolveCoordinator.swift:56-66, 159-161` |
| Engine как отдельный SwiftPM-таргет (только Foundation), тесты в CI на Linux | работает (57 тестов) | `Package.swift:12-20`, `.github/workflows/ai-homework-ios.yml:23-31` |
| Слой хранения (репозиторий/HistoryStore) | отсутствует: `ModelContext` напрямую во View и VM | 10 мест `try? context.save()` (см. ARCH-8) |
| Миграции SwiftData (`VersionedSchema`) | отсутствует; частично компенсировано JSON-блобом решения | `Persistence/SolvedProblem.swift:17-18` |
| DI-протоколы для координатора/хранилища/хаптики | отсутствует | `App/AppModel.swift:42-46`, `Features/Solve/SolveViewModel.swift:46, 57` |
| Тесты ViewModel / UI-тесты | отсутствуют | `EngineTests/` содержит только тесты движка |
| DesignSystem: `glassCard`/`GlassButton`/`AnimatedBackground` | работает, но часть параметров игнорируется | `DesignSystem/GlassSurface.swift:48-62`, `DesignSystem/AnimatedBackground.swift:6-13`, `DesignSystem/Buttons.swift:24-83` |
| `ShimmerBar`, `Theme.orb`, `Theme.brandGradient`, `Subject.palette/gradient` | мёртвый код (нет вызовов) | `DesignSystem/Components.swift:253`, `DesignSystem/Theme.swift:65-69, 89-95` |
| `GlassGroup` | заглушка (просто выводит содержимое, `spacing` игнорируется) | `DesignSystem/GlassSurface.swift:76-83` |
| `SolutionEngine.coreML` | заглушка совместимости: нужна для чтения старой истории из JSON, удалять нельзя | `Engine/Core/SolutionModels.swift:110-111`, `DesignSystem/Theme.swift:158` |

## Сильные стороны

1. **Граница Engine закреплена сборкой, а не договорённостью.** `Package.swift:12-15` собирает `AIHomework/Engine` отдельным таргетом, а CI запускает `swift test` на Linux (`.github/workflows/ai-homework-ios.yml:23-31`). Если кто-то добавит в Engine `import UIKit` или ссылку на Services, сборка пакета упадёт. Поэтому RemoteAPI (формирование запросов), TaskRouting, ModelPrompting и решатели остаются чистым Swift и проверяются без Mac.
2. **Типизированная навигация, устойчивая к удалению данных.** `AppRoute` (`App/AppModel.swift:11-15`) передаёт `UUID`, а не объект модели. `ProblemDetailView` ищет запись через `@Query` с предикатом и при удалении показывает «Задание удалено» (`Features/History/ProblemDetailView.swift:18-29`), а не обращается к удалённому `@Model`.
3. **Явная машина этапов с одной рабочей задачей.** `Stage` с `private(set)` (`SolveViewModel.swift:8-19`), а `workTask?.cancel()` стоит перед каждым новым запуском (`:126`, `:258`). После каждого `await` есть проверка `Task.isCancelled` (`:144, 148, 156, 275, 279`). Поэтому повторные нажатия «Решить» не дают двух параллельных решений.
4. **Ограничения времени на каждом шаге и правильная обработка отмены.** Есть `Deadline.run/compute` (`Engine/Core/Deadline.swift:11-39`) и общий лимит на все повторы сетевого запроса (`Services/RemoteAPIProvider.swift:90-113`). `CancellationError`/`URLError.cancelled` превращаются в `LanguageModelError.cancelled`, а координатор при отмене сразу выходит из цикла (`SolveCoordinator.swift:138-139, 192-193`). Так в коде устранена причина «бесконечно решает».
5. **Хранение устойчиво к изменению схемы.** `Solution` целиком хранится JSON-блобом, а поля для поиска и списков лежат рядом отдельными колонками (`Persistence/SolvedProblem.swift:12-20`). Крупное фото вынесено в `.externalStorage` (`:19`). Настройки читаются терпимо, поле за полем (`App/AppSettings.swift:34-45`), а ключ хранится отдельно в Связке ключей.
6. **Нейтральный к UI контракт провайдеров.** `LanguageModelProvider` импортирует только Foundation и принимает `Data?` вместо `UIImage` (`Services/LanguageModelProvider.swift:1, 29-40`), так что его можно перенести в Engine и подменять в тестах без переписывания.

## Находки

### ARCH-1. Главная логика маршрутизации нельзя подменить и не покрыта тестами
- Приоритет: P1
- Файл: `AIHomework/Services/SolveCoordinator.swift:31-42, 84-211`; `AIHomework/Features/Solve/SolveViewModel.swift:46, 57`; `AIHomework/App/AppModel.swift:42-46`
- Место в коде: `@MainActor final class SolveCoordinator { private let settings: AppSettings ... }`; `solve(... image: UIImage?, ...)` сама создаёт `RemoteAPIProvider(config:)` (`:96`) и `AppleIntelligenceProvider()` (`:161`); `SolveViewModel.init(... coordinator: SolveCoordinator)`.
- Причина: в одном конкретном классе смешаны политика (пять шагов: диспетчер → точный решатель → API → Apple Intelligence → отказ), создание провайдеров, чтение `@Observable AppSettings` и UIKit (`UIImage` → JPEG, `:100-106`). Протокола нет, а ViewModel принимает конкретный тип.
- Последствия: именно эта функция стоит за всеми известными жалобами владельца («бесконечно решает», «соединение потеряно»), но ни одна из её ветвей не проверяется автоматически. Её нельзя запустить в `swift test` на Linux (UIKit, MainActor), и её нельзя заменить заглушкой в тестах `SolveViewModel`. Любая правка ветвления проверяется только на iPhone владельца.
- Решение (эволюционно, без смены архитектуры): 1) Вынести в Engine `struct SolvePlan`/`SolvePolicy`, который принимает `SolveRequest` (текст, предмет, `subjectLocked`, `imageJPEG: Data?`, язык) и снимок настроек `SolveEnvironment` (`remoteConfig`, `useSystemModel`), а также `[any LanguageModelProvider]` и замыкание точного решателя. Перенести туда `LanguageModelProvider` и `ModelAvailability` (они Foundation-only). 2) `SolveCoordinator` оставить тонким адаптером: JPEG, `settings` → снимок, создание провайдеров. 3) Объявить `protocol SolveCoordinating { func detectSubject(_:) async -> SubjectGuess; func solve(...) async -> SolveOutcome; var canSolveImagesRemotely: Bool { get } }` и принимать его в `SolveViewModel.init`.
- Сложность: M
- Статус проверки: проверено чтением кода

### ARCH-2. Отмена сценария не окончательная: после закрытия работа может запуститься снова и записаться в историю
- Приоритет: P2
- Файл: `AIHomework/Features/Solve/RegionSelectionView.swift:128-133`; `AIHomework/Features/Solve/SolveViewModel.swift:88-98, 104-107, 118-127, 161-163`; `AIHomework/App/AppModel.swift:58-63`
- Место в коде: `Task { @MainActor in try? await Task.sleep(for: .milliseconds(350)); onSelectionFinished() }` → `model.recognize(useSelection: true)`; `func cancel() { workTask?.cancel(); detectionTask?.cancel() }`.
- Причина: `cancel()` отменяет только текущие задачи. Флага «сценарий закрыт» нет, и следующий вызов `recognize()`/`solve()` спокойно создаёт новый `workTask`. Отложенная задача из `RegionSelectionView` никем не отменяется и держит модель через замыкание. Задача нормализации из `onAppear` (`:92-97`) и кодирование JPEG в `save` (`:320-322`) тоже не отменяются.
- Последствия: если закрыть экран (×, быстрое действие, `AppModel.perform` → `closeFlow`) в течение 350 мс после обводки, OCR и решение всё равно запустятся. Будет запрос к платному API пользователя, а в историю попадёт запись, которую пользователь «отменил». Вторая, более частая проблема того же механизма: решение стартует через 350 мс после лассо, поэтому угловые маркеры (`RegionSelectionView.swift:154-197`) почти не успевают пригодиться, ведь распознавание уже началось. Окно короткое, но поведение не детерминировано.
- Решение: добавить в VM `private(set) var isClosed = false`. `cancel()` ставит `true`, а `recognize`/`solve`/`save` начинаются с `guard !isClosed`. Отложенный запуск перенести из View в VM (`scheduleAutoRecognize()` с собственной отменяемой задачей), отменять его при касании маркера и при `cancel()`.
- Сложность: S
- Статус проверки: проверено чтением кода (тайминги — требует проверки на устройстве)

### ARCH-3. Устаревший предмет при быстром нажатии «Решить» после правки условия
- Приоритет: P2
- Файл: `AIHomework/Features/Solve/SolveViewModel.swift:216-234, 255-256`; `AIHomework/Engine/Core/LocalSolverPipeline.swift:91`
- Место в коде: `let needsDetection = !isSubjectManual && subjectGuess == nil && !problem.isEmpty` и сразу `detectionTask?.cancel()`.
- Причина: при правке текста определение предмета откладывается на 450 мс. Если нажать «Решить» раньше, отложенная задача отменяется, а `subjectGuess` остаётся старым (не `nil`), поэтому повторного определения нет.
- Последствия: пример. OCR прочитал «1941–1945…» как историю, пользователь исправил текст на уравнение и сразу нажал «Решить». Предмет остаётся `.history`, а для гуманитарных предметов `order(for:)` возвращает `[]` (`LocalSolverPipeline.swift:91`), то есть точный решатель даже не запускается. Без API пользователь получит «Нужна нейросеть» на решаемое уравнение. С API диспетчер может исправить предмет, но точный решатель по исходному тексту получит неверный порядок.
- Решение: хранить `subjectGuessText` (текст, по которому сделан прогноз), и в `solve()` считать `needsDetection = !isSubjectManual && (subjectGuess == nil || subjectGuessText != problem)`.
- Сложность: S
- Статус проверки: проверено чтением кода

### ARCH-4. Заявленная точка расширения провайдеров не работает: `providers()` не участвует в решении
- Приоритет: P2
- Файл: `AIHomework/Services/LanguageModelProvider.swift:27-28`; `AIHomework/Services/SolveCoordinator.swift:56-66, 96, 159-185`
- Место в коде: документация протокола говорит «добавить провайдер в `SolveCoordinator.providers()`», но `solve()` собирает свой список заново (`:159-161`) и ветвится по `provider.engine == .remoteAPI` (`:164, 175, 179-185`).
- Причина: два источника правды о списке моделей. Особенности провайдера (видит ли изображения, свой ли у него лимит времени, умеет ли быть диспетчером) выводятся из типа движка, а не задаются свойствами.
- Последствия: новый провайдер (второй API, локальный сервер, MLX), добавленный по инструкции из комментария, появится только в бейдже `SubjectView` (`hasLanguageModel`), но не будет решать задания. Чтобы он заработал, придётся править `if isRemote` в трёх местах. `hasLanguageModel()` и `solve()` могут показывать разное.
- Решение: в протокол добавить `var supportsImages: Bool`, `var timeout: Double?` (nil = провайдер сам ограничивает время), по желанию `func route(...)` через отдельный протокол `TaskRouter`. `solve()` должен брать `providers()` (или фабрику из ARCH-1), отфильтрованные по `remoteUsable`.
- Сложность: S
- Статус проверки: проверено чтением кода

### ARCH-5. «Изменить и решить» из истории не даёт изменить: решение запускается сразу, создаётся дубликат записи, изображение теряется
- Приоритет: P2
- Файл: `AIHomework/Features/History/ProblemDetailView.swift:58-60, 97-101`; `AIHomework/Features/Solve/SolveViewModel.swift:65-69, 309-331`; `AIHomework/App/AppModel.swift:5-8`
- Место в коде: оба пункта вызывают `app.startSolve(.text(problem.problemText, subject: problem.subject))`; в `init` при непустом тексте `stage = .solving; shouldAutoSolve = true`.
- Причина: в `SolveInput` нет режима «открыть на проверке» и нет режима «продолжить существующую запись». У VM `record == nil`, поэтому `save` вставляет новую запись.
- Последствия: пункт меню «Изменить и решить» тратит запрос к API пользователя, не дав ничего изменить. Каждое «Решить заново» добавляет в историю ещё одну копию. Сохранённое фото не передаётся, поэтому задание, решённое по изображению (текст «Задание на изображении», `SolveViewModel.swift:283`), повторно не решить: `canSolve == true`, но API получит только эту подпись.
- Решение: расширить `SolveInput`: `.text(String, subject:, autoSolve: Bool = true)` и `.existing(SolvedProblem)` (подставляет текст, `imageData`, предмет и `record`). «Изменить и решить» → `autoSolve: false`, «Решить заново» → `.existing`, то есть обновляет ту же запись.
- Сложность: S–M
- Статус проверки: проверено чтением кода

### ARCH-6. ViewModel держит ссылку на `@Model`, которую можно удалить из настроек, открытых поверх результата
- Приоритет: P2
- Файл: `AIHomework/Features/Solve/SolveStages.swift:208-210` → `AIHomework/Features/Settings/SettingsView.swift:89-91`; `AIHomework/Features/Solve/SolveViewModel.swift:40, 310-314, 333-339`
- Место в коде: на экране нерешённого задания есть кнопка «Настроить нейросеть» (`SolutionContentView.swift:144-146`) → `app.isSettingsPresented = true`; в настройках «Удалить всю историю» выполняет `try? context.delete(model: SolvedProblem.self)`; потом «Заново» → `record.problemText = …; record.update(with:)`.
- Причина: VM владеет живым объектом SwiftData, а не идентификатором, и не следит за его удалением.
- Последствия: естественный сценарий «настроил API → нажал “Заново”» после очистки истории изменит удалённый объект. В зависимости от поведения SwiftData это либо падение (обращение к удалённой модели), либо новое решение молча не сохранится. Сценарий редкий, но приводит к падению или потере данных.
- Решение: хранить в VM `recordID: UUID?` и перед обновлением заново искать запись через `FetchDescriptor` (если её нет, вставлять новую). Это естественно ложится на `HistoryStore` из ARCH-8.
- Сложность: S
- Статус проверки: требует проверки на устройстве

### ARCH-7. Сценарий решения показан ZStack-оверлеем: экран под ним остаётся доступным, клавиатурная панель и переход «орба» не гарантированы
- Приоритет: P2
- Файл: `AIHomework/App/RootView.swift:13-32`; `AIHomework/Features/Solve/SolveStages.swift:46-51`; `AIHomework/Features/Home/HomeView.swift:73-80`
- Место в коде: `NavigationStack {...}.scaleEffect(...).blur(...).allowsHitTesting(app.activeFlow == nil)`, а поверх `if let flow = app.activeFlow { SolveFlowView(...) }`.
- Причина: оверлей выбран ради `matchedGeometryEffect`, но модальность реализована только отключением касаний.
- Последствия: (а) VoiceOver может перейти на элементы главного экрана под сценарием: `allowsHitTesting` не скрывает их от доступности, а ни `.accessibilityHidden`, ни `.accessibilityAddTraits(.isModal)` нигде не используются. (б) `ToolbarItemGroup(placement: .keyboard)` с кнопкой «Готово» стоит вне `NavigationStack`, а такие панели обычно показываются только внутри навигационного контейнера. (в) Сценарий запускается и с экранов, куда перешли по навигации (`SubjectView.swift:120`, `ProblemDetailView.swift:59`, `HistoryView.swift:116`). Тогда `HomeView` с исходным «орбом» не на экране, и общий переход летит из невидимой точки. Кроме того, исходник находится под `scaleEffect(0.94)`.
- Решение: оверлей оставить. Добавить на `NavigationStack` `.accessibilityHidden(app.activeFlow != nil)`, а на `SolveFlowView` `.accessibilityAddTraits(.isModal)`. Обернуть `SolveFlowView` в собственный `NavigationStack` со скрытой панелью (это даст клавиатурную панель и `.navigationDestination` на будущее). `matchedGeometryEffect` включать только при `app.path.isEmpty`, иначе использовать обычный переход.
- Сложность: M
- Статус проверки: требует проверки на устройстве

### ARCH-8. SwiftData разбросан по View и VM: ошибки сохранения молча проглатываются, очистка истории сделана двумя способами
- Приоритет: P2
- Файл: `AIHomework/Features/History/HistoryView.swift:176-194`; `AIHomework/Features/Settings/SettingsView.swift:89-91`; `AIHomework/Features/History/ProblemDetailView.swift:78-79, 115-116`; `AIHomework/Features/Solve/SolveViewModel.swift:51, 77-79, 247, 313, 329, 339`; `AIHomework/Features/Solve/SolveFlowView.swift:33-38`
- Место в коде: 10 вызовов `try? context.save()`. `clearAll()` удаляет в цикле (`HistoryView.swift:188-194`), а настройки — пакетно через `context.delete(model:)`. VM получает контекст двумя путями: `attach(_:)` из `onAppear` View и параметром `solve(context:)`.
- Причина: нет слоя хранения. Контекст появляется только внутри иерархии View (`.modelContainer` на сцене, `AIHomeworkApp.swift:15`), поэтому `AppModel` не может передать его в VM при создании.
- Последствия: если сохранение не удалось, пользователь об этом не узнает: избранное или запись «сохранены» только в памяти. VM нельзя проверить без живого `ModelContext`. Пакетное `delete(model:)` может не обновить `@Query` на главном экране и в истории до перезапуска (требует проверки на устройстве). Правила удаления и избранного продублированы в трёх экранах.
- Решение: создать `ModelContainer` в `AIHomeworkApp` и передать его через `.modelContainer(container)`. Добавить `@MainActor final class HistoryStore` (протокол `HistoryStoring`: `save(problem:solution:image:)`, `update(id:...)`, `toggleFavorite(id:)`, `delete(id:)`, `deleteAll()`), который бросает ошибки или возвращает `Result`. Передавать его в `AppModel` → `SolveViewModel.init`. `@Query` во View для чтения оставить: он нужен для реактивности.
- Сложность: M
- Статус проверки: проверено чтением кода (поведение `@Query` — требует проверки на устройстве)

### ARCH-9. Наследие «стеклянного» дизайна: параметры игнорируются, часть API мертва, имена вводят в заблуждение
- Приоритет: P3
- Файл: `AIHomework/DesignSystem/GlassSurface.swift:48-62, 76-83`; `AIHomework/DesignSystem/AnimatedBackground.swift:6-13`; `AIHomework/DesignSystem/Buttons.swift:24-29, 63-83`; `AIHomework/DesignSystem/Components.swift:151, 253-280`; `AIHomework/DesignSystem/Theme.swift:65-69, 89-95`
- Место в коде:
  - игнорируются: `glassCard(tint:)`, `glassCapsule(tint:)`, `glassCircle(tint:, interactive:)`, `AnimatedBackground(colors:, intensity:)` (вызов `HistoryView.swift:106` передаёт `intensity: 0.6` без эффекта), `PrimaryButton.colors`, `GlassButton.tint` (объявлен в `:66`, в `body` не используется), `FormulaBlock.tint` (вызовы передают `solution.subject.tint` в `SolutionContentView.swift:23, 47, 294`), `GlassGroup.spacing` (`HomeView.swift:121`);
  - никто не вызывает: `ShimmerBar`, `Theme.orb`, `Theme.brandGradient`, `Subject.palette`, `Subject.gradient`, `PrimaryButton.isLoading`;
  - `Subject.tint` всегда равен акценту, но по имени выглядит как цвет предмета.
- Причина: при смене дизайна сохранили сигнатуры, чтобы не трогать экраны.
- Последствия: читатель кода и будущий разработчик думают, что тонировка и интенсивность работают. `AnimatedBackground` больше не анимирован. Растёт стоимость понимания, и легко ошибиться при доработке.
- Решение (без массовой правки экранов): ввести честные имена `surfaceCard()`, `SecondaryButton`, `ScreenBackground`. Старые оставить как обёртки с `@available(*, deprecated, renamed: "surfaceCard")`, тогда компилятор сам покажет все места для постепенной замены. Неиспользуемые параметры пометить `deprecated`. `ShimmerBar`, `Theme.orb`, `brandGradient`, `Subject.palette/gradient` удалить, когда владелец разрешит удаления (сейчас ограничение «не удалять файлы» этому не мешает: это фрагменты файлов, но решать владельцу). `SolutionEngine.coreML` не трогать: он нужен для декодирования старой истории.
- Сложность: S
- Статус проверки: проверено чтением кода (поиск вызовов по всему `AIHomework/`)

### ARCH-10. Дублирование логики в Features и Services
- Приоритет: P3
- Файл: см. ниже
- Место в коде:
  - `AppModel.perform` (`App/AppModel.swift:148-176`) повторяет `dismissPresentations` (`:131-146`) почти построчно;
  - тосты `show(_:)` — `SolveFlowView.swift:125-133` и `ProblemDetailView.swift:162-170`; экспорт PDF — `SolveFlowView.swift:135-147` и `ProblemDetailView.swift:149-160`;
  - правило «текстовые предметы» `[.russian, .english, .literature]` — `SolveCoordinator.swift:229` и `ProblemDetailView.swift:70`;
  - описание ошибок `RemoteAPIError`/`LanguageModelError` — `SolveCoordinator.swift:234-242` и `SettingsView.swift:216-245` (дважды);
  - изображение сжимается в JPEG дважды за одно решение: `SolveCoordinator.swift:100-106` (1600 px, 0.82) и `SolveViewModel.swift:320-322` (1600 px, 0.8); нормализация ориентации — в `onAppear` (`:89-97`) и снова в `recognize` (`:130`).
- Причина: функции добавлялись по месту, без общих помощников.
- Последствия: правки расходятся (например, новый текстовый предмет добавят только в одно место). Двойное кодирование тратит лишнее время и память на большом снимке (требует проверки на устройстве).
- Решение: `perform` должен вызывать `dismissPresentations { … }`. Вынести `ToastModifier` в DesignSystem. Вынести `PDFExportAction` (или метод `HistoryStore`). Добавить `Subject.usesTextTools` в Engine. Добавить `func describe(_ error: Error, _ l: L10n) -> String` в Services. Сжатие в JPEG делать один раз в VM и передавать `Data` в координатор (это совпадает с ARCH-1).
- Сложность: S
- Статус проверки: проверено чтением кода

### ARCH-11. Бизнес-логика во View и состояние, которое не обновляется
- Приоритет: P3
- Файл: `AIHomework/Features/Settings/SettingsView.swift:205-247`; `AIHomework/App/RootView.swift:42-52`; `AIHomework/Features/Subjects/SubjectView.swift:36-38`
- Место в коде: сетевые проверки «Проверить и загрузить модели» и «Тестовый вопрос» с разбором ошибок живут в `SettingsView`. Загрузка `PhotosPickerItem` и сообщение об ошибке живут в `RootView` (флаг показа при этом в `AppModel`). `.task { hasModel = await app.coordinator.hasLanguageModel() }` работает без `id`.
- Причина: нет ViewModel для настроек. Владение данными разделено между `AppModel` и View.
- Последствия: логику подключения нельзя проверить тестом. Задачи не отменяются при закрытии листа. Бейдж «Нужна нейросеть» на странице предмета остаётся устаревшим после настройки API из этой же страницы (кнопка «Подключить нейросеть», `SubjectView.swift:100-102`), пока пользователь не уйдёт с неё и не вернётся.
- Решение: `@Observable SettingsModel` (или методы `AppModel`) для `checkConnection`/`sendTestQuestion`. `AppModel.handlePickedPhoto(_ item:)`. В `SubjectView` использовать `.task(id: app.settings.remoteConfig)` (`RemoteAPIConfig` уже `Equatable`) и учитывать `useSystemModel`.
- Сложность: S
- Статус проверки: проверено чтением кода

### ARCH-12. `withAnimation` и тактильный отклик внутри ViewModel; двойной отклик
- Приоритет: P3
- Файл: `AIHomework/Features/Solve/SolveViewModel.swift:109-113, 203-206, 229-232, 273, 336-338`; `AIHomework/DesignSystem/Buttons.swift:13-15`; `AIHomework/App/AppModel.swift:51`; `AIHomework/Features/Home/HomeView.swift:59-61`
- Место в коде: `setStage` оборачивает изменение в `withAnimation(Theme.spring)`, а `Haptics.*` вызывается из VM и AppModel. При этом `PressableButtonStyle` сам вызывает `Haptics.tap()` при нажатии.
- Причина: побочные эффекты интерфейса смешаны с состоянием.
- Последствия: VM привязана к SwiftUI и глобальному `Haptics.isEnabled`, а в тестах не проверить, «что сработал отклик». На многих кнопках два отклика подряд: `tap` из стиля и `press`/`tap` из обработчика (заметность требует проверки на устройстве).
- Решение: анимацию перенести во View (`.animation(Theme.spring, value: model.stage)` на `stageContent`). Хаптику передавать как зависимость `protocol FeedbackPlaying` (по умолчанию `Haptics`) или как событие `model.feedback` для View. В `PressableButtonStyle` для `PrimaryButton`/`GlassButton` выставлять `haptic: false`, если обработчик даёт свой отклик.
- Сложность: S
- Статус проверки: проверено чтением кода

### ARCH-13. Настройки и ключ записываются на каждое нажатие клавиши
- Приоритет: P3
- Файл: `AIHomework/Features/Settings/SettingsView.swift:77-82`; `AIHomework/App/AppSettings.swift:68-73, 95-97`
- Место в коде: `.onChange(of: settings.data) { settings.save() }` и `.onChange(of: settings.apiKey) { settings.saveAPIKey() }`.
- Причина: сохранение висит на каждое изменение привязки, а `KeychainStore.write` возвращает `Bool`, который игнорируется.
- Последствия: при вводе адреса и ключа идут десятки записей в `UserDefaults` и Связку ключей. Неудачная запись ключа не заметна: пользователь видит ключ в поле, но после перезапуска его нет (требует проверки на устройстве).
- Решение: сохранять ключ при `onSubmit`/потере фокуса/закрытии листа (`onDisappear`), либо с задержкой 0,5 с. Результат `write` показывать в статусе раздела API.
- Сложность: S
- Статус проверки: проверено чтением кода

### ARCH-14. Лишняя работа в `body`: полный `@Query` на главном экране, декодирование JSON и картинок при каждой перерисовке
- Приоритет: P3
- Файл: `AIHomework/Features/Home/HomeView.swift:9, 152, 210-211`; `AIHomework/Features/History/HistoryView.swift:8, 17-29, 231`; `AIHomework/Features/History/ProblemDetailView.swift:48, 87, 124`; `AIHomework/Persistence/SolvedProblem.swift:51-53`
- Место в коде: `HomeView` загружает все записи ради `prefix(10)` и двух счётчиков. `problem.solution` — вычисляемое свойство с `JSONDecoder` при каждом обращении, и в `ProblemDetailView` оно вызывается минимум дважды за проход. `UIImage(data:)` для миниатюр создаётся в `body`.
- Причина: удобство `@Query` без `fetchLimit` и вычисляемые свойства на модели.
- Последствия: главный экран остаётся в иерархии под оверлеем решения и пересчитывается при каждой вставке записи. На сотнях записей с фото возможны рывки прокрутки (требует проверки на устройстве).
- Решение: `@Query(FetchDescriptor` с `fetchLimit = 10`) для «Последних» и отдельные счётчики через `modelContext.fetchCount`. В `ProblemDetailView` декодировать решение один раз в `@State` через `.task(id:)`. Миниатюры кешировать (`NSCache` по `id`).
- Сложность: S–M
- Статус проверки: требует проверки на устройстве

### ARCH-15. Каталог примеров предметов лежит в Features, а тест движка копирует его строки вручную
- Приоритет: P3
- Файл: `AIHomework/Features/Subjects/SubjectCatalog.swift:1, 51-106`; `EngineTests/CatalogExamplesTests.swift:6-37`
- Место в коде: `extension Subject { func examples(_ l: L10n) -> [String] }` импортирует только Foundation, но находится вне `AIHomework/Engine`. Тест повторяет те же 32 строки литералами.
- Причина: файл положили к экрану, а не к модели предмета.
- Последствия: при изменении примера в приложении тест продолжит проверять старую строку, и на странице предмета может появиться пример, который не решается. Тест задуман как раз против этой ситуации.
- Решение: перенести `SubjectCatalog.swift` в `AIHomework/Engine/Core/` (зависимостей от UI нет). В тесте перебирать `Subject.allCases × AppLanguage.allCases` и брать `examples(L10n(lang))` для предметов с `hasLocalEngine`.
- Сложность: S
- Статус проверки: проверено чтением кода

### ARCH-16. Передача быстрых действий хрупкая: магическая задержка 450 мс, одновременные показы, «забытое» действие
- Приоритет: P3
- Файл: `AIHomework/App/AppModel.swift:71-81, 119-146, 167-172`; `AIHomework/App/ScreenshotIntent.swift:32-54`; `Shared/QuickActionIntent.swift:61-77`
- Место в коде: `try? await Task.sleep(for: .milliseconds(450)); run()`. В `openCamera()` при отсутствии камеры одновременно ставятся `alertMessage` и `isPhotoPickerPresented = true`. `handlePendingQuickAction` после скриншота делает `return`, и отложенное `QuickAction` остаётся в `UserDefaults` до следующей активации.
- Причина: последовательность показов держится на таймере, а не на завершении закрытия. Два почти одинаковых «ящика».
- Последствия: на медленном устройстве или при закрытии листа дольше 450 мс новое окно может не показаться. Из двух одновременных показов SwiftUI отобразит один. Устаревшее действие сработает неожиданно при следующем открытии приложения.
- Решение: очередь `pendingPresentation`, которую выполняют из `onDismiss` у `.sheet`/`.fullScreenCover` (и по `activeFlow == nil` после анимации); алерт показывать после закрытия выбора фото, а не вместе с ним. В `handlePendingQuickAction` очищать оба ящика. Общий тип `Inbox<Payload>` для двух ящиков.
- Сложность: S
- Статус проверки: требует проверки на устройстве

## Целевая архитектура

Эволюция без переписывания: слои остаются, меняются только швы между ними.

1. **Engine (SwiftPM, Linux):** добавить `SolvePolicy` (чистая версия шагов 1–5 из `SolveCoordinator.solve`), `LanguageModelProvider`/`TaskRouter`/`ModelAvailability`, `SubjectCatalog`, `Subject.usesTextTools`, `SettingsData`. Вход политики: `SolveRequest` (текст, предмет, `subjectLocked`, `imageJPEG: Data?`), `SolveEnvironment` (снимок настроек) и массив провайдеров. Выход: `SolveOutcome` плюс поток `SolvePhase`.
2. **Services (iOS):** `SolveCoordinator: SolveCoordinating` — тонкий адаптер (JPEG, снимок `AppSettings`, фабрика провайдеров `ProviderFactory`). `HistoryStore: HistoryStoring` поверх `ModelContainer`. `FeedbackPlaying` (Haptics). OCR за `protocol TextRecognizing`.
3. **App:** `AIHomeworkApp` создаёт `ModelContainer`, `AppSettings`, `HistoryStore`, `SolveCoordinator` и отдаёт их `AppModel(dependencies:)`. Для превью и тестов `AppModel.preview(...)` с заглушками.
4. **Features:** `SolveViewModel(input:, coordinator: any SolveCoordinating, history: any HistoryStoring, recognizer: any TextRecognizing, feedback:)`. Нет `ModelContext`, `withAnimation` и `Haptics` напрямую. Сценарий терминален после `cancel()`. Запись идентифицируется `UUID`.
5. **Навигация:** `AppRoute` оставить. Добавить `SolveInput.existing(UUID)` и `autoSolve`. Оверлей решения сделать модальным для доступности и обернуть в свой `NavigationStack`. Последовательность показов (лист → камера → решение) вести через `pendingPresentation` вместо таймеров.
6. **DesignSystem:** честные имена (`surfaceCard`, `SecondaryButton`, `ScreenBackground`), старые оставить как `deprecated`-обёртки до полной замены, игнорируемые параметры пометить.
7. **Новый предмет:** кейс в `Subject` + решатель в `LocalSolverPipeline.order/run` + примеры в `SubjectCatalog` (сразу под тестом). **Новый провайдер:** тип, реализующий протокол, и строка в `ProviderFactory`; координатор не меняется.

## Рекомендуемые тесты

**В Engine (`swift test`, Linux, после выноса `SolvePolicy`), с поддельными провайдерами:**
- диспетчер вернул `local` и точный решатель справился → API для решения не вызывается, в `notes` есть запись диспетчера;
- `local`, но точный решатель не справился → решение идёт по API с `route.problem`;
- диспетчер бросил ошибку → `remoteUsable == false`, следующий — Apple Intelligence, ошибка попала в `notes`;
- диспетчер выбрал `model` → точный решатель по исходному тексту не вызывается;
- `LanguageModelError.cancelled` на любом шаге → немедленный выход без дальнейших провайдеров;
- медленный провайдер → `Deadline` срабатывает, результат — честный отказ (с маленьким таймаутом через параметр);
- нет текста и есть изображение → провайдеры без зрения пропускаются;
- `subjectLocked` → предмет от диспетчера не применяется;
- каталог: все `Subject.examples` для предметов с `hasLocalEngine` решаются (вместо ручного списка);
- `SettingsData`: декодирование старого JSON без новых полей.

**ViewModel (XCTest в iOS-таргете на симуляторе в CI `macos-15`), с `FakeCoordinator`, `InMemoryHistoryStore`, `FakeRecognizer`:**
- `.text("x^2=4")` → этап `.solving` → `.result`, запись сохранена один раз;
- `.text("")` → `.review`, `canSolve == false`; после ввода — `true`;
- `cancel()` во время `.solving` → дальнейшие `recognize`/`solve` ничего не делают, запись не создаётся (ARCH-2);
- два вызова `solve()` подряд → координатор получил один «живой» запрос, итог один;
- правка текста и немедленный `solve()` → координатор получил свежий предмет (ARCH-3);
- «Заново» на результате → обновляется та же запись (по `UUID`), а не создаётся новая; при удалённой записи — вставка без падения (ARCH-6);
- OCR бросил `noText` и API настроен → решение по изображению; API не настроен → `.selecting` с `errorMessage`;
- `.existing(id)` и `autoSolve: false` → этап `.review` с текстом и изображением записи (ARCH-5).

**AppModel / навигация:**
- `perform(.camera)` при открытом сценарии → `activeFlow == nil`, `path == []`, затем `capture == .camera` (через внедряемые часы/планировщик вместо `Task.sleep`);
- `handlePendingQuickAction` очищает и скриншот, и отложенное действие;
- `pasteFromClipboard` с изображением / текстом / пустым буфером (буфер — через протокол);
- `ProblemDetailView` с несуществующим `UUID` показывает «Задание удалено» (снимок или ViewInspector-подобная проверка).

**UI-смоук (XCUITest на симуляторе в CI):** запуск → «Ввести» → `x^2 - 5x + 6 = 0` → «Решить» → виден ответ `x = 2; x = 3` → запись появилась в «Истории». Это единственная автоматическая проверка всей цепочки Features → Services → Engine без iPhone.
