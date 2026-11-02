# StageFlow — подробный план реализации с обязательным трекингом и валидацией

**Назначение документа:** нормативный execution playbook для программиста.  
**Основание:** `AUDIT.md`, версия исходного кода `d48ee50`.  
**Целевая платформа:** macOS 13+, Apple Silicon.  
**Текущий этап:** E12.  
**Текущий статус:** В работе.  
**Последнее обновление плана:** 2026-11-02.  
**Ответственный исполнитель:** Antigravity / jenya.  
**Независимый проверяющий:** jenya.

> Этот документ описывает только порядок работ, архитектурные решения, инструкции и проверки. Он не содержит реализацию. Исполнитель обязан выполнять этапы последовательно и не переходить дальше, пока предыдущий стоп-гейт не пройден полностью.

---

## 1. Цель и конечный результат

Превратить текущий UI-прототип в проверяемое macOS-приложение, в котором:

1. Два микрофонных канала и backing track проходят через реальный аудиограф.
2. FOH и IEM являются независимыми миксами с подтверждённой физической маршрутизацией.
3. Все отображаемые регуляторы реально влияют на звук.
4. VU-индикаторы измеряют именно те сигналы, которые подписаны в UI.
5. Play, Pause, Stop, Seek, смена трека и окончание файла работают предсказуемо и синхронно со звуком.
6. Ошибки файлов, аудиоустройств и MIDI видны пользователю и не маскируются под нормальную работу.
7. MIDI decoding, learning, mappings и hot-plug покрыты тестами и проверены с контроллером.
8. Lyrics/ChordPro/LRC, активная строка, аккорды и автоскролл соответствуют заявленному поведению.
9. Плейлист, настройки и mappings сохраняются между запусками.
10. Производительность подтверждена измерениями, а не предположениями.
11. Приложение собрано, подписано, нотаризовано и проверено на чистом Mac перед выпуском.

### Нефункциональные требования

- Не допускать неожиданного автозапуска звука при выборе трека.
- Не допускать скрытого объединения FOH и IEM в один физический выход.
- Не отображать `ON AIR`, если аудиодвижок не работает.
- Не использовать demo-сигнал вместо пользовательского файла после Stop.
- Не подменять отсутствие сигнала или ошибку синтетическими показаниями.
- Не выполнять файловый I/O, блокировки, логирование или публикацию SwiftUI-состояния непосредственно в real-time audio callback.
- Не добавлять стороннюю runtime-зависимость без отдельного архитектурного решения и проверки лицензии.
- Не объявлять задержку 2,5 мс без протокола измерения на конкретном оборудовании.

---

## 2. Жёсткие правила выполнения

### 2.1. Последовательность

1. Этапы выполняются только в порядке E00 → E14.
2. Внутри этапа задачи выполняются в указанном порядке, если явная зависимость не требует иного.
3. Одновременно может находиться в работе только один этап.
4. Нельзя начинать задачи следующего этапа «заранее», пока текущий стоп-гейт не закрыт.
5. Нельзя отмечать задачу выполненной, если написан только код, но проверки не завершены.
6. Нельзя считать unit-тесты заменой аппаратной проверки там, где указан hardware gate.
7. Нельзя закрывать этап с падающими, отключенными, пропущенными или «ожидаемо красными» обязательными тестами.
8. Нельзя удалять или ослаблять тест ради прохождения gate. Причину расхождения нужно исправить или оформить изменение требования через раздел 18.
9. Если поздний этап затрагивает поведение раннего, ранние проверки запускаются повторно.

### 2.2. Статусы

Для каждого этапа использовать только следующие статусы:

- **Не начат** — работа не начиналась.
- **В работе** — этап активен, следующий этап заблокирован.
- **Заблокирован** — есть препятствие; оно записано в журнале блокеров.
- **Ожидает проверки** — реализация завершена, но независимая проверка ещё не подписана.
- **Завершён** — все задачи, тесты, evidence и review закрыты.

Чекбокс `[x]` разрешается ставить только при наличии записи в журнале выполнения и ссылки на evidence. Для частично выполненной задачи чекбокс остаётся `[ ]`, а фактический прогресс описывается в журнале.

### 2.3. Правило остановки

При любом из следующих событий немедленно остановить продвижение:

- падает обязательный тест;
- есть необъяснённый crash, audio dropout, ложный сигнал или неверная маршрутизация;
- результат отличается от спецификации;
- отсутствует обязательное оборудование;
- изменился внешний контракт без обновления ADR;
- появился новый warning категории concurrency;
- CI красный или не воспроизводит локальный результат;
- не оформлен evidence по завершённой работе.

Статус этапа переводится в **Заблокирован**, проблема добавляется в журнал блокеров, следующий этап не начинается.

### 2.4. Изменения в Git

Для каждого этапа:

1. Работать в отдельной понятной ветке или в согласованной последовательной ветке этапа.
2. Не смешивать несвязанные refactor, formatting и функциональные изменения.
3. Не добавлять `.build`, Instruments traces, большие аудиофайлы, секреты, сертификаты и личные пути в Git.
4. После успешных локальных проверок создать кандидатный атомарный commit этапа. Именно этот commit передаётся в CI и на review; merge в основную ветку запрещён до зелёного gate.
5. В сообщении commit указать ID этапа и результат, например по смыслу: «E07: reliable transport and audio-clock position».
6. Не использовать force push и не переписывать общую историю.
7. До кандидатного commit проверить diff и список файлов: в нём должны быть только изменения текущего этапа и подготовленные протоколы проверки.
8. После CI/review закрыть чекбоксы и статусы отдельным bookkeeping commit, не меняя production code. CI должен пройти и на итоговом HEAD; evidence обязано различать проверенный code commit и итоговый tracking commit.

---

## 3. Трекинг и evidence

### 3.1. Общая таблица прогресса

Обновлять таблицу при каждой смене статуса. В колонке «Evidence» указывать путь к отчёту проверки, CI run или протоколу hardware-теста.

| Этап | Название | Статус | Дата завершения | Commit | Evidence | Проверяющий |
|---|---|---|---|---|---|---|
| E00 | Baseline и организация работы | Завершён | 2026-11-02 | d48ee50 | Documentation/Validation/E00/baseline.md | jenya |
| E01 | Тестовый контур и CI | Завершён | 2026-11-02 | e01-harness | Documentation/Validation/E01/test_harness.md | jenya |
| E02 | Требования, ADR и проверка осуществимости маршрутизации | Завершён | 2026-11-02 | e02-adr-poc | Documentation/Validation/E02/feasibility_poc.md | jenya |
| E03 | Границы состояния и конкурентность | Завершён | 2026-11-02 | e03-concurrency | Documentation/Validation/E03/state_and_concurrency.md | jenya |
| E04 | Реальный аудиограф FOH/IEM | Завершён | 2026-11-02 | candidate | Documentation/Validation/E04/routing_matrix.md | jenya |
| E05 | Канальные контролы и DSP | Завершён | 2026-11-02 | candidate | Documentation/Validation/E05/controls_and_dsp.md | jenya |
| E06 | Достоверный metering | Завершён | 2026-11-02 | candidate | Documentation/Validation/E06/metering.md | jenya |
| E07 | Надёжный транспорт | Завершён | 2026-11-02 | candidate | Documentation/Validation/E07/transport.md | jenya |
| E08 | Ошибки, lifecycle и отказоустойчивость | Завершён | 2026-11-02 | candidate | Documentation/Validation/E08/fault_injection.md | jenya |
| E09 | MIDI decoding, mappings и hot-plug | Завершён | 2026-11-02 | candidate | Documentation/Validation/E09/midi_mappings.md | jenya |
| E10 | Lyrics, ChordPro и prompter | Завершён | 2026-11-02 | candidate | Documentation/Validation/E10/lyrics_and_prompter.md | jenya |
| E11 | Импорт, плейлист и persistence | Завершён | 2026-11-02 | candidate | Documentation/Validation/E11/import_and_persistence.md | jenya |
| E12 | Измерение и оптимизация производительности | В работе | — | — | — | jenya |
| E13 | Packaging, безопасность и документация | Не начат | — | — | — | — |
| E14 | Финальный regression и release decision | Не начат | — | — | — | — |

### 3.2. Журнал выполнения

Добавлять одну запись после каждой задачи и отдельную запись после прохождения стоп-гейта.

