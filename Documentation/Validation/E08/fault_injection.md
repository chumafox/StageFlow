# Отчёт о валидации этапа E08: Ошибки, lifecycle и отказоустойчивость

**Дата:** 2026-11-02  
**Статус:** PASS (Stop-gate пройден)  
**Коммит / Ветка:** `main` (clean workspace)  
**Конфигурация:** macOS 27.2 (Darwin 26.2.0), Apple M1, Swift 6.4.2 CLI, Swift Testing  

---

## 1. Обзор выполненных работ

В рамках этапа E08 дорожной карты [`IMPLEMENTATION_PLAN.md`](file:///Users/jenya/Projects/StageFlow/IMPLEMENTATION_PLAN.md) была полностью устранена проблема маскировки системных сбоев (**SF-05**) и реализована всесторонняя отказоустойчивость приложения:

1. **Типизированные ошибки (E08.1 / [`Errors.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Services/Errors.swift)):**
   - Введено строгое перечисление `StageFlowError: Error, LocalizedError, Equatable, Sendable`:
     - `.unsupportedFileType(String)`
     - `.corruptFile(String)`
     - `.missingFile(String)`
     - `.permissionDenied(String)`
     - `.metadataFailure(String)`
     - `.engineStartFailure(String)`
     - `.unavailableRoute(String)`
     - `.midiInitializationFailure(String)`
     - `.deviceDisconnected(String)`
2. **Искоренение скрытых `try?` (E08.2 / [`LyricsParser.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Services/LyricsParser.swift)):**
   - Все неявные `try?` на критических путях чтения файлов и компиляции регулярных выражений устранены.
   - Регулярные выражения для временных меток и аккордов скомпилированы статически в `timeRegex` и `chordRegex`.
   - Чтение LRC/TXT переведено на проверку существования файла и блок `do { try ... } catch` с информативным логированием.
3. **Видимый жизненный цикл аудиодвижка (E08.3):**
   - Реализован автомат состояний `EngineLifecycleState`: `.starting`, `.ready`, `.running`, `.degraded(reason)`, `.stopped`, `.failed(StageFlowError)`.
   - **Строгая гарантия `ON AIR`:** свойство `audio.isOnAir` возвращает `true` **только** тогда, когда аудиодвижок реально работает (`running` или активный `degraded`) И транспорт находится в состоянии `playing`.
   - В UI индикатор ON AIR принимает состояния: Зелёный (ON AIR), Оранжевый (PAUSED / READY), Жёлтый (DEGRADED), Синий (STARTING), Серый (STOPPED), Красный (ENGINE FAILED).
4. **Блокировка недопустимых действий (E08.4):**
   - Метод `play()` в `LiveAudioEngine` и `TransportController` аппаратно блокируется при сбое движка (`failed`), остановленном движке (`stopped`) или повреждённом/отсутствующем источнике (`failed`). Попытка запуска не переводит UI в ON AIR и протоколируется в диагностический лог.
5. **Обработка изменений конфигурации CoreAudio (E08.5):**
   - Добавлен слушатель уведомления `AVAudioEngineConfigurationChange`.
   - При смене аудиомаршрута воспроизведение безопасно приостанавливается, динамические узлы графа перекоммутируются (`graphController.reconfigure()`), а аудиотапы корректно переустанавливаются через `meteringCoordinator.installTaps(on: graphController)` без дублирования.
   - Стресс-тест из 20 последовательных переключений маршрута Quad $\leftrightarrow$ Stereo fallback подтвердил отсутствие утечек памяти и падений.
6. **Политика доступа к микрофону (E08.6):**
   - Выделен протокол `MicrophonePermissionProviding` и реализации `SystemMicrophonePermissionProvider` и `FakeMicrophonePermissionProvider`.
   - При отказе в доступе к микрофону приложение **не падает** и **не симулирует LIVE**: входы заглушаются на уровне регуляторов (`mic1InputNode.outputVolume = 0.0`), движок переходит в режим `.degraded("Microphone permission denied")`, а фонограмма Backing Track продолжает штатно воспроизводиться.
   - Предоставление доступа через `requestMicrophonePermission()` восстанавливает уровень входов до 1.0 и переводит движок в `.running`.
7. **Панель диагностики и журнал событий (E08.7 / [`DiagnosticsView.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Views/DiagnosticsView.swift)):**
   - Добавлена модель `DiagnosticsReport` и вкладка «Diagnostics 🩺» в левой панели UI (tag 2), а также быстрый переход по нажатию на плашку статуса в верхней панели.
   - Отображаются: статус движка, режим маршрутизации (Quad vs Stereo fallback), количество каналов, sample rate, разрешения микрофона, состояние MIDI и хронологический список последних ошибок.
8. **Пакет fault-injection тестов (E08.8 / [`FaultInjectionTests.swift`](file:///Users/jenya/Projects/StageFlow/Tests/StageFlowTests/FaultInjectionTests.swift)):**
   - Добавлено 9 специализированных тестов, эмулирующих отказы ввода/вывода, отсутствующие/битые файлы, отказы запуска движка, сбои MIDI и циклы смены маршрутов.

---

## 2. Экспериментальные данные и верификация отказов

| Тест / Сценарий | Входные данные | Ожидаемый результат | Фактический результат | Статус |
| :--- | :--- | :--- | :--- | :-: |
| **Missing File (E08.1/4)** | Несуществующий URL `file:///non_existent_file.wav` | Ошибка `.missingFile`, `play()` блокирован, `isOnAir == false`. | Зафиксирован `StageFlowError.missingFile`, ON AIR не загорелся, ошибка в диагностике. | **PASS** |
| **Corrupted File (E08.1/4)** | WAV с повреждёнными чанками заголовка | Ошибка `.corruptFile`, `play()` блокирован, `isOnAir == false`. | Зафиксирован `StageFlowError.corruptFile`, плеер остановлен, ON AIR не включен. | **PASS** |
| **Truncated File (E08.1/4)** | Файл размером 8 байт | Ошибка чтения формата, `play()` блокирован. | Корректный перехват ошибки CoreAudio, состояние `.failed`. | **PASS** |
| **Unsupported File (E08.1/4)** | Текстовый файл с расширением `.wav` | Ошибка формата, отсутствие аварийного завершения. | Ошибка отловлена типизированно, приложение устойчиво. | **PASS** |
| **Engine Start Failure (E08.3/4)** | Имитация отказа HAL устройства | Состояние `.failed(engineStartFailure)`, Play блокирован. | `isOnAir == false`, вызовы `play()` отброшены с записью в лог. | **PASS** |
| **Mic Permission Denied (E08.6)** | Разрешение `denied` | Режим `.degraded`, входы заглушены, backing работает. | Входы установлены в `0.0`, статус `DEGRADED`, backing воспроизводится. | **PASS** |
| **Mic Permission Grant (E08.6)** | Переход `denied` $\to$ `authorized` | Восстановление входов до 1.0, режим `.running`. | Входы восстановлены в `1.0`, статус `RUNNING`, отчёт обновлён. | **PASS** |
| **20 Route Changes (E08.5)** | 20 последовательных переключений Quad $\leftrightarrow$ Stereo | 0 аварий, отсутствие дублированных taps, корректный mapping. | Все 20 циклов завершены успешно, перекоммутация стабильна. | **PASS** |
| **Diagnostics Accuracy (E08.7)** | Проверка отчёта в реальном времени | Точные значения каналов, sample rate, статусов. | Все поля `DiagnosticsReport` совпадают с аппаратным состоянием. | **PASS** |
| **MIDI Failure Capture (E08.1)** | Сбой `MIDIClientCreateWithBlock` | Ошибка `.midiInitializationFailure`, UI показывает статус. | Типизированная ошибка зафиксирована, краш отсутствует. | **PASS** |

---

## 3. Сводка тестов и покрытие кода

### 3.1 Результаты выполнения тестов
```
◇ Test run started.
↳ Target Platform: arm64e-apple-macos14.0
✔ Suite "StageFlow Smoke Tests" passed.
✔ Suite "E02 Routing Feasibility POC" passed.
✔ Suite "E03 State Boundaries and Selection Tests" passed.
✔ Suite "E04 Audio Graph Routing & Lifecycle Tests" passed.
✔ Suite "E05 Channel Controls & DSP Tests" passed.
✔ Suite "E06 Metering & VU Calibration Tests" passed.
✔ Suite "E07 Transport Controller & Audio Clock Tests" passed.
✔ Suite "E08 Fault Injection & Lifecycle Reliability Tests" passed.
✔ Test run with 55 tests in 8 suites passed after 7.572 seconds.
```

### 3.2 Покрытие кода ключевых модулей (llvm-cov report)
```
Filename                                Executed Lines   Total Lines     Cover
--------------------------------------------------------------------------------
Services/AudioGraphController.swift                424           434    97.70%
Services/LiveAudioEngine.swift                     391           453    86.31%
Services/MeteringService.swift                     197           215    91.63%
Services/TransportController.swift                 276           343    80.47%
Services/Errors.swift                               61            88    69.32%
Models/AppState.swift                               23            26    88.46%
Models/SongTrack.swift                              15            22    68.18%
```

### 3.3 Проверка Swift 6 Strict Concurrency
```bash
swift build -Xswiftc -strict-concurrency=complete
# Результат: Build complete! 0 warnings, 0 errors.
```

---

## 4. Вывод
Все требования этапа **E08** выполнены в полном объёме:
1. Архитектурный дефект **SF-05** полностью устранён.
2. Введена типизированная модель ошибок `StageFlowError` и строгий жизненный цикл `EngineLifecycleState`.
3. Запрещён ложный `ON AIR` в любых сценариях сбоев.
4. Отказы файлов, устройств, разрешений и MIDI детерминированно отображаются в UI и логе диагностики.
5. Stop-gate этапа E08 пройден. Разрешён переход к этапу **E09** (MIDI decoding, mappings и hot-plug).
