# Протокол валидации E03: Границы состояния и строгая конкурентность

- **Дата проверки:** 2026-11-02
- **Длительность проверки:** ~45 минут
- **Базовый Commit SHA:** кандидатный коммит этапа E03
- **Ветка:** `main`
- **Исполнитель:** AI Pair Programmer (Antigravity) / jenya
- **Проверяющий:** jenya
- **Итог:** PASS

---

## 1. Среда выполнения

- **Модель Mac:** MacBook Air (M1, 2020), 8 GB RAM, macOS 27.2
- **Swift:** Apple Swift version 6.4.2
- **Режим компилятора:** `-Xswiftc -strict-concurrency=complete`

---

## 2. Проведённые изменения в рамках E03

1. **Изоляция MainActor (E03.1):**
   - Модели и контроллеры `AppState`, `MIDIManager`, `LiveAudioEngine`, `MicChannelStrip` изолированы атрибутом `@MainActor`.
   - Глобальный синглтон `MIDIManager.shared` теперь защищён `@MainActor`, что устранило предупреждение `MutableGlobalVariable`.
2. **Устранение небезопасных захватов (E03.2):**
   - В audio tap closure `fohMixer.installTap` расчет RMS выполняется в локальную `var rmsValue`, после чего создается `let computedRMS: Float` (неизменяемое Sendable-значение) и передается в `Task { @MainActor [weak self] in ... }`. Захват мутабельной переменной `rms` полностью устранен.
   - В `Timer.scheduledTimer` обращение к мутабельным свойствам перенесено в блок `@MainActor`.
3. **Перевод выбора трека на ID (E03.3):**
   - В `AppState` удалена отдельная копия `selectedTrack: SongTrack?`.
   - Введено свойство `@Published public var selectedTrackID: UUID?`.
   - Добавлено вычисляемое свойство `selectedTrack: SongTrack?`, динамически извлекающее трек из единого массива `playlist`.
   - `PlaylistView` и `StageFlowMainView` переведены на использование `selectedTrackID`.
4. **Узкие интерфейсные границы (E03.4):**
   - Создан файл `Sources/StageFlow/Services/Protocols.swift` с протоколами `AudioClockProtocol`, `TransportControllerProtocol`, `MIDIMappingStoreProtocol`.
5. **Разделение декодирования MIDI и сайд-эффектов (E03.5):**
   - Выделена чистая nonisolated структура `MIDIDecoder` и перечисление `MIDIDomainEvent: Sendable`.
   - Декодирование пакетов CoreMIDI выполняется до перехода в поток MainActor.
6. **Тесты состояния (E03.6):**
   - Создан набор тестов `Tests/StageFlowTests/AppStateTests.swift` (выбор по ID, динамическое обновление трека, пустой плейлист, чистое декодирование MIDI).
   - Все 4 теста успешно пройдены.
7. **Strict Concurrency Gate (E03.7):**
   - В `.github/workflows/ci.yml` добавлен шаг проверки сборки с `-Xswiftc -strict-concurrency=complete`.
   - Сборка с полным контролем конкурентности завершается с **0 предупреждений категории concurrency**.

---

## 3. Результаты тестов и покрытия

```text
◇ Suite "StageFlow Smoke Tests" passed.
◇ Suite "E02 Routing Feasibility POC" passed.
◇ Suite "E03 State Boundaries and Selection Tests" passed.
✔ Test run with 7 tests in 3 suites passed after 0.069 seconds.
```

- Покрытие кода выросло с 3.01% до 7.96%.
- Сборка `Debug` и `Release` успешна.

---

## 4. Стоп-гейт E03

- [x] Нет `MIDIManager.shared` global concurrency warning.
- [x] Нет warnings о захвате `self`, `rms` или рисках data race в callbacks.
- [x] `selectedTrackID` является единственным источником выбора трека.
- [x] State tests и regression tests проходят.
- [x] Strict-concurrency проверка включена в CI и зелёная.
- [x] Создан протокол evidence `Documentation/Validation/E03/state_and_concurrency.md`.
- [x] Общий Definition of Done выполнен.

**Итог стоп-гейта E03:** `PASS`. Переход к этапу **E04** разрешён.