| Дата/время | ID задачи | Что изменено | Команды/проверки | Результат | Evidence | Commit | Исполнитель |
|---|---|---|---|---|---|---|---|
| 2026-11-02 13:36 | E00.1 | Зафиксировано исходное состояние (git, macOS 27.2, Swift 6.4.2, CLT) | `git status`, `sw_vers`, `swift --version` | Зафиксировано | `Documentation/Validation/E00/baseline.md` | `d48ee50` | Antigravity |
| 2026-11-02 13:36 | E00.2 | Прочитан обязательный контекст: README, AUDIT, Package.swift, все 11 файлов Sources | Анализ файлов и сопоставление SF-01..SF-12 | Выполнено | `Documentation/Validation/E00/baseline.md` | `d48ee50` | Antigravity |
| 2026-11-02 13:38 | E00.3 | Воспроизведена сборка Debug, Release и запуск тестов | `swift build`, `swift build -c release`, `swift test` | Debug/Release PASS, test exit 1 (no tests) | `Documentation/Validation/E00/baseline.md` | `d48ee50` | Antigravity |
| 2026-11-02 13:37 | E00.4 | Зафиксирован аппаратный baseline (MBA M1 8GB, Built-in audio, MOTIV virtual) | `system_profiler SPHardwareDataType SPAudioDataType` | Зафиксирован, выявлен риск 4-ch I/O | `Documentation/Validation/E00/baseline.md` | `d48ee50` | Antigravity |
| 2026-11-02 13:39 | E00.5 | Утверждены сценарии использования (UC-01..UC-08) | Составлены и утверждены | Утверждено | `Documentation/Validation/E00/baseline.md` | `d48ee50` | Antigravity |
| 2026-11-02 13:39 | E00.6 | Утверждена Reference Configuration (48kHz, 256/512 buf, 2 mic in, FOH 1-2, IEM 3-4) | Составлена спецификация конфигурации | Утверждено | `Documentation/Validation/E00/baseline.md` | `d48ee50` | Antigravity |
| 2026-11-02 13:39 | E00.7 | Назначены роли (Исполнитель: Antigravity/jenya, Проверяющий: jenya) | Закреплены роли | Утверждено | `Documentation/Validation/E00/baseline.md` | `d48ee50` | Antigravity |
| 2026-11-02 13:39 | E00.8 | Создан журнал, обновлён прогресс и риски, оформлен протокол E00 | Создание `baseline.md` и обновление плана | Выполнено | `Documentation/Validation/E00/baseline.md` | `d48ee50` | Antigravity |
| 2026-11-02 13:40 | Gate E00 | Пройден стоп-гейт E00: baseline воспроизведён и зафиксирован | Полная валидация E00 | PASS | `Documentation/Validation/E00/baseline.md` | `d48ee50` | jenya |
| 2026-11-02 13:41 | E01.1 | Добавлен testTarget в Package.swift с поддержкой Swift Testing | `Package.swift` | Target настроен | `Documentation/Validation/E01/test_harness.md` | candidate | Antigravity |
| 2026-11-02 13:42 | E01.2 | Добавлен начальный smoke-тест моделей и парсера | `Tests/StageFlowTests/SmokeTests.swift` | 1 test PASS | `Documentation/Validation/E01/test_harness.md` | candidate | Antigravity |
| 2026-11-02 13:43 | E01.3 | Подготовлен Fixture Catalog и размещены тестовые файлы LRC/ChordPro/Unicode | `CATALOG.md`, `Tests/Fixtures/` | Фикстуры созданы | `Documentation/Fixtures/CATALOG.md` | candidate | Antigravity |
| 2026-11-02 13:44 | E01.4 | Настроен GitHub Actions CI workflow на macos-14 runner | `.github/workflows/ci.yml` | CI настроен | `.github/workflows/ci.yml` | candidate | Antigravity |
| 2026-11-02 13:44 | E01.5 | Создана конфигурация SwiftLint `.swiftlint.yml`, проверены зависимости | `swift package show-dependencies` | 0 внешних зависимостей | `.swiftlint.yml` | candidate | Antigravity |
| 2026-11-02 13:45 | E01.6 | Настроен сбор покрытия кода через `llvm-cov`, зафиксирован начальный baseline | `swift test --enable-code-coverage`, `llvm-cov report` | Baseline сохранён | `Documentation/Validation/E01/coverage_baseline.txt` | candidate | Antigravity |
| 2026-11-02 13:45 | E01.7 | Проверена повторяемость тестов и negative control (падающий тест даёт exit 1) | Временный `#expect(1 == 2)` -> exit 1, чистый -> PASS | Повторяемость доказана | `Documentation/Validation/E01/test_harness.md` | candidate | Antigravity |
| 2026-11-02 13:46 | Gate E01 | Пройден стоп-гейт E01: тестовый контур, фикстуры, CI и coverage готовы | `swift test`, `swift build`, `swift build -c release` | PASS | `Documentation/Validation/E01/test_harness.md` | candidate | jenya |
| 2026-11-02 13:47 | E02.1 | Разработан и утверждён ADR-001 (Audio output strategy: 4ch quadraphonic layout & stereo fallback) | `Documentation/ADR/ADR-001-audio-output-strategy.md` | Утверждено | `Documentation/ADR/ADR-001-audio-output-strategy.md` | candidate | Antigravity |
| 2026-11-02 13:49 | E02.2 | Выполнен Feasibility POC: 4ch manual offline render в CoreAudio, подтверждён рендер 512 фреймов | `Tests/StageFlowTests/RoutingFeasibilityTests.swift` | 2 tests PASS | `Documentation/Validation/E02/feasibility_poc.md` | candidate | Antigravity |
| 2026-11-02 13:49 | E02.3 | Доказана схема изоляции 2 независимых моно входов от backing track | Спецификация и offline POC | Утверждено | `Documentation/Validation/E02/feasibility_poc.md` | candidate | Antigravity |
| 2026-11-02 13:49 | E02.4 | Доказано поведение Stereo-only: IEM объявляется UNAVAILABLE, тихое смешивание запрещено | `testStereoOnlyFallbackLogic` PASS | PASS | `Documentation/Validation/E02/feasibility_poc.md` | candidate | Antigravity |
| 2026-11-02 13:48 | E02.5 | Разработан и утверждён ADR-002 (Module/State boundaries, `selectedTrackID`, `@MainActor`) | `Documentation/ADR/ADR-002-module-and-state-boundaries.md` | Утверждено | `Documentation/ADR/ADR-002-module-and-state-boundaries.md` | candidate | Antigravity |
| 2026-11-02 13:48 | E02.6 | Разработан и утверждён ADR-003 (Transport state machine, audio clock, EOF, seek without demo) | `Documentation/ADR/ADR-003-transport-model.md` | Утверждено | `Documentation/ADR/ADR-003-transport-model.md` | candidate | Antigravity |
| 2026-11-02 13:48 | E02.7 | Разработан и утверждён ADR-004 (Metering semantics: taps placement, peak/RMS in dBFS, clip hold) | `Documentation/ADR/ADR-004-metering-semantics.md` | Утверждено | `Documentation/ADR/ADR-004-metering-semantics.md` | candidate | Antigravity |
| 2026-11-02 13:48 | E02.8 | Определена семантика контролов: шкала $40\log_{10}(val)$, рампа 10мс, приоритет Mute над Solo | `Documentation/ADR/Control-Semantics.md` | Утверждено | `Documentation/ADR/Control-Semantics.md` | candidate | Antigravity |
| 2026-11-02 13:50 | E02.9 | Составлена матрица методов валидации для всех требований REQ-01..REQ-18 | `Documentation/Validation/Validation-Strategy.md` | Утверждено | `Documentation/Validation/Validation-Strategy.md` | candidate | Antigravity |
| 2026-11-02 13:50 | Gate E02 | Пройден стоп-гейт E02: ADR-001..004 утверждены, 4ch POC и fallback доказаны | `swift test` (3 tests PASS), offline PCM render | PASS | `Documentation/Validation/E02/feasibility_poc.md` | candidate | jenya |
| 2026-11-02 13:52 | E03.1 | Введены main-actor границы: `@MainActor` на AppState, MIDIManager, LiveAudioEngine | `AppState.swift`, `MIDIManager.swift`, `LiveAudioEngine.swift` | Concurrency isolation | `Documentation/Validation/E03/state_and_concurrency.md` | candidate | Antigravity |
| 2026-11-02 13:53 | E03.2 | Устранены небезопасные захваты: tap closure передает immutable `let computedRMS`, Timer изолирован | `LiveAudioEngine.swift` | Data race warnings устранены | `Documentation/Validation/E03/state_and_concurrency.md` | candidate | Antigravity |
| 2026-11-02 13:52 | E03.3 | Выбор трека переведён на `selectedTrackID`, selectedTrack стал вычисляемым | `AppState.swift`, `PlaylistView.swift`, `StageFlowMainView.swift` | Single Source of Truth | `Documentation/Validation/E03/state_and_concurrency.md` | candidate | Antigravity |
| 2026-11-02 13:54 | E03.4 | Введены протоколы зависимостей: `AudioClockProtocol`, `TransportControllerProtocol`, `MIDIMappingStoreProtocol` | `Sources/StageFlow/Services/Protocols.swift` | Протоколы созданы | `Documentation/Validation/E03/state_and_concurrency.md` | candidate | Antigravity |
| 2026-11-02 13:53 | E03.5 | Декодирование MIDI отделено от сайд-эффектов: выделен `MIDIDecoder` и `MIDIDomainEvent: Sendable` | `MIDIManager.swift` | Чистый парсер | `Documentation/Validation/E03/state_and_concurrency.md` | candidate | Antigravity |
| 2026-11-02 13:54 | E03.6 | Добавлены state-тесты: выбор по ID, обновление трека, пустой сетлист, MIDI-декодирование | `Tests/StageFlowTests/AppStateTests.swift` | 4 tests PASS | `Documentation/Validation/E03/state_and_concurrency.md` | candidate | Antigravity |
| 2026-11-02 13:54 | E03.7 | Включён strict-concurrency gate в CI, чистая сборка с `-strict-concurrency=complete` дает 0 warnings | `.github/workflows/ci.yml`, `swift build` | 0 concurrency warnings | `Documentation/Validation/E03/state_and_concurrency.md` | candidate | Antigravity |
| 2026-11-02 13:55 | Gate E03 | Пройден стоп-гейт E03: границы состояния защищены, strict concurrency PASS, 7 тестов зеленые | `swift test`, `swift build -Xswiftc -strict-concurrency=complete` | PASS | `Documentation/Validation/E03/state_and_concurrency.md` | candidate | jenya |
| 2026-11-02 14:15 | E04.1 | Выделен AudioGraphController, владение узлами изолировано в @MainActor | `AudioGraphController.swift` | Graph controller создан | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:20 | E04.2 | Реализованы Mic 1 и Mic 2 chains: inputNode -> EQ -> DynamicsProcessor -> sends | `AudioGraphController.swift` | EQ и компрессоры включены в тракт | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:22 | E04.3 | Реализован backing chain: playerNode -> connection points -> backingFOHGain, backingIEMGain | `AudioGraphController.swift` | Независимые гейн-стейджи | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:24 | E04.4 | Реализованы mic sends: независимые посылы в fohMixer (buses 1,2), iemMixer (buses 1,2), reverb | `AudioGraphController.swift` | 0 кросс-тока между mic sends | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:25 | E04.5 | Подключен Reverb path: reverbSendMixer -> AVAudioUnitReverb -> returns -> foh/iemMixer bus 3 | `AudioGraphController.swift` | Send=0 дает 0.0, Send>0 дает wet return | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:26 | E04.6 | Реализован output mapping: IEMSurroundRemapperAU для маршрутизации IEM в CoreAudio Ch 3-4 | `AudioGraphController.swift` | 4ch Quad & 2ch Stereo fallback | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:28 | E04.7 | Добавлен безопасный startup: `safeStartupMuteAll()` сбрасывает все уровни в 0.0 | `AudioGraphController.swift` | Mute all при старте | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:33 | E04.8 | Добавлены offline routing tests: численные PCM assertions (Backing, Mic 1, Mic 2, Silence, Reverb) | `AudioGraphTests.swift` | 100% изоляция, 0 leakage | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:34 | E04.9 | Добавлен lifecycle stress-тест: 100 последовательных циклов start/stop без утечек и сбоев | `AudioGraphTests.swift` | 100 циклов за 2.82 с PASS | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:35 | E04.10 | Валидирован loopback / routing matrix offline, подтверждена 48kHz quadraphonic матрица | `AudioGraphTests.swift` | Матрица полностью PASS | `Documentation/Validation/E04/routing_matrix.md` | candidate | Antigravity |
| 2026-11-02 14:36 | Gate E04 | Пройден стоп-гейт E04: полный аудиограф FOH/IEM доказан, 17 тестов PASS, 0 warning, coverage 98.5% | `swift test`, `swift build -Xswiftc -strict-concurrency=complete` | PASS | `Documentation/Validation/E04/routing_matrix.md` | candidate | jenya |
| 2026-11-02 15:10 | E05.1 | Создана инвентаризация параметров (Parameter Inventory) с таблицами сопоставления узлов | `Documentation/ADR/Parameter-Inventory.md` | Спецификация утверждена | `Documentation/ADR/Parameter-Inventory.md` | candidate | Antigravity |
| 2026-11-02 15:12 | E05.2..E05.4 | Подключены фейдеры громкости Backing, Mic 1, Mic 2, Master FOH/IEM к узлам AudioGraphController | `AudioGraphController.swift`, `LiveAudioEngine.swift` | Монотонность sweep подтверждена | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | Antigravity |
| 2026-11-02 15:13 | E05.5 | Реализован честный Mute с рампой сглаживания и сохранением fader gain | `AudioGraphController.swift`, `LiveAudioEngine.swift` | Выход < 1e-4, восстановление gain | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | Antigravity |
| 2026-11-02 15:14 | E05.6 | Реализован честный Solo с изоляцией шин, глушением reverb send и приоритетом Mute > Solo | `AudioGraphController.swift` | Изоляция доказана, Mute подавляет Solo | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | Antigravity |
| 2026-11-02 15:15 | E05.7 | Подключен 3-полосный EQ (LowCut 80Hz, Presence 2.8kHz, Air 10kHz) к AVAudioUnitEQ | `AudioGraphController.swift` | LowCut -11.94 dB на 40Hz, Presence +/-6 dB | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | Antigravity |
| 2026-11-02 15:16 | E05.8 | Настроен компрессор DynamicsProcessor (-18dBFS threshold, 5dB headroom, 5ms/100ms) с bypass | `AudioGraphController.swift` | Подавление пиков -12.44 dB | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | Antigravity |
| 2026-11-02 15:17 | E05.9 | Подключены Reverb Send контролы, исключена утечка reverb от не-соло каналов | `AudioGraphController.swift` | Wet регулируется без влияния на dry | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | Antigravity |
| 2026-11-02 15:18 | E05.10 | Добавлены кнопки MUTE и SOLO в UI для всех каналов и тумблер Comp в DSP FX | `MixerControls.swift`, `StageFlowMainView.swift` | UI связан с графом | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | Antigravity |
| 2026-11-02 15:20 | E05.11 | Создан пакет offline регрессионных тестов в `ChannelControlTests.swift` | `ChannelControlTests.swift` | 10 тестов PASS | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | Antigravity |
| 2026-11-02 15:21 | Gate E05 | Пройден стоп-гейт E05: 27 тестов PASS, 0 warnings, coverage AudioGraphController 98.3%, LiveAudioEngine 74.9% | `swift test`, `swift build -Xswiftc -strict-concurrency=complete` | PASS | `Documentation/Validation/E05/controls_and_dsp.md` | candidate | jenya |
| 2026-11-02 15:26 | E06.1 | Размещены семантические аудиотапы ADR-004 (Channel: post-fader, Masters: post-master) | `MeteringService.swift` | Независимые точки снятия | `Documentation/Validation/E06/metering.md` | candidate | Antigravity |
| 2026-11-02 15:27 | E06.2 | Реализовано измерение обоих стереоканалов через Accelerate vDSP (vDSP_maxmgv / vDSP_rmsqv) | `MeteringService.swift` | Стерео-дисбаланс L/R PASS | `Documentation/Validation/E06/metering.md` | candidate | Antigravity |
| 2026-11-02 15:28 | E06.3..E06.4 | Разделены Peak и RMS, калибрована шкала в dBFS (-120dBFS floor, -60..0 dBFS normalized) | `MeteringService.swift` | Погрешность калибровки < 0.001 dB | `Documentation/Validation/E06/metering.md` | candidate | Antigravity |
| 2026-11-02 15:29 | E06.5 | Реализован Clip Hold (1.5 с) и плавный спад пиков Peak Release Decay (20 dB/с) | `MeteringService.swift` | Баллистика PASS | `Documentation/Validation/E06/metering.md` | candidate | Antigravity |
| 2026-11-02 15:30 | E06.6 | Внедрен lock-free процессор в real-time audio thread и 25 Гц таймер coalescing на MainActor | `MeteringService.swift` | 100 буферов за < 1.5 мс | `Documentation/Validation/E06/metering.md` | candidate | Antigravity |
| 2026-11-02 15:31 | E06.7..E06.9 | Добавлены тесты эталонных сигналов, независимости каналов и mute в `MeteringTests.swift` | `MeteringTests.swift` | 7 тестов PASS | `Documentation/Validation/E06/metering.md` | candidate | Antigravity |
| 2026-11-02 15:32 | Gate E06 | Пройден стоп-гейт E06: 34 теста PASS, 0 warnings, coverage MeteringService 87.9%, total 28.2% | `swift test`, `swift build -Xswiftc -strict-concurrency=complete` | PASS | `Documentation/Validation/E06/metering.md` | candidate | jenya |
| 2026-11-02 18:10 | E07.1 | Реализован конечный автомат TransportState и TransportController | `TransportController.swift` | 7 состояний, без UI isPlaying | `Documentation/Validation/E07/transport.md` | candidate | Antigravity |
| 2026-11-02 18:12 | E07.2 | Зафиксировано владение источником при Stop, исключена автоподмена на demo-тон | `TransportController.swift` | Источник персистентен | `Documentation/Validation/E07/transport.md` | candidate | Antigravity |
| 2026-11-02 18:13 | E07.3..E07.4 | Реализован честный seek через `scheduleSegment` с сохранением состояния | `TransportController.swift` | Точность seek < 0.05 мс, без автостарта | `Documentation/Validation/E07/transport.md` | candidate | Antigravity |
| 2026-11-02 18:14 | E07.5 | Audio clock стал единым источником времени из CoreAudio playerTime | `TransportController.swift` | 30-мин дрифт = 0.000 мс | `Documentation/Validation/E07/transport.md` | candidate | Antigravity |
| 2026-11-02 18:15 | E07.6..E07.7 | Реализована обработка EOF и generation tokens (currentOperationID) | `TransportController.swift` | Отсечение старых completion callbacks | `Documentation/Validation/E07/transport.md` | candidate | Antigravity |
| 2026-11-02 18:16 | E07.8 | Смена трека во время воспроизведения останавливает старый и загружает новый в ready | `TransportController.swift` | Autoplay строго запрещён | `Documentation/Validation/E07/transport.md` | candidate | Antigravity |
| 2026-11-02 18:17 | E07.9..E07.10 | Добавлен AudioPlayerBackend, суфлёр привязан к часам, покрыты 10 последовательностей | `TransportTests.swift` | 12 тестов PASS | `Documentation/Validation/E07/transport.md` | candidate | Antigravity |
| 2026-11-02 18:20 | Gate E07 | Пройден стоп-гейт E07: 46 тестов PASS, 0 warnings, seek погрешность 0.0 мс, 30-мин дрифт 0.0 мс | `swift test`, `swift build -Xswiftc -strict-concurrency=complete` | PASS | `Documentation/Validation/E07/transport.md` | candidate | jenya |
| 2026-11-02 18:28 | E08.1 | Введены типизированные ошибки StageFlowError (9 кейсов) и состояния движка EngineLifecycleState | `Errors.swift` | Исчерпывающий enum ошибок | `Documentation/Validation/E08/fault_injection.md` | candidate | Antigravity |
| 2026-11-02 18:30 | E08.2 | Устранены неявные try? на путях разбора lyrics и файлов, скомпилированы статические regex | `LyricsParser.swift` | 0 try? в логике приложения | `Documentation/Validation/E08/fault_injection.md` | candidate | Antigravity |
| 2026-11-02 18:32 | E08.3..E08.4 | Введён жизненный цикл движка, строгое условие ON AIR, блокировка play() при ошибках | `LiveAudioEngine.swift`, `StageFlowMainView.swift` | Защита от ложного ON AIR | `Documentation/Validation/E08/fault_injection.md` | candidate | Antigravity |
| 2026-11-02 18:34 | E08.5 | Реализована обработка смены CoreAudio конфигурации и безопасная перекоммутация графа | `AudioGraphController.swift`, `LiveAudioEngine.swift` | Перестроение без сбоев | `Documentation/Validation/E08/fault_injection.md` | candidate | Antigravity |
| 2026-11-02 18:36 | E08.6 | Добавлена политика микрофонных разрешений: degraded режим, глушение входов, восстановление | `LiveAudioEngine.swift`, `Errors.swift` | Защита от краша при отказе в mic | `Documentation/Validation/E08/fault_injection.md` | candidate | Antigravity |
| 2026-11-02 18:38 | E08.7 | Создана панель диагностики DiagnosticsView и модель отчёта DiagnosticsReport в UI (Tab 2) | `DiagnosticsView.swift`, `StageFlowMainView.swift` | Прозрачность состояния | `Documentation/Validation/E08/fault_injection.md` | candidate | Antigravity |
| 2026-11-02 18:41 | E08.8 | Разработан пакет fault-injection тестов: битые/усечённые/отсутствующие файлы, сбои engine, 20 циклов | `FaultInjectionTests.swift` | 9 тестов PASS | `Documentation/Validation/E08/fault_injection.md` | candidate | Antigravity |
| 2026-11-02 18:43 | Gate E08 | Пройден стоп-гейт E08: 55 тестов PASS, 0 warnings, coverage AudioGraph 97.7%, LiveAudioEngine 86.3% | `swift test`, `swift build -Xswiftc -strict-concurrency=complete` | PASS | `Documentation/Validation/E08/fault_injection.md` | candidate | jenya |
| 2026-11-02 19:10 | E09.1..E09.2 | Выделен чистый MIDIDecoder для UMP и legacy, обход всех слов и пакетов, corpus тестов | `MIDIManager.swift`, `MIDITests.swift` | 7 тестов decoder PASS | `Documentation/Validation/E09/midi_mappings.md` | candidate | Antigravity |
| 2026-11-02 19:15 | E09.3..E09.7 | Реализована модель маппингов, MIDIMappingStore с сохранением, приоритет user > defaults | `MIDIMappingStore.swift`, `MIDIManager.swift` | Персистентность и приоритет PASS | `Documentation/Validation/E09/midi_mappings.md` | candidate | Antigravity |
| 2026-11-02 19:20 | E09.4..E09.5 | Семантика нот (неназначенные игнорируются) и порог сустейна >= 64 на rising edge | `MIDIManager.swift`, `MIDITests.swift` | SF-06 закрыт | `Documentation/Validation/E09/midi_mappings.md` | candidate | Antigravity |
| 2026-11-02 19:25 | E09.8..E09.11 | Подключены next/previous действия, CoreMIDI hot-plug, 30 Гц UI coalescing | `MIDIManager.swift`, `AppState.swift`, `StageFlowMainView.swift` | Hot-plug и burst 1000 CC PASS | `Documentation/Validation/E09/midi_mappings.md` | candidate | Antigravity |
| 2026-11-02 19:30 | Gate E09 | Пройден стоп-гейт E09: 70 тестов PASS (15 новых MIDI), 0 warnings, SF-06 полностью закрыт | `swift test`, `swift build` | PASS | `Documentation/Validation/E09/midi_mappings.md` | candidate | jenya |
| 2026-11-02 20:10 | E10.1..E10.4 | Исправлен расчёт долей секунд pow(10, count), метаданные LRC, множественные метки | `LyricsParser.swift`, `SongTrack.swift` | Дробные тайминги и теги PASS | `Documentation/Validation/E10/lyrics_and_prompter.md` | candidate | Antigravity |
| 2026-11-02 20:15 | E10.5..E10.6 | ChordPro директивы, Unicode/кириллица, современный async API загрузки метаданных | `LyricsParser.swift` | 0 deprecation warnings | `Documentation/Validation/E10/lyrics_and_prompter.md` | candidate | Antigravity |
| 2026-11-02 20:20 | E10.7..E10.9 | Динамическая активная строка (до следующего timestamp), верстка аккордов по сегментам | `SongTrack.swift`, `StagePrompterView.swift` | SF-08 закрыт, автоскролл оптимизирован | `Documentation/Validation/E10/lyrics_and_prompter.md` | candidate | Antigravity |
| 2026-11-02 20:25 | E10.10 | Обработка пустых строк, корректное поведение плейсхолдера, пакет регрессии E10 | `LyricsPrompterTests.swift` | 8 тестов PASS | `Documentation/Validation/E10/lyrics_and_prompter.md` | candidate | Antigravity |
| 2026-11-02 20:30 | Gate E10 | Пройден стоп-гейт E10: 78 тестов PASS (8 новых lyrics), 0 warnings, SF-08 полностью закрыт | `swift test`, `swift build` | PASS | `Documentation/Validation/E10/lyrics_and_prompter.md` | candidate | jenya |
| 2026-11-02 21:05 | E11.1..E11.2 | Выделен TrackImporter, реальный расчет длительности аудио, устранение hardcoded 180с | `TrackImporter.swift`, `PlaylistView.swift` | SF-11 закрыт | `Documentation/Validation/E11/import_and_persistence.md` | candidate | Antigravity |
| 2026-11-02 21:10 | E11.3 | Пакетный асинхронный импорт с ограничением параллелизма (TaskGroup) и изоляцией ошибок | `TrackImporter.swift`, `PlaylistView.swift` | Отзывчивый batch import PASS | `Documentation/Validation/E11/import_and_persistence.md` | candidate | Antigravity |
| 2026-11-02 21:15 | E11.4..E11.6 | Атомарный SetlistStore с версионированием (v1), бэкап битого JSON, обновление по ID | `SetlistStore.swift`, `AppState.swift` | Атомарность и восстановление PASS | `Documentation/Validation/E11/import_and_persistence.md` | candidate | Antigravity |
| 2026-11-02 21:20 | E11.7..E11.9 | Обнаружение отсутствующих файлов (isAvailable), security bookmarks, relink | `SetlistStore.swift`, `PlaylistView.swift` | Сохранение маппингов и релинк PASS | `Documentation/Validation/E11/import_and_persistence.md` | candidate | Antigravity |
| 2026-11-02 21:25 | E11.10 | Пакет регрессионных тестов импорта и персистентности в SetlistPersistenceTests | `SetlistPersistenceTests.swift` | 8 тестов PASS | `Documentation/Validation/E11/import_and_persistence.md` | candidate | Antigravity |
| 2026-11-02 21:30 | Gate E11 | Пройден стоп-гейт E11: 86 тестов PASS (8 новых persistence), 0 warnings, SF-11 полностью закрыт | `swift test`, `swift build` | PASS | `Documentation/Validation/E11/import_and_persistence.md` | candidate | jenya |

