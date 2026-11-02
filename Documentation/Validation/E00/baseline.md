# Протокол валидации E00: Baseline и фиксация исходного состояния

- **Дата проверки:** 2026-11-02
- **Длительность проверки:** ~30 минут
- **Базовый Commit SHA:** `d48ee50c53d06b6eb7433bece5d9ef25bf7e8220` (`d48ee50`)
- **Ветка:** `main` (или `stage/e00-baseline`)
- **Исполнитель:** AI Pair Programmer (Antigravity) / jenya
- **Проверяющий:** jenya
- **Итог:** PASS

---

## 1. Среда выполнения и версии инструментов

- **Модель Mac:** MacBook Air (M1, 2020), Model Identifier: `MacBookAir10,1`, RAM: 8 GB, Cores: 8 (4P + 4E)
- **Версия macOS:** macOS 27.2 (Darwin Kernel Version 26.2.0, Build 26B123)
- **Версия Swift:** `Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)`, Target: `arm64-apple-macosx27.2.0`
- **Версия Xcode / SDK:** Active Developer Directory `/Library/Developer/CommandLineTools` (Xcode.app не установлен в системе; сборка и тестирование выполняются через SwiftPM и Command Line Tools)

---

## 2. Аппаратный baseline (Hardware Baseline)

### Аудиоустройства (CoreAudio):
1. **MacBook Air Microphone (Built-in):**
   - Тип: Встроенный микрофон
   - Каналы ввода: 1 (моно)
   - Sample Rate: 48 000 Гц
2. **MacBook Air Speakers (Built-in):**
   - Тип: Встроенные динамики
   - Каналы вывода: 2 (стерео)
   - Sample Rate: 48 000 Гц
3. **MOTIV Mix Virtual (Shure Inc.):**
   - Тип: Virtual Audio Device
   - Вход: 2 канала, 48 000 Гц
   - Вывод: 2 канала, 48 000 Гц

### MIDI устройства:
- Физические MIDI контроллеры на момент проверки не подключены (`connectedDeviceName` = "No MIDI Devices").

### Аппаратный риск:
- **ВНИМАНИЕ (Риск для E02/E04):** В наличии локально отсутствуют физические интерфейсы с конфигурацией 2+ входа / 4 независимых выхода (для раздельного одновременного физического вывода Stereo FOH и Stereo IEM).
- **План митигации риска:**
  1. Для offline unit/integration тестов в E01–E04 используется `AVAudioEngine.renderOffline` / PCM memory buffer analysis.
  2. Для multi-channel проверки в E02/E04 будет настроен виртуальный многоканальный агрегатный интерфейс (Aggregate Device / Multi-Output / BlackHole 4ch/16ch) либо подключён внешний многоканальный интерфейс / удалённый стенд.

---

## 3. Reference Configuration

- **Sample Rate:** 48 000 Гц (48 kHz)
- **Buffer Size:** 256 frames (~5.33 ms) / 512 frames (~10.67 ms)
- **Входы:**
  - Mic 1 (Lead Vocal): Mono Input (Channel 1)
  - Mic 2 (Backing Vocal): Mono Input (Channel 2)
  - Backing Track: Stereo Virtual/File Stream (Left/Right)
- **Выходы:**
  - FOH Master (Speakers): Physical Output Channels 1 & 2 (Stereo)
  - IEM Master (In-Ear Monitor): Physical Output Channels 3 & 4 (Stereo)

---

## 4. Утверждённые сценарии использования (Use Cases)

1. **UC-01 (Импорт сетлиста):** Добавление одного или нескольких аудиофайлов (MP3, WAV, M4A, AIFF), парсинг встроенных/внешних тегов lyrics/chords/LRC без зависания UI, отображение в сетлисте с корректной длительностью.
2. **UC-02 (Выбор трека без автозапуска):** Клик по треку в сетлисте загружает аудио и текст суфлёра, но **не** запускает автовоспроизведение; плеер остаётся в состоянии готовности/паузы.
3. **UC-03 (Управление транспортом):** Play, Pause, Stop, Seek по таймлайну. При Stop сбрасывается позиция на 00:00, отменяется воспроизведение, при повторном Play играет выбранный трек с начала (никаких demo buffers).
4. **UC-04 (Окончание трека - EOF):** По достижении конца трека воспроизведение корректно останавливается (`ended`/`stopped`), UI переходит в остановленное состояние, не происходит зацикливания или рассинхрона времени.
5. **UC-05 (Микрофонный DSP тракт):** Два микрофонных входа с независимым 3-полосным EQ (LowCut 80Hz, Mid Presence 2.8kHz, High Air 10kHz), динамическим процессором (DynamicsProcessor) и регулируемым Reverb Send.
6. **UC-06 (Независимая FOH / IEM маршрутизация):**
   - Изменение фейдера FOH канала (Backing, Mic 1, Mic 2) влияет только на FOH микс (Channels 1-2).
   - Изменение фейдера IEM канала влияет только на IEM мониторы (Channels 3-4).
   - FOH Master регулирует общую громкость зала, IEM Master регулирует общую громкость мониторов.
