# ADR-002: Module and State Boundaries

- **Статус:** Принято (Approved)
- **Дата:** 2026-11-02
- **Автор:** AI Pair Programmer & State Architecture
- **Контекст:** Решение проблем SF-09, SF-10, SF-11; подготовка к Swift 6 strict concurrency и предотвращение рассинхронизации состояния.

---

## 1. Проблема

В исходном коде (`d48ee50`):
1. Состояние распределено между несвязанными объектами: `AppState` хранит `selectedTrack` (отдельную копию структуры `SongTrack`), а `LiveAudioEngine` независимо хранит `trackDuration`, `currentTrackTime` и `isPlaying`.
2. В audio tap closures происходит захват `self` и разделяемых мутабельных переменных (`var rms`).
3. Callback'и из CoreMIDI и CoreAudio напрямую вызывают `DispatchQueue.main.async` и мутируют `@Published` поля на каждый audio buffer (~47 раз/сек), перегружая главный поток и вызывая избыточные рендеры SwiftUI.
4. Отсутствуют строгие границы между nonisolated callback-потоками реального времени и MainActor UI-моделью.

---

## 2. Архитектурное решение

### 2.1. Единый источник истины (Single Source of Truth)
- **Плейлист:** Единственным владельцем массива треков является `SetlistStore` (или `AppState.playlist`).
- **Выбор трека:** Запрещено хранить копию структуры трека `selectedTrack: SongTrack?`. Вместо этого хранится `selectedTrackID: UUID?`. Выбранный трек всегда вычисляется на лету: `playlist.first { $0.id == selectedTrackID }`.
- **Длительность и метаданные:** Реальная длительность трека получается при импорте аудиофайла (`AVAudioFile` / `AVURLAsset`) и сохраняется непосредственно в модели `SongTrack`, обновляя сетлист по ID.

### 2.2. Разделение ответственности компонентов
1. **AudioGraphController (Audio Engine):**
   - Управляет аудиографом, узлами, маршрутизацией, канальными DSP и аудио-интерфейсами.
   - Не зависит от SwiftUI.
2. **TransportController:**
   - Конечный автомат транспорта (`stopped`, `loading`, `ready`, `playing`, `paused`, `ended`, `failed`).
   - Получает аудио-время из CoreAudio audio clock, а не из таймера.
3. **MeteringStore:**
   - Хранит атомарные snapshot'ы измерений уровней (FOH L/R, IEM L/R, Mic 1, Mic 2).
   - Ограничивает частоту публикаций в UI (Throttling / Coalescing до 25-30 Гц).
4. **MIDIManager / MIDIDecoder:**
   - Чистая функция декодирования UMP/MIDI пакетов без сайд-эффектов.
   - Хранилище пользовательских маппингов (`MIDIMappingStore`).
5. **SwiftUI Views:**
   - Пассивное отображение состояния через `@ObservedObject` / `@StateObject`. Никакой аудиологики и непосредственной работы с CoreAudio внутри Views.

### 2.3. Изоляция конкурентности (Swift 6 Concurrency)
- Все UI-facing контроллеры и observable объекты изолируются атрибутом `@MainActor`.
- Real-time callbacks CoreAudio и CoreMIDI считаются `nonisolated`.
- Из nonisolated callbacks в очередь MainActor передаются **только неизменяемые (immutable) снимки значений (Sendable value snapshots)**, например `struct MeterSnapshot: Sendable`.
- Запрещён захват мутабельного `self` или изменяемых локальных переменных внутри sendable closures.