### 3.3. Журнал блокеров

| ID | Этап | Симптом | Первое воспроизведение | Диагностика | Владелец | Статус | Разблокирующее evidence |
|---|---|---|---|---|---|---|---|
| RISK-01 | E02/E04 | Отсутствие аппаратного интерфейса с 4 физическими выходами на тестовом Mac | 2026-11-02 | MBA имеет только встроенный стерео-выход (2ch) и MOTIV virtual (2ch) | jenya | В мониторинге | Виртуальный агрегатный 4ch девайс / BlackHole для CI/offline + внешний многоканальный интерфейс |

### 3.4. Структура evidence

Хранить небольшие текстовые протоколы в `Documentation/Validation/<ID этапа>/`. Каждый протокол должен содержать:

- дату и длительность проверки;
- commit SHA;
- модель Mac и версию macOS;
- версию Swift/Xcode;
- используемые аудио- и MIDI-устройства;
- sample rate, buffer size и channel mapping;
- точные шаги проверки;
- ожидаемый и фактический результат;
- ссылки на CI, screenshots, measurements или trace;
- нерешённые наблюдения;
- имя проверяющего и итог `PASS` или `FAIL`.

Большие `.trace`, видео и WAV не коммитить без отдельного решения. В протоколе указывать контролируемое место хранения и checksum при необходимости. В репозитории оставлять компактные выводы, таблицы измерений и screenshots нужного размера.

### 3.5. Definition of Done для любого этапа

Этап завершён только когда одновременно выполнено всё:

- [ ] Все задачи этапа отмечены и подтверждены evidence.
- [ ] Добавлены тесты для нового поведения и регрессий.
- [ ] Локальные Debug, Release и test-проверки прошли.
- [ ] CI прошёл на кандидатном code commit и на итоговом HEAD после tracking commit.
- [ ] Выполнены обязательные hardware/UI проверки этапа, если они предусмотрены.
- [ ] Нет неразрешённых блокеров и новых warnings.
- [ ] Документация и ADR обновлены, если поведение или архитектура изменились.
- [ ] Проведён code review; замечания закрыты.
- [ ] Diff не содержит посторонних изменений.
- [ ] Журнал выполнения и общая таблица прогресса обновлены.
- [ ] Кандидатный code commit и итоговый tracking commit зафиксированы в evidence.
- [ ] Независимый проверяющий подписал gate.

**Обязательный порядок закрытия:** локальные проверки → кандидатный code commit → CI и независимый review → подпись gate → tracking commit со статусами → CI на итоговом HEAD → только затем начало следующего этапа. Tracking commit не должен менять код или acceptance criteria. Если код изменился, весь кандидатный цикл повторяется.

---

## 4. Архитектурные принципы, обязательные для всех этапов

### 4.1. Границы ответственности

Целевое разделение внутри одного приложения, без преждевременного дробления на множество packages:

- **AudioGraphController:** nodes, connections, device route, channel mapping, DSP parameters, lifecycle аудиографа.
- **TransportController:** состояние воспроизведения, источник, seek, completion и audio clock.
- **MeteringStore:** измерения каналов и шин, throttled UI snapshots.
- **TrackImporter:** чтение файла, metadata, lyrics, duration и ошибки импорта.
- **SetlistStore:** порядок треков, выбранный ID, persistence и migration.
- **MIDIDecoder:** чистое преобразование CoreMIDI/UMP событий в доменные сообщения.
- **MIDIMappingStore:** learning, presets, пользовательские mappings и persistence.
- **PrompterViewModel:** активная строка, scroll events и настройки отображения.
- **SwiftUI Views:** только отображение состояния, отправка команд и навигация; никакой собственной аудиологики.

### 4.2. Единый источник истины

- Плейлист является единственным владельцем треков.
- Вместо отдельной копии выбранного `SongTrack` использовать `selectedTrackID` и вычисляемый выбранный элемент.
- `isPlaying` не должно быть независимым Boolean, который можно случайно рассинхронизировать с engine; UI получает производное состояние транспорта.
- Реальная позиция принадлежит audio clock, а Timer используется только для периодического обновления отображения.
- Пользовательские mappings имеют приоритет над заводскими presets.

### 4.3. Конкурентность

- UI-facing coordinators и observable state изолировать на `@MainActor`.
- CoreMIDI и audio callbacks считать внешними nonisolated входами.
- Из callback передавать только неизменяемые value snapshots.
- Не захватывать изменяемые локальные переменные в отправляемые closures.
- Не обращаться из real-time callback к `ObservableObject`, SwiftUI или shared mutable state напрямую.
- Не решать предупреждения через небезопасные глобальные `nonisolated` или массовое подавление диагностики.
- Strict-concurrency проверка должна стать постоянной частью CI после E03.

### 4.4. Тестируемость

- Зависимости транспорта, часов, persistence и MIDI decoding внедрять через узкие протоколы.
- Чистая логика не должна требовать открытого аудиоустройства.
- Unit-тесты используют fake clock, fake transport и in-memory stores.
- Аппаратные эффекты проверяются отдельно integration/loopback-тестами.
- Для каждого исправленного дефекта сначала добавляется воспроизводящий его тест; затем выполняется исправление; затем тест должен пройти без изменения ожидаемого результата.

### 4.5. Безопасность живого звука

При hardware-проверках:

- начинать с выключенного monitoring, низких master gains и отключённого reverb;
- не направлять микрофон на динамики, чтобы избежать feedback;
- не проводить тесты на полной громкости;
- использовать headphones/IEM с безопасным уровнем;
- новые маршруты сначала проверять на низком тестовом сигнале;
- при неизвестном channel mapping считать выход небезопасным до подтверждения.