7. **UC-07 (MIDI управление и Hot-Plug):**
   - Подключение MIDI педали/контроллера во время работы приложения (hot-plug) автоматически распознается.
   - Поддерживаются команды Control Change (CC) и Note On (для управления Play/Pause и громкостью).
   - Поддерживается MIDI Learn с сохранением маппингов.
8. **UC-08 (Отказоустойчивость при смене аудиоустройств):**
   - Отключение или переключение аудиоинтерфейса не приводит к крэшу; движок безопасно останавливается или переподключается с выводом понятного сообщения пользователю.

---

## 5. Воспроизведение сборки и тестов

### 5.1. Debug Build (`swift build`)
- **Команда:** `cd /Users/jenya/Projects/StageFlow && swift build`
- **Результат:** `Build complete! (27.41 sec)`, exit code `0`.
- **Предупреждения:**
  - `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/usr/lib' not found`
  - `ld: warning: search path '/Library/Developer/CommandLineTools/Developer/Library/Frameworks' not found`
  *(Предупреждения linker вызваны особенностями путей Command Line Tools и не являются дефектами кода).*

### 5.2. Release Build (`swift build -c release`)
- **Команда:** `cd /Users/jenya/Projects/StageFlow && swift build -c release`
- **Результат:** `Build complete! (29.06 sec)`, exit code `0`.
- **Предупреждения:**
  - `Sources/StageFlow/Services/LyricsParser.swift:10:27: warning: 'metadata' was deprecated in macOS 13.0: Use load(.metadata) instead`
  - `Sources/StageFlow/Services/LyricsParser.swift:15:32: warning: 'stringValue' was deprecated in macOS 13.0: Use load(.stringValue) instead`
  - Linker search path warnings (аналогично Debug).

### 5.3. Test Target (`swift test`)
- **Команда:** `cd /Users/jenya/Projects/StageFlow && swift test`
- **Результат:** Exit code `1`: `error: no tests found; create a target in the 'Tests' directory`.
- **Оценка:** Ожидаемый результат в рамках E00; подтверждает находку SF-07 из `AUDIT.md`. Тестовый контур будет создан в этапе E01.

---

## 6. Сопоставление находок аудита SF-01...SF-12 с этапами реализации

| ID | Описание | Закрывающий этап(ы) |
|---|---|---|
| **SF-01** | Аудиограф не реализует микрофонный тракт, IEM и reverb | **E02, E04, E08** |
| **SF-02** | Регуляторы микшера не связаны с аудиопараметрами | **E04, E05** |
| **SF-03** | VU-индикаторы уровня недостоверны (фейковые значения) | **E06** |
| **SF-04** | Транспорт и позиция воспроизведения некорректны (seek, stop, loop) | **E03, E07** |
| **SF-05** | Ошибки движка и загрузки не доходят до UI | **E07, E08** |
| **SF-06** | MIDI реализован частично (нет hot-plug, сохранения learn) | **E03, E09, E11** |
| **SF-07** | Тесты и CI отсутствуют | **E01 (и все последующие)** |
| **SF-08** | Ошибки парсинга текстов, аккордов и подсветки строк | **E10** |
| **SF-09** | Конкурентность и совместимость со Swift 6 | **E03 (и постоянный CI gate)** |
| **SF-10** | Риски лишней нагрузки на главный поток и UI | **E06, E10, E11, E12** |
| **SF-11** | Несогласованность модели плейлиста и отсутствие persistence | **E03, E11** |
| **SF-12** | Документация (README) и готовность к релизу | **E13, E14** |

Каждая находка строго привязана к конкретным этапам плана. Ни одна не потеряна.

---

## 7. Заключение по этапу E00

Все условия Stop Gate E00 выполнены:
1. Исходное состояние зафиксировано (commit `d48ee50`, branch `main`, версии ОС и Swift).
2. Обязательный контекст (`README.md`, `AUDIT.md`, `Package.swift`, все 11 файлов исходников) прочитан и проанализирован.
3. Сборка (Debug/Release) воспроизведена с сохранением вывода и warnings; отсутствие тестов зафиксировано.
4. Hardware baseline зафиксирован, риски отсутствия 4-канального физического интерфейса выявлены и внесены в журнал рисков.
5. Пользовательские сценарии (UC-01..UC-08) и Reference Configuration утверждены.
6. Роли назначены, журналы выполнения и блокеров инициализированы.

**Итог стоп-гейта E00:** `PASS`. Переход к этапу **E01** разрешён.
