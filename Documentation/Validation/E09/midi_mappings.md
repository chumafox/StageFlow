# Отчёт о валидации этапа E09: MIDI decoding, mappings и hot-plug

**Дата:** 2026-11-02  
**Статус:** PASS (Stop-gate пройден)  
**Коммит / Ветка:** `main`  
**Конфигурация:** macOS 27.2 (Darwin 26.2.0), Apple M1, Swift 6.4.2 CLI, Swift Testing  

---

## 1. Обзор выполненных работ

В рамках этапа E09 дорожной карты [`IMPLEMENTATION_PLAN.md`](file:///Users/alexnovak/проекты/StageFlow/IMPLEMENTATION_PLAN.md) была полностью решена проблема непредсказуемой обработки MIDI-событий, потери пакетов и случайных запусков воспроизведения (**SF-06**):

1. **Изолированный UMP / MIDI-декодер (E09.1 / [`MIDIManager.swift`](file:///Users/alexnovak/проекты/StageFlow/Sources/StageFlow/Services/MIDIManager.swift)):**
   - Выделена чистая структура `MIDIDecoder`, поддерживающая декодирование 32-битных слов UMP (Universal MIDI Packet) по спецификации MIDI 2.0 / CoreMIDI 1.0 protocol (`._1_0`).
   - Устранено чтение только первого слова `packet.words.0`: реализован последовательный проход по всем `wordCount` словам внутри `MIDIEventPacket` и обход всех пакетов `MIDIEventList` через `MIDIEventPacketNext`.
   - Поддерживаются типы сообщений: Control Change (0xB0), Note On (0x90), Note Off (0x80), Program Change (0xC0), Pitch Bend (0xE0) и безопасная классификация неизвестных / утилитных пакетов (`.other`).
2. **Преобразование Note On velocity 0 в Note Off (E09.2 / E09.4):**
   - Сообщения `Note On` с `velocity == 0` по стандарту MIDI строго декодируются как `.noteOff(channel:note:velocity:0)`.
3. **Строгая семантика нот и педалей (E09.4):**
   - **Устранена критическая ошибка SF-06:** неназначенные ноты больше **никогда** не вызывают Play/Pause или смену состояний транспорта. Любая игра на MIDI-клавиатуре без явного маппинга полностью безопасна для живого выступления.
   - Одно физическое нажатие назначенной ноты создаёт ровно одно действие.
4. **Пороговое переключение педали сустейна (E09.5):**
   - Для педали сустейна (CC 64) установлен стандартный порог срабатывания: $\text{value} \ge 64$.
   - Реализовано определение фронта перехода (rising edge): триггер Play/Pause срабатывает **только один раз** в момент нажатия ($< 64 \to \ge 64$). Непрерывный поток значений $\ge 64$ (например, 64, 65, 80, 127) больше не вызывает хаотичных повторных переключений. Отпускание педали ($< 64$) безопасно сбрасывает внутренний флаг готовности.
5. **Полноценная система маппингов и Learning (E09.3 / E09.6 / [`MIDIMappingStore.swift`](file:///Users/alexnovak/проекты/StageFlow/Sources/StageFlow/Services/MIDIMappingStore.swift)):**
   - Создана модель `MIDIMapping`, связывающая триггер `MIDITrigger` (`.controlChange(channel:cc:)` или `.note(channel:note:)`) с целевым действием `MIDITarget`.
   - Внедрён класс `MIDIMappingStore` с автоматическим сохранением и восстановлением пользовательских назначений в `UserDefaults` в формате JSON.
   - При входе в режим `startLearning(target:)` первое пришедшее событие (CC или Note) формирует правило, немедленно сохраняет его на диск, подтверждает в UI (`lastLearnedMapping`) и применяет ко всем последующим входящим событиям.
6. **Приоритет пользовательских назначений (E09.7):**
   - Пользовательский маппинг имеет строгий приоритет над стандартными заводскими пресетами. Если пользователь переназначает CC 7 на громкость микрофона 1, стандартное управление FOH Master для этого канала отключается.
   - Заводские пресеты по умолчанию:
     - CC 7 (Omni) $\to$ `masterFOH`
     - CC 1 (Omni) $\to$ `reverb`
     - CC 64 (Omni) $\to$ `playPause`
7. **Подключение навигации по сетлисту (E09.8):**
   - Действия `nextTrack` и `previousTrack` подключены к методам `appState.selectNextTrack()` и `appState.selectPreviousTrack()`, обеспечивая мгновенное переключение песен с контроллера или футсвитча.
8. **Горячее подключение (Hot-Plug) и контроль ошибок (E09.9 / E09.10):**
   - Блок уведомлений CoreMIDI отслеживает события `.msgSetupChanged`, `.msgObjectAdded`, `.msgObjectRemoved`, динамически переподключая доступные источники и обновляя список `connectedDevices`.
   - Все системные вызовы CoreMIDI проверяются на `OSStatus`. При сбое ошибка типизируется в `StageFlowError.midiInitializationFailure` и транслируется в панель диагностики [`DiagnosticsView`](file:///Users/alexnovak/проекты/StageFlow/Sources/StageFlow/Views/DiagnosticsView.swift).
9. **Защита очереди UI и Coalescing (E09.11):**
   - Регуляторы аудиодвижка обновляются синхронно в реальном времени с нулевой задержкой.
   - Для UI индикации (`lastReceivedCC`) применен 30 Гц троттлинг/коалесцинг, предотвращающий лаги и перегрузку главного потока даже при шторме из 1 000+ CC-событий в секунду.

---

## 2. Результаты тестирования (Suite E09)

В файл [`Tests/StageFlowTests/MIDITests.swift`](file:///Users/alexnovak/проекты/StageFlow/Tests/StageFlowTests/MIDITests.swift) включено 15 специализированных тестов:

| Тест / Сценарий | Входные данные | Ожидаемый результат | Статус |
| :--- | :--- | :--- | :-: |
| **Decode CC (E09.1/2)** | UMP слово `0x20B00764` (Ch 0, CC 7, Val 100) | Разобран `.controlChange(channel: 0, cc: 7, value: 100)` | **PASS** |
| **Decode Note On (E09.1/2)** | UMP слово `0x20903C50` (Ch 0, Note 60, Vel 80) | Разобран `.noteOn(channel: 0, note: 60, velocity: 80)` | **PASS** |
| **Note On Vel 0 $\to$ Off (E09.2/4)** | UMP слово `0x20903C00` (Ch 0, Note 60, Vel 0) | Строго преобразован в `.noteOff(channel: 0, note: 60, velocity: 0)` | **PASS** |
| **Decode Note Off (E09.1/2)** | UMP слово `0x20824040` (Ch 2, Note 64, Vel 64) | Разобран `.noteOff(channel: 2, note: 64, velocity: 64)` | **PASS** |
| **PC & Pitch Bend (E09.1/2)** | `0x20C00500`, `0x20E00040` | Разобраны `.programChange(0, 5)` и `.pitchBend(0, 8192)` | **PASS** |
| **Multi-Word Packet (E09.1)** | Пакет из 3 UMP слов (CC 7, CC 1, Note 60) | Все 3 события успешно извлечены без потерь | **PASS** |
| **Malformed Words (E09.2)** | MT=0 (Utility), MT=4 (MIDI 2.0 64-bit) | Корректный шаг смещения, отсутствие сбоев, `.other` | **PASS** |
| **Unmapped Notes (E09.4/SF-06)** | 10 случайных нот на разных каналах | `onPlayPauseTrigger` вызван ровно 0 раз | **PASS** |
| **Mapped Note (E09.4)** | Назначенная нота 60 | Вызов действия ровно 1 раз, Note Off не триггерит повторно | **PASS** |
| **Sustain Threshold (E09.5)** | Значения 0, 30, 63, 64, 65, 100, 127 | Ровно 1 триггер на фронте $\ge 64$, отсутствие повторов | **PASS** |
| **Learning & Store (E09.6)** | `startLearning(.backingVolume)`, CC 25 | Маппинг сохранён, восстановлен после рестарта, управляет Backing | **PASS** |
| **User Precedence (E09.7)** | Пользовательский маппинг CC 7 $\to$ Mic 1 | CC 7 управляет Mic 1, а не дефолтным FOH | **PASS** |
| **Setlist Actions (E09.8)** | Триггеры `nextTrack` и `previousTrack` | Переключение треков в `AppState` вперёд и назад | **PASS** |
| **Hot-Plug Cycles (E09.9)** | 20 последовательных циклов смены устройств | Обновление списка устройств без падений и утечек | **PASS** |
| **CC Burst 1,000 (E09.11)** | 1 000 CC сообщений в плотном цикле | 1 000 аудио-обновлений, отсутствие зависания UI, финальный CC 104 | **PASS** |

---

## 3. Итоговый статус регрессионного тестирования

- **Всего тестов в проекте:** 70 тестов в 9 тестовых наборах (`E02`–`E09`, `SmokeTests`).
- **Результат:** 70 passed, 0 failed, 0 skipped.
- **Strict Concurrency (Swift 6):** 0 warnings.
- **Стоп-гейт E09:** Полностью пройден (**PASS**).