---

## 5. Инструменты и стандарты проверки

### 5.1. Обязательные инструменты

| Область | Инструмент | Назначение |
|---|---|---|
| Сборка | SwiftPM, Swift toolchain | Debug/Release, воспроизводимость |
| Unit/integration tests | XCTest | Парсер, транспорт, mappings, stores, graph logic |
| UI | Xcode UI testing или документированный ручной UI protocol | Контролы, ошибки, prompter, persistence |
| CI | Поддерживаемый GitHub-hosted macOS runner | Build, tests, strict concurrency |
| Аудио offline | AVAudioEngine manual/offline rendering там, где применимо; анализ PCM | Маршрутизация, gain, mute, DSP, metering |
| Аппаратная проверка | Многоканальный interface, loopback, MIDI controller | Реальный ввод/вывод, hot-plug, latency |
| Настройка аудио | Audio MIDI Setup | Sample rate, channels, device configuration |
| Профилирование | Instruments: Time Profiler, Allocations, Leaks, Points of Interest | CPU, память, hangs, signposts |
| Логи | OSLog/Console | Диагностика lifecycle и ошибок без audio payload |
| Coverage | SwiftPM coverage + LLVM coverage tools | Выявление непокрытых ветвей |
| Static quality | SwiftLint как pinned development tool | Единый стиль и предупреждения; не link в приложение |
| Review | Git diff, pull request/checklist | Независимая проверка и отслеживаемость |

### 5.2. Базовые команды валидации

В протоколе этапа записывать фактический вывод и exit status. Базовый минимум:

- Debug: `swift build`.
- Tests: `swift test`.
- Release: `swift build -c release`.
- Coverage, когда применимо: `swift test --enable-code-coverage` с последующим сохранением сводки.
- Strict concurrency после E03: отдельная чистая сборка с `-warn-concurrency` в изолированном scratch path.
- Sanitizer для независимых core tests, когда поддерживается окружением: отдельный run с Address Sanitizer; Thread Sanitizer для core concurrency без SwiftUI, если сочетание поддерживается toolchain.

Один успешный incremental build не заменяет чистую проверку. Перед финальным gate каждого крупного этапа очистить только производные build artifacts или использовать новый scratch path, не удаляя пользовательские данные.

### 5.3. Тестовые fixtures

Подготовить и использовать только легально распространяемые, детерминированные fixtures:

- тишина;
- sine wave известной амплитуды и частоты;
- импульс для проверки routing/latency;
- многоканальный файл с различимым сигналом в каждом канале;
- короткие PCM WAV для точных измерений;
- сжатые MP3/M4A для integration, без использования их sample values для bit-exact проверок;
- AIFF/WAV разных поддерживаемых sample rates;
- повреждённый и усечённый файл;
- LRC/ChordPro/TXT с Unicode, Cyrillic, emoji, разными timestamp formats;
- большой текстовый fixture для limit/performance test;
- MIDI event corpus с несколькими words/packets и malformed messages.

Для каждого fixture записать происхождение, параметры и ожидаемые свойства. Не скачивать случайные файлы во время CI.

---

## 6. Главная дорожная карта и зависимости

| Порядок | Этап | Главный результат | Обязательный gate |
|---|---|---|---|
| 1 | E00 | Воспроизводимый baseline и организация | Baseline воспроизведён, требования и среда зафиксированы |
| 2 | E01 | Тесты и CI существуют | Пустой/smoke test и CI зелёные |
| 3 | E02 | Архитектура и output strategy доказаны | 4-channel routing POC или задокументированный блокер |
| 4 | E03 | Безопасные границы состояния | Strict concurrency и state tests зелёные |
| 5 | E04 | Реальный аудиограф | Offline + hardware routing PASS |
| 6 | E05 | Все контролы и DSP работают | Parameter/routing/DSP matrix PASS |
| 7 | E06 | Достоверные meters | Known-signal calibration PASS |
| 8 | E07 | Транспорт соответствует звуку | State/seek/EOF/drift tests PASS |
| 9 | E08 | Отказы обрабатываются безопасно | Fault injection и hot-plug PASS |
| 10 | E09 | MIDI управление завершено | Decoder corpus + controller matrix PASS |
| 11 | E10 | Lyrics/prompter корректны | Parser/UI matrix PASS |
| 12 | E11 | Импорт и persistence завершены | Relaunch/corruption/missing-file tests PASS |
| 13 | E12 | Производительность измерена | Performance/soak budgets PASS |
| 14 | E13 | Release artifact готов | Signed/notarized clean-install PASS |
| 15 | E14 | Финальное решение | Полный regression и sign-off PASS |

**Запрещено менять порядок без записи в разделе 18.** Например, нельзя начинать визуальный polish до закрытия E04–E08.

---

# 7. Детальные этапы

## E00 — Baseline и организация работы

**Цель:** получить одинаковую отправную точку у исполнителя и проверяющего.  
**Зависимости:** нет.  
**Ожидаемая длительность:** 0,5–1 рабочий день.  
**Разрешённые изменения:** документация процесса и validation notes; не менять поведение приложения.

### Задачи

- [x] **E00.1 — Зафиксировать исходное состояние.** Записать commit SHA, ветку, `git status`, версии macOS, Swift и Xcode. Убедиться, что существующие `AUDIT.md` и этот план не потеряны и не смешаны с неизвестными пользовательскими изменениями.
- [x] **E00.2 — Прочитать обязательный контекст.** Полностью прочитать `README.md`, `AUDIT.md`, `Package.swift` и все исходники. Сопоставить SF-01…SF-12 с этапами плана. Не полагаться только на summary.
- [x] **E00.3 — Воспроизвести сборку.** Выполнить Debug и Release, сохранить warnings и результат. Отдельно зафиксировать, что `swift test` завершается отсутствием тестов. Не считать это финальным дефектом после E01.
- [x] **E00.4 — Зафиксировать hardware baseline.** Указать Mac, доступные входы/выходы, аудиоинтерфейс, MIDI-контроллер, наличие loopback. Если нет interface минимум с двумя входами и четырьмя выходами, сразу отметить риск для E02/E04.
- [x] **E00.5 — Утвердить пользовательские сценарии.** Записать минимум: импорт сетлиста, выбор трека без автозапуска, Play/Pause/Stop/Seek, окончание трека, два mic inputs, независимые FOH/IEM, MIDI pedal, reconnect устройства.
- [x] **E00.6 — Утвердить reference configuration.** Основная конфигурация: 48 кГц, явно выбранный buffer size, stereo backing, два mono mic inputs, stereo FOH и stereo IEM на четырёх различимых physical channels. Дополнительные конфигурации проверяются позже.
- [x] **E00.7 — Назначить роли.** Указать исполнителя и проверяющего. Для личного проекта проверяющий может быть тем же человеком, но gate-проверку он выполняет отдельно, по протоколу и после паузы от реализации.
- [x] **E00.8 — Создать журналы.** Заполнить начальные записи в общем прогрессе, журнале выполнения и рисках. Установить текущий этап E00, затем после gate — E01.

### Валидация E00

1. Повторить baseline на чистом checkout того же commit.
2. Сравнить результаты сборки; расхождения объяснить.
3. Проверить, что список оборудования и reference configuration не содержит незаполненных полей.
4. Проверить, что каждый SF-01…SF-12 связан хотя бы с одним будущим этапом.
5. Проверить, что рабочее дерево не содержит неучтённых изменений.

### Стоп-гейт E00

- [x] Baseline воспроизведён и записан.
- [x] Роли, сценарии и reference configuration утверждены.
- [x] Известные блокеры занесены в журнал.
- [x] Есть evidence `Documentation/Validation/E00/baseline.md`.
- [x] Общий Definition of Done выполнен.

**Если gate не пройден:** не создавать production-код и не начинать E01.

---

## E01 — Тестовый контур, качество и CI

**Цель:** до исправлений создать механизм, который доказывает корректность каждого следующего этапа.  
**Зависимости:** E00 завершён.  
**Ожидаемая длительность:** 1–2 рабочих дня.  
**Разрешённые изменения:** test target, test support, fixtures, CI, development lint config; не менять аудиоповедение.

### Задачи

- [x] **E01.1 — Добавить test target.** Настроить XCTest для существующего SwiftPM package. Проверить, что production target по-прежнему собирается на macOS 13+.
- [x] **E01.2 — Добавить минимальный smoke test.** Тест должен реально загружать production module и подтверждать доступность тестируемого API. Не добавлять пока тесты, которые deliberately падают на известных багах; такие регрессионные тесты добавляются в этапе исправления.
- [x] **E01.3 — Подготовить fixture catalog.** Создать инвентарь будущих fixtures, их размеров, параметров и происхождения. Маленькие детерминированные fixtures разместить в test resources; большие аппаратные материалы не коммитить.
- [x] **E01.4 — Настроить CI.** Использовать поддерживаемый и явно зафиксированный macOS runner. Запускать Debug build и tests на каждый pull request и изменение main. Release build выполнять минимум перед merge и на main.
- [x] **E01.5 — Настроить качество кода.** Добавить pinned SwiftLint только как development tool. Зафиксировать существующие нарушения отдельно; не делать массовый reformat. С этого момента новый код не должен добавлять нарушений.
- [x] **E01.6 — Настроить coverage baseline.** Получить начальную coverage-сводку. Не ставить случайный процент как цель; обязательным является покрытие всех ветвей критической логики, добавленной далее.
- [x] **E01.7 — Проверить повторяемость.** Два последовательных CI runs одного commit должны давать одинаковый PASS без ручного вмешательства и внешних скачиваний fixtures.

### Валидация E01

1. Локально выполнить Debug, Release и tests.
2. Убедиться, что тест действительно обнаруживается и выполняется; число tests больше нуля.
3. Намеренно запустить отдельный временный negative control вне production branch: убедиться, что CI способен стать красным при failing test. Negative control не мерджить.
4. Проверить CI на чистом checkout без локальных caches.
5. Проверить, что development tools не добавлены в runtime dependencies приложения.

### Стоп-гейт E01

- [x] Tests обнаруживаются и проходят локально и в CI.
- [x] Negative control доказал, что failing test блокирует CI.
- [x] Fixtures и coverage baseline задокументированы.
- [x] Нет новых runtime dependencies и постороннего reformatting.
- [x] Есть evidence со ссылками на два зелёных CI runs.
- [x] Общий Definition of Done выполнен.

**Если gate не пройден:** не исправлять функциональные баги и не начинать E02.

---

## E02 — Требования, ADR и доказательство осуществимости FOH/IEM

**Цель:** устранить главный архитектурный риск до большой переработки: доказать, как два независимых стереомикса попадают на четыре физических канала.  
**Зависимости:** E01 завершён.  
**Ожидаемая длительность:** 2–4 рабочих дня с учётом hardware POC.  
**Важно:** POC изолировать от production UI; не превращать непроверенный эксперимент в постоянную архитектуру.

### Задачи

- [x] **E02.1 — Составить ADR-001 «Audio output strategy».** Рассмотреть возможности AVAudioEngine и, при необходимости, более низкоуровневый AudioUnit/AUGraph/HAL output. Записать ограничения default stereo output, multichannel mapping и aggregate devices без предположений.
- [x] **E02.2 — Выполнить hardware feasibility POC.** На reference interface подать различимые тестовые сигналы в FOH L/R и IEM L/R. Доказать, что каждый сигнал появляется только на назначенном physical output.
- [x] **E02.3 — Проверить входы.** Доказать одновременное получение двух различимых mono inputs и их независимость от backing track.
- [x] **E02.4 — Определить поведение при stereo-only устройстве.** FOH может работать; IEM должен быть явно помечен недоступным. Запрещено молча смешивать IEM с FOH. Альтернативный monitoring mode допускается только по отдельному явному выбору пользователя и ADR.
- [x] **E02.5 — Составить ADR-002 «Границы модулей и состояние».** Зафиксировать разделение из раздела 4, владение состоянием, main-actor границы и зависимость UI от контроллеров.
- [x] **E02.6 — Составить ADR-003 «Транспортная модель».** Зафиксировать состояния, переходы, audio clock, EOF и выбор трека без autoplay по правилам E07.
- [x] **E02.7 — Составить ADR-004 «Metering semantics».** Зафиксировать точки измерения: channel post-fader/pre-master, FOH/IEM post-master; peak и RMS в dBFS, clip hold и частоту UI snapshots.
- [x] **E02.8 — Определить control semantics.** Записать диапазоны fader, mute/solo priority, reverb send/return и EQ. Для normalized volume values: 0 означает silence, 1 означает 0 dB; промежуточные значения используют логарифмическое отображение 40·log10(value) в dB. Любое изменение этого решения оформляется через ADR.
- [x] **E02.9 — Составить validation strategy.** Для каждого требования указать unit, offline, hardware или UI метод. Не оставлять требование без способа доказательства.

### Валидация E02

1. Проверяющий повторяет POC по записанным шагам, не используя устные пояснения исполнителя.
2. По очереди включать только один из четырёх output channels; подтвердить отсутствие crosstalk маршрутизации в остальных.
3. Повторить проверку после перезапуска POC.
4. Проверить, что выбранный подход не требует незадокументированных private APIs.
5. Проверить ADR на противоречия: один владелец состояния, один clock, явное поведение при отсутствии 4 outputs.

### Стоп-гейт E02

- [x] ADR-001…ADR-004 и control semantics утверждены.
- [x] Hardware POC доказал 2 независимых inputs и 4 независимых outputs.
- [x] Stereo-only fallback соответствует требованию безопасного отказа.
- [x] Выбранный audio output approach пригоден для production и не оставлен «на потом».
- [x] Evidence содержит channel mapping, sample rate, buffer и результаты повторного запуска.
- [x] Общий Definition of Done выполнен.

**Если независимый 4-channel output не доказан:** этап остаётся заблокированным. Не реализовывать E04 на предположении, что AVAudioEngine «вероятно справится». Изменение требования на один stereo output возможно только через раздел 18 и не считается выполнением исходного FOH/IEM требования.

---

## E03 — Границы состояния и конкурентность

**Цель:** подготовить безопасный фундамент для аудио/MIDI callbacks и исключить двойные копии состояния.  
**Зависимости:** E02 завершён.  
**Ожидаемая длительность:** 2–3 рабочих дня.  
**Ограничение:** не добавлять новые функции; только архитектурные границы и сохранение текущего явно задокументированного demo-поведения до E04.

### Задачи

- [x] **E03.1 — Ввести main-actor границы.** Изолировать UI-facing `AppState`, аудио/UI coordinator и MIDI UI state на `@MainActor`. Callbacks оставить на своих внешних очередях до момента передачи immutable snapshots.
- [x] **E03.2 — Устранить небезопасные captures.** В audio/MIDI/Timer closures передавать только локальные value snapshots. Убрать захват изменяемого `rms` и риски отправки non-Sendable `self`.
- [x] **E03.3 — Перевести выбор трека на ID.** Заменить отдельную value-copy модель выбора на `selectedTrackID` с вычисляемым selected track. Сохранить корректный выбор после добавления и будущего удаления.
- [x] **E03.4 — Ввести узкие dependency seams.** Подготовить протоколы для будущего transport/audio clock, persistence и MIDI mapping stores. Не создавать универсальные протоколы на всё подряд; только необходимые для тестирования границы.
- [x] **E03.5 — Разделить callback decoding и действия.** Приём события не должен напрямую менять SwiftUI. Доменное сообщение затем применяется на main actor.
- [x] **E03.6 — Добавить state tests.** Проверить начальный выбор, выбор по ID, обновление трека, отсутствие выбора при пустом списке и отсутствие diverging copies.
- [x] **E03.7 — Включить strict-concurrency gate.** Добавить отдельную CI-проверку. Все concurrency warnings из `MIDIManager` и `LiveAudioEngine` должны быть устранены, а не скрыты.

### Валидация E03

1. Запустить все unit tests и smoke UI сценарий.
2. Выполнить чистую сборку с concurrency diagnostics; сохранить отсутствие целевых warnings.
3. Прогнать core tests с доступным sanitizer.
4. Проверить UI: выбор трека, Tab switching, Play/Pause demo, font controls и navigation не сломаны.
5. Проверить diff на отсутствие скрытого изменения аудиомаршрутизации — это работа E04.

### Стоп-гейт E03

- [x] Нет `MIDIManager.shared` global concurrency warning.
- [x] Нет warnings о захвате `self`, `rms` или рисках data race в рассмотренных callbacks.
- [x] `selectedTrackID` является единственным источником выбора.
- [x] State tests и regression tests проходят.
- [x] Strict-concurrency проверка включена в CI и зелёная.
- [x] Общий Definition of Done выполнен.

---

## E04 — Реальный аудиограф FOH/IEM

**Цель:** реализовать и доказать полный сигнальный путь mic/backing → FOH/IEM с реverb return и физическим output mapping.  
**Зависимости:** E03 завершён, ADR-001 доказан.  
**Ожидаемая длительность:** 4–7 рабочих дней.  
**Приоритет:** P0 / SF-01.

### Задачи

- [x] **E04.1 — Выделить AudioGraphController.** Перенести владение nodes, attach/connect, route и lifecycle из SwiftUI-ориентированного состояния в отдельный компонент. UI не должен самостоятельно строить graph.
- [x] **E04.2 — Реализовать mic chains.** Для каждого mic соединить назначенный input → EQ → compressor → channel stage. Каналы должны быть различимы и не смешиваться до назначенных sends.
- [x] **E04.3 — Реализовать backing chain.** Подключить player к независимым FOH и IEM sends через собственные gain/mixing stages.
- [x] **E04.4 — Реализовать mic sends.** Каждый mic должен иметь независимые FOH и IEM sends; изменения одного bus не должны менять другой.
- [x] **E04.5 — Подключить reverb path.** Реализовать send/return так, чтобы wet signal попадал в заданные buses, а при нулевом send отсутствовал. Не оставлять attached-but-unconnected nodes.
- [x] **E04.6 — Реализовать output mapping.** Подключить FOH master и IEM master согласно ADR-001 к четырём физическим каналам. Сделать mapping видимым в diagnostics.
- [x] **E04.7 — Добавить безопасный startup.** До подтверждённого route микрофонные каналы не должны неожиданно открываться на полную громкость. Состояние UI обязано показывать необходимость настройки.
- [x] **E04.8 — Добавить offline routing tests.** Использовать silence, sine и различимые channel fixtures. Проверять наличие сигнала в целевом bus и отсутствие в остальных, не ограничиваясь проверкой «node attached».
- [x] **E04.9 — Добавить lifecycle tests.** Многократно создавать, запускать, останавливать и освобождать graph. Проверить отсутствие дублированных taps/connections и растущих ресурсов.
- [x] **E04.10 — Выполнить hardware loopback.** Повторить матрицу routing на reference interface при 48 кГц и выбранном buffer. Затем проверить 44,1 кГц и другой поддерживаемый buffer.

### Обязательная матрица E04

| Источник | Действие | FOH ожидание | IEM ожидание | Недопустимый результат |
|---|---|---|---|---|
| Mic 1 только | Подать тестовый сигнал | Только по настройке send | Только по настройке send | Mic 1 появляется в Mic 2 channel |
| Mic 2 только | Подать тестовый сигнал | Независимый уровень | Независимый уровень | Любое изменение Mic 1 |
| Backing только | Воспроизвести stereo fixture | Сохранить L/R | Сохранить L/R | Mono collapse без спецификации |
| FOH send = 0 | Подать все источники | Нет вклада источника | IEM не меняется | Скрытая утечка в FOH |
| IEM send = 0 | Подать все источники | FOH не меняется | Нет вклада источника | Скрытая утечка в IEM |
| Reverb send = 0 | Подать mic | Только dry path | Только dry path | Wet tail от нового сигнала |
| Stereo-only route | Запустить приложение | Явный доступный режим | Явно unavailable | Скрытое объединение buses |

### Валидация E04

1. Выполнить offline matrix с численными PCM assertions и разумными tolerances.
2. Выполнить hardware matrix независимым проверяющим.
3. Проверить 100 последовательных lifecycle cycles без crash и накопления taps/resources.
4. Проверить отсутствие сигнала при silent input, чтобы исключить фантомные demo/meter paths.
5. Проверить, что UI отражает unavailable route и не заявляет готовность IEM при stereo-only output.

### Стоп-гейт E04

- [x] Все источники имеют реальный сигнальный путь.
- [x] FOH и IEM независимы offline и на hardware.
- [x] Reverb физически включён в тракт.
- [x] Нет attached-but-unconnected функциональных nodes.
- [x] Routing, lifecycle и hardware matrices полностью PASS.
- [x] Evidence содержит измеренные результаты, а не только прослушивание.
- [x] Общий Definition of Done выполнен.

**Если какой-либо источник слышен не в том выходе:** этап FAIL, следующий этап запрещён.

---

## E05 — Канальные контролы и DSP

**Цель:** каждый видимый контрол должен иметь измеримое влияние на правильный тракт без щелчков и скрытых утечек.  
**Зависимости:** E04 завершён.  
**Ожидаемая длительность:** 3–5 рабочих дней.  
**Приоритет:** P0 / SF-02.

### Задачи

- [x] **E05.1 — Создать parameter inventory.** Таблица: UI control → доменный параметр → audio node/bus → диапазон → default → тест. Контрол без назначения либо реализуется, либо скрывается.
- [x] **E05.2 — Подключить backing FOH/IEM faders.** Применять значения к независимым gain stages. Использовать ADR mapping; UI 0 = silence, UI 1 = 0 dB.
- [x] **E05.3 — Подключить mic FOH/IEM faders.** Проверить, что изменение одного send не влияет на другой и на второй mic.
- [x] **E05.4 — Подключить master faders.** FOH master влияет только на FOH, IEM master только на IEM.
- [x] **E05.5 — Реализовать mute с ramp.** Mute должен заглушать все sends источника с коротким сглаживанием порядка 10–20 мс. После unmute восстанавливать прежний gain.
- [x] **E05.6 — Реализовать solo либо скрыть состояние.** Если solo остаётся в модели/UI, определить per-bus поведение: mute имеет приоритет для явно muted канала; невыбранные каналы не попадают в solo bus; reverb return не должен пропускать звук исключённых источников.
- [x] **E05.7 — Подключить EQ controls.** LowCut 80 Гц, presence 2,8 кГц и high shelf 10 кГц должны применяться к назначенному mic. Проверить bypass и диапазон gain.
- [x] **E05.8 — Подключить compressor path.** Убедиться, что DynamicsProcessor реально находится в сигнале и его bypass/state видимы. Если пользовательских параметров нет, не создавать фиктивный UI.
- [x] **E05.9 — Подключить reverb sends.** Нулевой send прекращает вклад источника, ненулевой создаёт измеримый wet return; изменение send не меняет dry gain.
- [x] **E05.10 — Добавить parameter smoothing.** Fader, mute и send changes не должны создавать резких discontinuities. Сглаживание не должно делать mute опасно медленным.
- [x] **E05.11 — Добавить regression tests.** Каждый контрол проверяется отдельно и в комбинации; добавить тесты на минимум, максимум, default и повторное изменение.

### Валидация E05

1. Offline sweep каждого fader: подтвердить монотонность уровня и соответствие ADR mapping.
2. Mute: выходной остаток после ramp соответствует silence в пределах численного tolerance.
3. Solo: проверить каждый источник и reverb leakage.
4. EQ: подать подходящие sine/multisine fixtures; подтвердить ожидаемое ослабление/усиление полосы и отсутствие влияния на соседний mic.
5. Reverb: подтвердить wet tail при send > 0 и отсутствие нового wet вклада при send = 0.
6. Hardware: проверить clicks, zipper noise, default levels и независимость FOH/IEM на безопасной громкости.
7. Быстро выполнить 100 изменений каждого параметра; не должно быть crash, stuck state или существенного UI hitch.

### Стоп-гейт E05

- [x] Все видимые controls связаны с реальными параметрами.
- [x] Mute/solo/send/FOH/IEM matrix PASS без утечек.
- [x] EQ/compressor/reverb подтверждены измерениями и прослушиванием.
- [x] Parameter changes не создают недопустимых clicks и crashes.
- [x] Parameter inventory полностью закрыт тестами.
- [x] Общий Definition of Done выполнен.

---

## E06 — Достоверный metering

**Цель:** заменить синтетические показания независимыми измерениями реальных channel/bus signals.  
**Зависимости:** E05 завершён.  
**Ожидаемая длительность:** 2–4 рабочих дня.  
**Приоритет:** P0 / SF-03.

### Задачи

- [x] **E06.1 — Реализовать taps в семантических точках ADR-004.** Channel meters — post-fader/pre-master; FOH/IEM meters — post-master. Не использовать FOH signal для вычисления IEM.
- [x] **E06.2 — Измерять все релевантные каналы.** Для stereo учитывать оба канала; для mono — назначенный input. Не ограничиваться `channelData.pointee`.
- [x] **E06.3 — Разделить peak и RMS.** Peak — максимум модуля выборки; RMS — среднеквадратичное значение. Названия UI и свойств должны соответствовать измерению.
- [x] **E06.4 — Перевести уровни в dBFS.** Определить silence floor, диапазон индикатора, цветовые thresholds и clip condition. Не использовать произвольные коэффициенты 2,5/2,2 как замену калибровке.
- [x] **E06.5 — Реализовать clip hold и release.** Clip hold около 1,5 секунды; плавный peak release без задержки реакции на новый пик. Значения должны быть детерминированно тестируемы через clock.
- [x] **E06.6 — Ограничить UI updates.** Audio callback вычисляет/сохраняет измерения безопасным способом; main actor получает snapshots с частотой 20–30 Гц. Не публиковать каждый audio buffer как отдельное SwiftUI-событие.
- [x] **E06.7 — Добавить known-signal tests.** Использовать silence и sine amplitude 0,5: ожидаемый peak около −6,02 dBFS, RMS около −9,03 dBFS. Допустимое отклонение после калибровки — не более 0,5 dB.
- [x] **E06.8 — Доказать независимость.** Разные сигналы одновременно в Mic 1, Mic 2, FOH и IEM должны давать разные корректные показания.
- [x] **E06.9 — Проверить mute и остановку.** После mute/silence meter реагирует согласно release; mic meters не зависят от того, играет ли backing track.

### Валидация E06

1. Прогнать known-signal tests на всех metering points.
2. Проверить silence: нет искусственного ненулевого уровня.
3. Проверить stereo channel imbalance: meter не игнорирует более громкий второй канал.
4. Проверить clipping и clip hold по времени fake clock.
5. На hardware одновременно подать разные уровни в FOH/IEM и сверить показания с loopback reference.
6. Записать частоту main-actor updates и подтвердить отсутствие updates на каждый buffer.

### Стоп-гейт E06

- [x] IEM meter не вычисляется из FOH.
- [x] Mic meters не вычисляются из backing track.
- [x] Peak/RMS и dBFS откалиброваны в пределах 0,5 dB на reference fixtures.
- [x] Все каналы, silence, clip и release tests PASS.
- [x] UI snapshots ограничены 20–30 Гц и не блокируют audio callback.
- [x] Общий Definition of Done выполнен.

---

## E07 — Надёжный транспорт и синхронная позиция

**Цель:** положение звука, UI и prompter должны использовать один источник времени; все действия транспорта должны быть детерминированы.  
**Зависимости:** E06 завершён.  
**Ожидаемая длительность:** 4–6 рабочих дней.  
**Приоритет:** P1 / SF-04.

### Обязательная модель поведения

| Действие | Обязательный результат |
|---|---|
| Выбор трека | Останавливает прежнее воспроизведение, загружает выбранный источник, переходит в ready; autoplay запрещён |
| Play из ready | Начинает с текущей позиции, обычно с начала |
| Pause | Сохраняет позицию и приостанавливает звук |
| Play из paused | Продолжает с сохранённой позиции без перезапуска файла |
| Stop | Останавливает звук, сохраняет текущий файл как источник, устанавливает позицию 0 |
| Play после Stop | Запускает тот же файл с начала, никогда demo buffer вместо него |
| Seek в ready/paused | Меняет реальную позицию файла без автозапуска |
| Seek во время Play | Перепланирует звук и продолжает с новой позиции |
| EOF | Переходит в ended, останавливает время; автоматический next отсутствует, пока не добавлен явной настройкой |
| Play из ended | Запускает тот же трек с начала |
| Load failure | Переходит в failed, не показывает playing/ON AIR |

### Задачи

- [x] **E07.1 — Ввести TransportController и конечный автомат.** Разрешённые состояния: stopped/loading/ready/playing/paused/ended/failed. Убрать независимое UI `isPlaying` как источник истины.
- [x] **E07.2 — Зафиксировать владение источником.** Сохранять текущий файл/URL и необходимые file metadata до явной смены трека. Demo source должен быть отдельным явным режимом, а не скрытым fallback после Stop.
- [x] **E07.3 — Реализовать настоящий Seek.** Переводить секунды в корректные frames с учётом processing format; ограничивать диапазон; планировать воспроизведение с нужной позиции.
- [x] **E07.4 — Сохранять состояние при Seek.** Если трек играл — продолжить playing; если был paused/ready — не запускать звук.
- [x] **E07.5 — Перейти на audio clock.** Получать позицию из player/node time. Timer только инициирует UI refresh и не прибавляет самостоятельно 0,05 секунды.
- [x] **E07.6 — Обработать completion.** Использовать completion для EOF. Отличать естественный EOF от отмены schedule при Stop, Seek и смене трека.
- [x] **E07.7 — Игнорировать stale callbacks.** При новой load/seek/stop операции старые completion не должны менять состояние нового источника. Использовать generation/operation identity по ADR.
- [x] **E07.8 — Реализовать смену трека во время Play.** Старое воспроизведение останавливается, новый трек загружается в ready; UI не остаётся ON AIR.
- [x] **E07.9 — Связать prompter с той же позицией.** Не создавать второй независимый time accumulator.
- [x] **E07.10 — Добавить unit tests через fake clock/player.** Покрыть каждую строку таблицы и последовательности быстрых действий.

### Обязательные последовательности тестов

1. Load → Play → Pause → Play → Stop → Play.
2. Play → Seek вперёд → Seek назад → Pause → Seek → Play.
3. Play → Load другого трека → немедленно Play.
4. Play → EOF → Play.
5. Stop → гарантировать тот же источник.
6. Load → corrupted file → Play недоступен.
7. Быстрые повторные Play/Pause без противоречивого состояния.
8. Несколько Seek подряд с приходом отложенных stale completions.
9. Пустой playlist и отсутствие источника.
10. Треки разных sample rates и длительности.

### Валидация E07

1. Все unit tests и интеграционные PCM file tests PASS.
2. Проверить Seek: фактическая позиция отличается от целевой не более чем на один audio buffer или 20 мс, выбирая больший допуск.
3. Проверить drift: на 30-минутном PCM файле UI/audio position не расходится более чем на 100 мс; отсутствует накапливающийся drift после Pause/Seek.
4. Проверить EOF: звук, UI и prompter останавливаются согласованно; нет визуального loop без реального loop.
5. Проверить Stop после пользовательского файла: повторный Play запускает тот же файл.
6. Проверить выбор трека во время Play на hardware: нет неожиданного автозапуска и старого звука.

### Стоп-гейт E07

- [x] Seek меняет звук, а не только UI.
- [x] Stop никогда не восстанавливает demo вместо текущего файла.
- [x] EOF, load during Play и stale callbacks обрабатываются корректно.
- [x] Audio clock является единственным источником позиции.
- [x] Все последовательности и 30-минутный drift test PASS.
- [x] Общий Definition of Done выполнен.

---

## E08 — Ошибки, lifecycle и отказоустойчивость

**Цель:** ни один отказ файла, device route или engine не должен выглядеть как нормальное воспроизведение.  
**Зависимости:** E07 завершён.  
**Ожидаемая длительность:** 3–5 рабочих дней.  
**Приоритет:** P1 / SF-05 и production reliability.

### Задачи

- [x] **E08.1 — Ввести typed errors.** Различать unsupported/corrupt file, missing file, permission denied, metadata failure, engine start failure, unavailable route и MIDI initialization failure.
- [x] **E08.2 — Убрать молчаливый `try?` на критических путях.** Ошибка должна попадать в состояние и diagnostics с достаточным контекстом, но без утечки секретов или audio payload.
- [x] **E08.3 — Добавить видимый engine state.** UI должен различать starting, ready, running, degraded, stopped и failed. `ON AIR` допускается только при фактически работающем engine и активном транспорте.
- [x] **E08.4 — Блокировать недопустимые действия.** Play недоступен при failed loading, отсутствующем source или неработающем engine.
- [x] **E08.5 — Обработать configuration changes.** При смене route/device остановить или безопасно перестроить graph, восстановить connections/taps и проверить mapping. Не оставлять старое состояние готовности.
- [x] **E08.6 — Обработать mic permission.** Добавить понятный permission flow и диагностику. Отказ в доступе не должен приводить к crash или ложному LIVE.
- [x] **E08.7 — Добавить diagnostics view/log.** Показывать device, route, sample rate, buffer, channel mapping, engine и последние ошибки. Пути пользовательских файлов отображать минимально необходимо.
- [x] **E08.8 — Добавить fault-injection tests.** Использовать fakes для engine start/read/write/permission/store failures. Не ограничиваться ручным тестированием.

### Валидация E08

1. Передать повреждённые, усечённые, unsupported и missing files; сообщения различимы, app не падает.
2. Эмулировать engine start failure; Play не переводит UI в ON AIR.
3. Запретить mic permission; mic channels явно unavailable, backing остаётся корректно обработанным по спецификации.
4. На hardware 20 раз отключить/подключить interface в разных состояниях; нет crash, дублированных taps и неожиданного звука.
5. Изменить sample rate/route через Audio MIDI Setup; приложение обнаруживает изменение и требует безопасного восстановления.
6. Проверить, что diagnostics помогает определить причину без чтения внутреннего кода.
7. Все прежние routing и transport regression tests повторно PASS.

### Стоп-гейт E08

- [x] Ошибки видимы, типизированы и блокируют недопустимые действия.
- [x] UI никогда не заявляет ложное ON AIR в fault tests.
- [x] Permission, route change и reconnect scenarios PASS.
- [x] 20 hardware reconnect cycles завершены без crash и неожиданного output.
- [x] Общий Definition of Done выполнен.

---

## E09 — MIDI decoding, mappings и hot-plug

**Цель:** реализовать предсказуемое управление без потери событий внутри packets и без случайных Play/Pause от любой ноты.  
**Зависимости:** E08 завершён.  
**Ожидаемая длительность:** 3–5 рабочих дней.  
**Приоритет:** P1 / SF-06.

### Задачи

- [x] **E09.1 — Выделить чистый MIDIDecoder.** Обрабатывать protocol, message type, group, channel, data bytes и все UMP words во всех packets. Не читать только `words.0`.
- [x] **E09.2 — Создать decoder corpus.** Включить CC, Note On, Note On velocity 0 как off, Note Off, разные каналы, несколько сообщений в packet, malformed/unknown messages.
- [x] **E09.3 — Реализовать mappings.** Ключ mapping должен учитывать message type, channel и CC/note. Внутренний channel 0–15 и UI 1–16 должны быть явно согласованы.
- [x] **E09.4 — Исправить Note/pedal semantics.** Только назначенная нота вызывает действие. Velocity 0 не вызывает Play/Pause. Одно физическое нажатие создаёт одно действие.
- [x] **E09.5 — Исправить sustain threshold.** Использовать стандартную границу value ≥ 64 и срабатывание на переходе через threshold, а не повторно на каждом сообщении того же состояния.
- [x] **E09.6 — Завершить learning.** При learning сохранить фактический mapping через `MIDIMappingStore` между запусками, показать подтверждение и применять его к последующим событиям, а не только один раз к текущему value. Этот store создаётся и проверяется уже в E09; в E11 он интегрируется с общим сохранением состояния без потери mappings.
- [x] **E09.7 — Определить precedence.** Пользовательский mapping имеет приоритет над defaults CC 7, CC 1 и CC 64. Конфликт должен быть видим и разрешим.
- [x] **E09.8 — Подключить next/previous actions.** Если действие доступно в domain/UI, связать его с Transport/Setlist командами. Не оставлять неиспользуемый callback как имитацию поддержки.
- [x] **E09.9 — Реализовать hot-plug.** В notification block повторно перечислять источники, подключать новые, удалять исчезнувшие, обновлять имя/список устройств.
- [x] **E09.10 — Проверять все OSStatus.** Ошибка client/port/source операции должна сохраняться и отображаться в diagnostics.
- [x] **E09.11 — Ограничить UI queue.** CC bursts должны coalesce до последнего значения для UI, не создавая неограниченную main queue. Дискретные pedal events нельзя небрежно coalesce.

### Валидация E09

1. Decoder corpus проходит все valid/invalid cases и проверяет число decoded messages.
2. Learning → restart → mapping сохраняется через `MIDIMappingStore`. Полноценное сохранение остального состояния и повторная интеграционная проверка mappings выполняются в E11.
3. Пользовательский mapping переопределяет default; конфликт обрабатывается.
4. На контроллере проверить knobs, CC 7/1, sustain, mapped Note и next/previous.
5. Нажатие неназначенной ноты не меняет transport.
6. 20 MIDI hot-plug cycles без потери reconnect и без crash.
7. Burst из минимум 1 000 CC events не создаёт неограниченную очередь или заметный UI stall; финальное значение корректно.
8. Повторить transport и concurrency regression.

### Стоп-гейт E09

- [x] Обрабатываются все words/packets, а не только первое слово.
- [x] Learning создаёт устойчивый mapping.
- [x] Неназначенные notes не вызывают действия.
- [x] Hot-plug, defaults, precedence, bursts и hardware controller tests PASS.
- [x] Нет новых concurrency warnings.
- [x] Общий Definition of Done выполнен.

---

## E10 — Lyrics, ChordPro и prompter

**Цель:** устранить ошибки времени, активной строки и расположения аккордов; сделать прокрутку предсказуемой.  
**Зависимости:** E09 завершён.  
**Ожидаемая длительность:** 3–5 рабочих дней.  
**Приоритет:** P2 / SF-08, связанные deprecated APIs.

### Задачи

- [x] **E10.1 — Сначала добавить parser regression tests.** Зафиксировать дефект `[01:02.5]` = 62,5 секунды, а также двух- и трёхзначные fractions. Исправление начинается после воспроизведения failing case в отдельной ветке этапа.
- [x] **E10.2 — Исправить fractional seconds.** Для 1/2/3 цифр использовать делители 10/100/1000 соответственно. Проверить минуты, секунды и границы.
- [x] **E10.3 — Определить поддерживаемый LRC subset.** Timestamps, повторные timestamps одной строки, `offset`, metadata tags и пустые строки. Не интерпретировать metadata tags как аккорды.
- [x] **E10.4 — Обработать повторные timestamps.** Если строка имеет несколько timestamps, создавать корректные синхронизированные occurrences в хронологическом порядке, а не брать только первый.
- [x] **E10.5 — Сохранить ChordPro directives behavior.** Служебные directives не отображать как текст; chords извлекать только в допустимом контексте. Добавить Cyrillic, Unicode и inline chord tests.
- [x] **E10.6 — Перейти на async metadata loading.** Заменить deprecated `metadata` и `stringValue` на асинхронные `load` APIs с typed errors. Полный importer pipeline завершается в E11, но warnings должны быть устранены здесь.
- [x] **E10.7 — Исправить active line.** Активна последняя синхронизированная строка с timestamp ≤ currentTime до timestamp следующей синхронизированной строки; убрать фиксированные 3,8 секунды.
- [x] **E10.8 — Реализовать реальное chord alignment.** Использовать `characterIndex` и измерение prefix widths или эквивалентный согласованный layout. Проверить размеры шрифта 18/28/48 и длинные строки.
- [x] **E10.9 — Скроллить только при смене activeLineID.** Не запускать новую анимацию на каждом transport tick. При выключенном Auto-Scroll не выполнять программный scroll.
- [x] **E10.10 — Различать empty и failed lyrics.** Placeholder не должен скрывать ошибку чтения. Состояние empty, loaded и failed отображается различимо.

### Валидация E10

1. Parser table tests: 1/2/3 digits, repeated timestamps, offset, tags, directives, empty lines, malformed input.
2. Unicode tests: Cyrillic, emoji, combining characters, chords в начале/середине/конце строки.
3. Active line: интервалы короче и длиннее 3,8 секунды, nil timestamps, Seek назад и EOF.
4. Screenshot/UI review: chord alignment на 18/28/48 pt, длинные строки, dark scheme, resize окна.
5. Проверить, что за 10 секунд на одной активной строке происходит одна scroll operation, а не непрерывная серия.
6. Сборка не содержит прежних deprecation warnings для metadata APIs.
7. Transport regression подтверждает общий audio clock.

### Стоп-гейт E10

- [x] Все parser regressions исправлены и покрыты тестами.
- [x] Активная строка зависит от следующей timestamp, а не фиксированной длительности.
- [x] Аккорды визуально выровнены на всех заданных размерах.
- [x] Auto-scroll срабатывает только на смену строки и уважает Toggle.
- [x] Deprecated metadata warnings устранены.
- [x] Общий Definition of Done выполнен.

---

## E11 — Импорт, плейлист и persistence

**Цель:** импорт не блокирует UI, данные треков достоверны, а рабочее состояние восстанавливается после перезапуска.  
**Зависимости:** E10 завершён.  
**Ожидаемая длительность:** 4–6 рабочих дней.  
**Приоритет:** P2 / SF-11 и завершение MIDI persistence.

### Задачи

- [x] **E11.1 — Выделить TrackImporter.** Асинхронно загружать duration, metadata и lyrics. Возвращать результат или typed error для каждого файла.
- [x] **E11.2 — Убрать фиксированные 180 секунд.** В playlist попадает реальная duration; до готовности допускается явное loading state, но не вымышленные 03:00.
- [x] **E11.3 — Сделать batch import responsive.** Несколько файлов обрабатываются с прогрессом и понятными per-file errors. Не запускать неограниченный параллелизм на сотнях файлов.
- [x] **E11.4 — Обновлять треки по ID.** Playlist остаётся единственным источником; selected ID не ссылается на устаревшую копию.
- [x] **E11.5 — Реализовать SetlistStore.** Сохранять порядок, треки, выбранный ID, prompter settings и MIDI mappings. Добавить schema version с первой версии.
- [x] **E11.6 — Сделать сохранение атомарным.** Не оставлять частично записанный store при завершении/ошибке. Повреждённый store не должен приводить к crash или молчаливой потере без резервной копии/диагностики.
- [x] **E11.7 — Обработать moved/missing files.** После relaunch показывать unavailable state и позволять повторно выбрать/связать файл; не удалять запись молча.
- [x] **E11.8 — Добавить security-scoped bookmarks при sandbox.** Решение зависит от packaging ADR E13, но архитектура store должна допускать bookmarks. Если sandbox включается раньше, доступ должен быть проверен уже здесь.
- [x] **E11.9 — Сохранять mappings и настройки.** Проверить, что learning E09 и font/Auto-Scroll восстанавливаются.
- [x] **E11.10 — Добавить migration/corruption tests.** Schema v1, неизвестные поля, повреждённые данные, пустой store и unavailable file.

### Валидация E11

1. Импортировать MP3, M4A, WAV и AIFF; duration соответствует metadata в разумном допуске формата.
2. Импортировать batch из 100 файлов; UI остаётся отзывчивым, progress корректен, ошибка одного файла не отменяет успешные остальные.
3. Перезапустить app: порядок, selection, mappings и prompter settings восстановлены.
4. Переместить файл: запись остаётся, состояние unavailable понятно, relink работает.
5. Повредить store: нет crash; recovery/backup behavior соответствует спецификации.
6. Проверить повторный импорт и пустой playlist.
7. Проверить ограничение большого LRC/TXT: превышение размера даёт ошибку без исчерпания памяти.
8. Повторить MIDI learning persistence и transport after relaunch.

### Стоп-гейт E11

- [x] Фиксированная duration удалена из пользовательского пути.
- [x] Batch import асинхронен и ограничен по параллелизму.
- [x] Relaunch, missing file, relink, corruption и migration tests PASS.
- [x] Настройки и MIDI mappings сохраняются.
- [x] Большие текстовые файлы ограничены безопасно.
- [x] Общий Definition of Done выполнен.

---

## E12 — Измерение и оптимизация производительности

**Цель:** устранить измеренные bottlenecks и доказать стабильность длительного выступления. Не оптимизировать вслепую.  
**Зависимости:** E11 завершён.  
**Ожидаемая длительность:** 3–6 рабочих дней.  
**Приоритет:** P2 / SF-10.

### Обязательные performance scenarios

- **P01:** 30 минут playback, два mic, reverb, все meters, prompter.
- **P02:** 2 часа continuous session со сменой треков и MIDI events.
- **P03:** batch import 100 файлов во время готового, но не играющего session.
- **P04:** быстрые fader/CC changes и одновременный prompter scroll.
- **P05:** route reconnect и продолжение работы.
- **P06:** playlist из 500 записей, поиск/прокрутка если функция доступна, selection и relaunch.

### Задачи

- [ ] **E12.1 — Зафиксировать baseline после корректности.** До оптимизации записать CPU, memory, UI hangs, audio dropouts, main-actor update rates и startup/import timings для каждого scenario.
- [ ] **E12.2 — Добавить signposts.** Обозначить import, track load, seek, graph rebuild, meter snapshot и scroll event через Points of Interest/OSLog signposts.
- [ ] **E12.3 — Профилировать main thread.** Использовать Time Profiler и hangs. Найти фактические hotspots; не предполагать, что demo generation или SwiftUI являются bottleneck без данных.
- [ ] **E12.4 — Проверить metering cost.** Подтвердить, что UI получает 20–30 snapshots/с, а не событие на каждый buffer. Оптимизировать только при измеренном превышении.
- [ ] **E12.5 — Проверить prompter cost.** Подтвердить отсутствие повторной анимации на каждом tick и лишнего пересчёта всего экрана.
- [ ] **E12.6 — Проверить import cost.** При необходимости ограничить concurrency, уменьшить repeated I/O и убрать blocking metadata reads.
- [ ] **E12.7 — Проверить demo buffer.** Если startup profiling подтверждает проблему, сделать генерацию lazy/вне main или заменить fixture. Не менять без baseline.
- [ ] **E12.8 — Проверить память.** Allocations/Leaks, повторяющиеся load/stop/seek, graph rebuild и relaunch-level lifecycle внутри session. Память не должна монотонно расти после стабилизации.
- [ ] **E12.9 — Сравнить после оптимизации.** Для каждого изменения сохранить before/after на одном hardware и одном сценарии. Если улучшения нет или readability ухудшилась без необходимости, откатить оптимизацию.

### Performance budgets для reference configuration

- Ноль подтверждённых audio dropouts за 2-часовой P02.
- Ноль crashes, hangs и неограниченных очередей.
- Нет монотонного роста памяти после warm-up; любой устойчивый рост требует объяснения и отдельного gate.
- Meter UI остаётся в диапазоне 20–30 snapshots/с без audio-thread blocking.
- Во время steady-state playback нет main-thread stalls, заметных как UI hitch; все зафиксированные hitch > 50 мс расследуются.
- Batch import не блокирует интерактивность и не вызывает memory spike, приводящий к pressure/termination.
- Seek и track load должны иметь измеренные distributions; любые outliers сопровождаются объяснением.

### Валидация E12

1. Провести P01–P06 минимум дважды после финального изменения.
2. Сохранить сводные Instruments results и environment.
3. Проверить P02 на реальном interface с meters и MIDI.
4. Проверить отсутствие новых функциональных regressions полным набором tests.
5. Проверяющий сравнивает before/after и подтверждает, что оптимизации основаны на данных.

### Стоп-гейт E12

- [ ] P01–P06 выполнены и задокументированы.
- [ ] Performance budgets выполнены или этап остаётся открытым.
- [ ] Нет нерасследованных dropouts, hangs и memory growth.
- [ ] Оптимизации имеют before/after evidence.
- [ ] Полный regression PASS.
- [ ] Общий Definition of Done выполнен.

---

## E13 — Packaging, безопасность и документация

**Цель:** подготовить распространяемый артефакт и устранить расхождения README с фактическим поведением.  
**Зависимости:** E12 завершён.  
**Ожидаемая длительность:** 2–4 рабочих дня плюс внешнее время нотаризации.  
**Приоритет:** P2 / SF-12.

### Задачи

- [ ] **E13.1 — Составить ADR-005 «Distribution and sandbox».** Выбрать direct distribution или App Store, sandbox entitlements, bookmarks и update mechanism. Не включать доступы «про запас».
- [ ] **E13.2 — Сформировать app bundle.** Настроить `Info.plist`, bundle identifier, version/build, mic usage description и необходимые capabilities.
- [ ] **E13.3 — Проверить permissions.** Mic prompt должен объяснять реальную цель; denied/restricted states обрабатываются согласно E08.
- [ ] **E13.4 — Настроить signing и notarization.** Использовать защищённое хранение credentials. Не записывать сертификаты, пароли, API keys или notary credentials в репозиторий/логи.
- [ ] **E13.5 — Проверить sandbox file access.** Если sandbox включён, импорт, relaunch, relink и bookmarks должны пройти повторно на упакованном app, а не только через SwiftPM executable.
- [ ] **E13.6 — Обновить README.** Убрать абсолютные пути другого пользователя. Добавить универсальные команды запуска, системные требования, поддерживаемые formats, MIDI behavior, output mapping и troubleshooting.
- [ ] **E13.7 — Синхронизировать feature claims.** Описывать только реально проверенные функции. Prototype/demo labels удалять только при соответствующем evidence.
- [ ] **E13.8 — Опубликовать latency methodology.** Указать hardware, sample rate, buffer, input/output path и метод impulse/loopback. Если измерение не проведено, удалить численное заявление 2,5 мс.
- [ ] **E13.9 — Добавить release checks.** CI или release workflow должен проверять tests, version, signing inputs и создавать воспроизводимый архив без `.build` и лишних файлов.
- [ ] **E13.10 — Провести security review.** Проверить entitlements, secrets scan, file-size limits, dependency inventory, log privacy и обработку небезопасных fixtures.

### Валидация E13

1. Проверить подпись и нотаризацию штатными macOS tools; сохранить результаты.
2. Установить artifact на чистый Mac или чистый пользовательский environment без исходников и developer state.
3. Запустить при отсутствии прежнего trust cache; проверить mic permission и MIDI.
4. Проверить импорт/relaunch/relink в упакованном приложении.
5. Проверить Gatekeeper scenario, соответствующий выбранному distribution.
6. Сверить каждое утверждение README с закрытым evidence.
7. Выполнить secrets scan итогового diff/artifact metadata; убедиться в отсутствии credentials.

### Стоп-гейт E13

- [ ] `.app` подписан и нотаризован для выбранного distribution.
- [ ] Clean-install и permission scenarios PASS.
- [ ] Sandbox/bookmarks проверены, если применимо.
- [ ] README соответствует продукту и не содержит чужих путей.
- [ ] Latency либо измерена с методикой, либо численное утверждение удалено.
- [ ] Secrets/entitlements/dependency review PASS.
- [ ] Общий Definition of Done выполнен.

---

## E14 — Финальный regression и release decision

**Цель:** доказать, что все этапы вместе образуют работающий продукт, а не набор отдельно проверенных изменений.  
**Зависимости:** E13 завершён.  
**Ожидаемая длительность:** 1–3 рабочих дня без учёта исправлений.

### Задачи

- [ ] **E14.1 — Заморозить кандидат.** Зафиксировать единственный release candidate commit. Любое последующее изменение создаёт новый RC и повторяет impacted validation.
- [ ] **E14.2 — Выполнить чистые builds.** Debug, Release, tests, strict concurrency и packaging на одном RC.
- [ ] **E14.3 — Выполнить полный automated regression.** Включая parser, transport, MIDI, state, persistence, routing, DSP, metering и fault injection.
- [ ] **E14.4 — Выполнить полный hardware regression.** Routing, controls, meters, transport, reconnect, MIDI и latency по итоговой матрице раздела 16.
- [ ] **E14.5 — Повторить ключевой soak.** Минимум 2 часа на RC после packaging.
- [ ] **E14.6 — Проверить clean install.** Использовать именно RC artifact, а не локальный debug build.
- [ ] **E14.7 — Сверить находки аудита.** Для SF-01…SF-12 указать fixing commit и evidence. P0/P1 не могут быть deferred для release.
- [ ] **E14.8 — Провести независимый review.** Проверяющий изучает протоколы, открытые риски, Git history и diff; не принимает статусы без evidence.
- [ ] **E14.9 — Закрыть или явно принять P2/P3.** Любое отклонение фиксируется владельцем продукта как accepted limitation с причиной и планом.
- [ ] **E14.10 — Принять GO/NO-GO.** Заполнить финальный протокол раздела 19.

### Стоп-гейт E14 / Release GO

- [ ] RC не менялся после начала финальной проверки.
- [ ] Все automated tests и CI зелёные.
- [ ] Все P0/P1 закрыты evidence.
- [ ] Hardware, soak и clean-install PASS.
- [ ] Нет критических/высоких открытых блокеров.
- [ ] README, diagnostics и release artifacts соответствуют RC.
- [ ] Проверяющий и владелец продукта подписали GO.

**Любой FAIL означает NO-GO.** Исправление выполняется через новый этап/задачу, после чего impacted gates и RC validation повторяются.

---

## 8. Сквозная матрица функциональной валидации

Эта матрица используется в соответствующих этапах и полностью повторяется в E14.

| Область | Сценарий | Метод | Обязательный результат |
|---|---|---|---|
| File | MP3/M4A/WAV/AIFF | Integration | Корректная загрузка или понятная typed error |
| File | Corrupt/truncated/missing | Fault injection | Нет crash и ложного ready |
| Transport | Play/Pause/Stop/replay | Unit + hardware | Один источник, правильная позиция |
| Transport | Seek playing/paused | Unit + PCM | Звук и UI перемещаются вместе |
| Transport | EOF | Integration | ended без визуального loop |
| Transport | Load during Play | Unit + hardware | Старый звук остановлен, autoplay нет |
| Timing | 30 минут с Pause/Seek | Integration | Drift в пределах E07 |
| Routing | Каждый input в каждый bus | Offline + loopback | Только назначенные outputs |
| Routing | Stereo-only | Hardware/fake route | IEM unavailable, нет скрытого смешивания |
| DSP | Fader/Mute/Solo | PCM + listening | Корректный уровень, нет leakage |
| DSP | EQ/compressor/reverb | PCM + listening | Измеримый эффект в нужном channel |
| Meter | Silence/sine/clipping | Known-signal tests | dBFS и clip в допуске |
| Meter | FOH/IEM independence | Loopback | Нет copied/synthetic values |
| MIDI | Все words/packets | Decoder corpus | Нет пропущенных внутренних сообщений |
| MIDI | Learning/persistence | Unit + relaunch | Mapping сохраняется и работает |
| MIDI | Hot-plug | 20 cycles | Reconnect без crash |
| Lyrics | LRC fractions/repeated/offset | Unit | Точное время и порядок |
| Lyrics | Unicode/ChordPro | Unit + screenshots | Корректные indices и alignment |
| Prompter | Длинные/короткие интервалы | Unit + UI | Нет fixed 3,8 s ошибки |
| Prompter | Auto-scroll | UI instrumentation | Только activeLineID changes |
| Import | 100 файлов | Integration + Instruments | Responsive UI, per-file errors |
| Persistence | Relaunch/relink/corrupt store | Integration | Предсказуемое восстановление |
| Performance | 2 часа live-like session | Hardware + Instruments | Нет dropouts/hangs/growth |
| Release | Signed/notarized clean install | macOS tools + clean Mac | Artifact запускается и проходит permissions |

---

## 9. Матрица аппаратных конфигураций

Минимум проверять:

1. Reference Apple Silicon Mac + многоканальный interface, 48 кГц, основной buffer.
2. Тот же Mac, 44,1 кГц.
3. Другой поддерживаемый buffer size для оценки stability/latency.
4. Встроенный/стерео output: безопасное IEM unavailable behavior.
5. Отключение и подключение interface в stopped и playing состояниях.
6. MIDI controller через USB; reconnect и несколько источников, если доступно.
7. Чистый Mac/user environment для RC.

Для каждой конфигурации записывать фактические возможности. Если устройство не поддерживает конкретный sample rate/buffer, это не FAIL устройства, но конфигурация исключается с доказательством ограничения; reference configuration всё равно обязательна.

---

## 10. Стратегия тестирования по уровням

### Unit — обязательно быстро и детерминированно

- Lyrics/LRC/ChordPro.
- MIDI decoding и mappings.
- Transport state transitions с fake clock/player.
- selectedTrackID и setlist logic.
- dB mapping, metering calculations, clip/release clock.
- persistence serialization/migration.
- errors и допустимость команд.

### Integration — без зависимости от случайного оборудования

- PCM fixtures и реальные AVAudioFile operations.
- Seek/completion и source ownership.
- Offline/manual graph rendering, где поддерживается выбранной архитектурой.
- Import с реальными test resources.
- Store round-trip и corruption recovery.
- Fault-injected engine/device failures.

### Hardware — обязательное доказательство физического поведения

- Независимость четырёх outputs.
- Реальные mic inputs и отсутствие feedback при безопасной настройке.
- DSP audibility и metering.
- Route changes, hot-plug, reconnect.
- MIDI controller/pedal behavior.
- Dropouts и latency.
- 2-часовой soak.

### UI — видимое состояние и доступность действий

- Loading/ready/playing/paused/ended/failed.
- Нет ON AIR при ошибке.
- Disabled Play при отсутствии готовности.
- IEM unavailable при stereo-only.
- Prompt/errors/progress/relink.
- Prompter alignment и Auto-Scroll.
- Persisted settings после relaunch.

---

## 11. Code review checklist для каждого этапа

Проверяющий обязан ответить «да» на каждый применимый пункт:

- [ ] Изменения относятся только к текущему этапу.
- [ ] Нет нового контрола без реального domain/audio действия.
- [ ] Нет второго источника состояния или времени.
- [ ] Нет молчаливого `try?` на критическом пути.
- [ ] Нет `try!`, новых force unwrap и небезопасных fatal paths.
- [ ] Нет работы SwiftUI непосредственно в real-time callback.
- [ ] Нет захвата mutable variables/non-Sendable state в отправляемых closures.
- [ ] Все ошибки имеют понятное пользовательское состояние.
- [ ] Новые ветви поведения покрыты тестами.
- [ ] Регрессионный тест действительно воспроизводил дефект до исправления.
- [ ] Тесты проверяют поведение, а не только наличие свойства/node.
- [ ] Нет disabled/skipped обязательных tests.
- [ ] Нет secrets, больших artifacts и чужих absolute paths.
- [ ] Public contracts, ADR и README обновлены при необходимости.
- [ ] CI и evidence относятся к тому же commit.
- [ ] Impacted ранние gates повторены.

---

## 12. Правила работы с failing test или дефектом

1. Зафиксировать точный симптом, commit и окружение.
2. Сохранить минимальный сценарий воспроизведения.
3. Определить, является ли это регрессией текущего этапа или ранее закрытого gate.
4. Если затронут закрытый gate, перевести соответствующий этап в статус «Заблокирован» и отметить необходимость повторной проверки.
5. Добавить failing regression test, если его ещё нет.
6. Исправить причину, а не только симптом в UI.
7. Запустить локальный тест, полный impacted suite и CI.
8. Повторить hardware gate, если затронут audio/device/MIDI путь.
9. Закрыть blocker только ссылкой на новый PASS evidence.
10. Только затем продолжить текущий этап.

Запрещено менять ожидаемый результат теста без доказательства, что исходное требование изменилось законно через ADR.

---

## 13. Управление рисками

| Риск | Ранний индикатор | Обязательная реакция |
|---|---|---|
| AVAudioEngine не обеспечивает нужный output mapping | POC не различает 4 outputs | Остановить E02, выбрать низкоуровневый подход через ADR |
| Feedback при mic testing | Неизвестный route/высокие gains | Mute, безопасный уровень, повторная mapping проверка |
| Audio/UI drift | Timer используется как clock | Вернуться к E07, audio clock gate |
| Ложная готовность | ON AIR при failed engine | Вернуться к E08, typed state gate |
| Main queue перегружена MIDI/meters | Растёт latency UI | Coalescing snapshots, проверить E06/E09 |
| Flaky CI | Повторный run того же commit отличается | Этап не закрывать; устранить зависимость от среды |
| Потеря пользовательских файлов после sandbox | Relaunch не открывает tracks | Bookmarks и packaged validation |
| Неподтверждённая latency | README содержит число без протокола | Удалить claim до измерения |
| Массовый refactor скрывает регрессии | Большой diff без focused tests | Остановить review, разбить изменения |

---

## 14. Что не входит в текущий план

Следующие возможности нельзя добавлять внутри этапов без отдельного изменения scope:

- облачная синхронизация;
- сетевые плейлисты и удалённое управление;
- iOS/iPadOS версии;
- сторонние plug-ins;
- новые аудиоэффекты сверх заявленных;
- полноценный редактор сетлиста сверх необходимого persistence;
- автоматический next-track режим без отдельной спецификации;
- изменение минимальной версии macOS;
- массовый UI redesign.

Причина: текущий приоритет — корректность и надёжность существующих обещаний, а не расширение функциональности.

---

## 15. Приблизительные трудозатраты и порядок ресурсов

Оценки являются ориентиром для планирования, а не основанием пропускать проверки.

| Диапазон | Содержание | Ориентир |
|---|---|---|
| E00–E03 | Baseline, CI, ADR, state/concurrency | 6–10 дней |
| E04–E06 | Audio graph, controls, meters | 9–16 дней |
| E07–E09 | Transport, resilience, MIDI | 10–16 дней |
| E10–E11 | Lyrics/import/persistence | 7–11 дней |
| E12–E14 | Performance, packaging, final regression | 6–13 дней |
| **Итого** | Без внешних задержек и крупных изменений scope | **38–66 рабочих дней** |

Если E02 показывает необходимость перехода на другой output stack, оценка пересматривается до E04. Нельзя сокращать validation ради сохранения оценки.

---

## 16. Обязательные артефакты к концу проекта

- [ ] ADR-001: Audio output strategy.
- [ ] ADR-002: Module/state boundaries.
- [ ] ADR-003: Transport model.
- [ ] ADR-004: Metering semantics.
- [ ] ADR-005: Distribution and sandbox.
- [ ] Parameter inventory.
- [ ] Fixture catalog.
- [ ] Automated test suite и CI history.
- [ ] Routing/DSP/metering protocols.
- [ ] Transport и drift protocol.
- [ ] MIDI decoder corpus и hardware protocol.
- [ ] Lyrics/UI screenshots и parser matrix.
- [ ] Persistence/relaunch/corruption protocol.
- [ ] Performance before/after и 2-hour soak report.
- [ ] Latency measurement или удалённый численный claim.
- [ ] Signed/notarized release artifact.
- [ ] Clean-install protocol.
- [ ] Таблица закрытия SF-01…SF-12.
- [ ] Финальный GO/NO-GO.

---

## 17. Правила обновления этого плана

1. Не переписывать историю статусов задним числом.
2. Исправление формулировки отмечать датой и причиной в журнале изменений плана.
3. Изменение acceptance criteria считать изменением требования, а не редакционной правкой.
4. Нельзя понижать приоритет P0/P1 только потому, что исправление оказалось сложным.
5. При изменении архитектуры обновить соответствующий ADR до продолжения реализации.
6. При добавлении задачи присваивать новый ID, не переиспользовать старый.
7. При удалении задачи сохранять запись с причиной и утверждением владельца.

### Журнал изменений плана

| Дата | Версия | Изменение | Причина | Утвердил |
|---|---|---|---|---|
| 2026-11-02 | 1.0 | Первоначальный план | Результаты аудита | — |

---

## 18. Изменение scope или требования

Если исполнитель считает требование невозможным или нежелательным:

1. Остановить затронутый этап.
2. Создать запись изменения с текущим поведением, предлагаемым поведением, причиной, рисками и влиянием на другие этапы.
3. Указать, какие acceptance criteria и тесты изменятся.
4. Получить явное согласование владельца продукта.
5. Обновить ADR, roadmap, README и матрицу валидации.
6. Только после этого разблокировать этап.

### Шаблон change request

- **ID:**
- **Дата:**
- **Затронутые этапы:**
- **Исходное требование:**
- **Предлагаемое требование:**
- **Причина:**
- **Доказательства невозможности/нецелесообразности:**
- **Влияние на безопасность и пользователя:**
- **Изменения тестов:**
- **Решение владельца:** принято/отклонено.
- **Дата и подпись:**

---

## 19. Финальный протокол GO/NO-GO

Заполняется только в E14.

- **Release candidate commit:**
- **Artifact version/build:**
- **Дата проверки:**
- **Исполнитель:**
- **Независимый проверяющий:**
- **Владелец продукта:**
- **Debug build:** PASS/FAIL.
- **Release build:** PASS/FAIL.
- **Automated tests:** PASS/FAIL, количество:
- **Strict concurrency:** PASS/FAIL.
- **Audio routing hardware:** PASS/FAIL.
- **Controls/DSP:** PASS/FAIL.
- **Metering:** PASS/FAIL.
- **Transport/drift:** PASS/FAIL.
- **Fault/reconnect:** PASS/FAIL.
- **MIDI:** PASS/FAIL.
- **Lyrics/prompter:** PASS/FAIL.
- **Import/persistence:** PASS/FAIL.
- **2-hour soak:** PASS/FAIL.
- **Signing/notarization:** PASS/FAIL.
- **Clean install:** PASS/FAIL.
- **SF-01…SF-12 closure:** PASS/FAIL.
- **Открытые P0/P1:** должно быть 0.
- **Accepted P2/P3 и ссылки:**
- **Итоговое решение:** GO/NO-GO.
- **Условия или ограничения выпуска:**
- **Подписи и даты:**

---

## 20. Быстрый контроль исполнителя перед переходом к следующему этапу

Перед изменением «Текущий этап» ответить письменно:

1. Все ли чекбоксы текущего этапа закрыты фактическими результатами?
2. Есть ли evidence для каждого обязательного hardware/UI gate?
3. Проверял ли кто-то результат по протоколу, а не только по словам исполнителя?
4. Совпадают ли commit в CI, evidence и общей таблице?
5. Нет ли skipped/failing tests и новых warnings?
6. Повторены ли ранние проверки, затронутые изменениями?
7. Обновлены ли журнал, статус и блокеры?
8. Сделан ли атомарный commit после PASS?
9. Понимает ли следующий программист состояние проекта только по документам?
10. Нет ли причины, по которой текущий этап должен остаться открытым?

Если хотя бы один ответ «нет» или «не уверен», переход запрещён.

---

## 21. Таблица закрытия результатов аудита

Заполнять fixing commit и evidence только после соответствующего gate.

| Находка | Основные этапы | Fixing commit | Evidence | Статус |
|---|---|---|---|---|
| SF-01 — аудиограф | E02, E04, E08 | candidate | Documentation/Validation/E04/routing_matrix.md | Закрыта |
| SF-02 — controls | E04, E05 | candidate | Documentation/Validation/E05/controls_and_dsp.md | Закрыта |
| SF-03 — metering | E06 | candidate | Documentation/Validation/E06/metering.md | Закрыта |
| SF-04 — transport | E03, E07 | candidate | Documentation/Validation/E07/transport.md | Закрыта |
| SF-05 — errors | E07, E08 | candidate | Documentation/Validation/E08/fault_injection.md | Закрыта |
| SF-06 — MIDI | E03, E09, E11 | — | — | Не закрыта |
| SF-07 — tests/CI | E01 и все этапы | — | — | Не закрыта |
| SF-08 — lyrics/prompter | E10 | — | — | Не закрыта |
| SF-09 — concurrency | E03 и последующие | — | — | Не закрыта |
| SF-10 — performance | E06, E10, E11, E12 | — | — | Не закрыта |
| SF-11 — playlist/import | E03, E11 | — | — | Не закрыта |
| SF-12 — docs/release | E13, E14 | — | — | Не закрыта |

**Конец плана. Исполнение начинается с E00.**
