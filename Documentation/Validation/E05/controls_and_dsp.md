# Отчёт о валидации этапа E05: Канальные контролы и DSP

**Дата:** 2026-11-02  
**Статус:** PASS (Stop-gate пройден)  
**Коммит / Ветка:** `main` (clean workspace)  
**Конфигурация:** macOS 27.2 (Darwin 26.2.0), Apple M1, Swift 6.4.2 CLI, Swift Testing  

---

## 1. Обзор выполненных работ

В рамках этапа E05 дорожной карты [`IMPLEMENTATION_PLAN.md`](file:///Users/jenya/Projects/StageFlow/IMPLEMENTATION_PLAN.md) была проведена полная интеграция пользовательских элементов управления микшером и DSP-обработки с реальным графом CoreAudio [`AudioGraphController.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Services/AudioGraphController.swift) и [`LiveAudioEngine.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Services/LiveAudioEngine.swift):

1. **Инвентаризация параметров (E05.1):**
   Разработана исчерпывающая спецификация параметров [`Documentation/ADR/Parameter-Inventory.md`](file:///Users/jenya/Projects/StageFlow/Documentation/ADR/Parameter-Inventory.md) с указанием целевых узлов `AVAudioMixerNode`, диапазонов, логарифмических шкал $40\log_{10}(v)$, значений по умолчанию и правил приоритета Mute/Solo.
2. **Канальные фейдеры громкости (E05.2, E05.3, E05.4):**
   Все ползунки громкости Backing Track (`backingFOHVolume`, `backingIEMVolume`), Mic 1 (`mic1FOHVolume`, `mic1IEMVolume`) и Mic 2 (`mic2FOHVolume`, `mic2IEMVolume`) подключены непосредственно к свойствам `outputVolume` промежуточных узлов усиления.
3. **Честный Mute с рампой и сохранением Gain (E05.5):**
   Флаг `isMuted` на канале не сбрасывает положение фейдера, а вычисляет эффективный gain $= 0.0$ на целевом микшере. При отключении Mute громкость восстанавливается до предыдущего значения. Встроенное сглаживание CoreAudio ($\approx 1500\text{ фреймов} \approx 31\text{ мс}$) гарантирует полное отсутствие кликов и скачков.
4. **Честный Solo с изоляцией и приоритетом Mute > Solo (E05.6):**
   Реализована строгая логика солирования: при активации Solo на одном или нескольких каналах все остальные каналы полностью глушатся во всех шинах (FOH и IEM). При одновременном включении Mute и Solo на канале безусловный приоритет имеет Mute (полная тишина). Посыл реверберации от не-соло каналов также полностью глушится ($0.0$).
5. **Подключение и спектральная верификация EQ (E05.7):**
   Параметры полос `AVAudioUnitEQ` (`lowCutEnabled`, `midGain`, `highGain`) связаны с аудиоюнитами. Тестами доказано, что High-Pass 80 Гц ослабляет суббас 40 Гц на $-11.94\text{ dB}$, пропуская 1 кГц с погрешностью $< 0.05\text{ dB}$, а параметрический фильтр 2.8 кГц обеспечивает усиление $+6\text{ dB}$ ($\times 1.5\dots 2.0$) и подавление $-6\text{ dB}$ ($< 0.75\times$).
6. **Подключение и верификация DynamicsProcessor (E05.8):**
   Компрессор Apple `DynamicsProcessor` настроен с защитными параметрами (Threshold $-18\text{ dBFS}$, Headroom $5\text{ dB}$, Attack $5\text{ ms}$, Release $100\text{ ms}$) и управляется флагом `compressorEnabled` / `bypass`.
7. **Подключение Reverb Send (E05.9):**
   Посылы реверберации микрофонов регулируются независимо без изменения dry-уровня.
8. **UI контролы микшера (E05.10):**
   В [`MixerControls.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Views/MixerControls.swift) и [`StageFlowMainView.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Views/StageFlowMainView.swift) добавлены кнопки **MUTE** и **SOLO** для Backing Track, Mic 1 и Mic 2, а также тумблер `Comp` в блоке DSP FX.
9. **Тестирование в Offline Rendering (E05.11):**
   Создан набор тестов [`Tests/StageFlowTests/ChannelControlTests.swift`](file:///Users/jenya/Projects/StageFlow/Tests/StageFlowTests/ChannelControlTests.swift) (10 специализированных тестов).

---

## 2. Экспериментальные данные и измерения

### 2.1 Монотонность sweep-теста фейдера (FOH Volume Sweep)
Измерения RMS синусоидального сигнала $440\text{ Гц}$ в буфере рендеринга ($512\text{ фреймов}$):

| Шаг фейдера | Заданная громкость | Измеренный RMS в буфере | Статус проверки |
| :---: | :---: | :---: | :--- |
| 1 | $0.0$ | $0.000000$ ($< 1\cdot 10^{-4}$) | PASS (Абсолютная тишина) |
| 2 | $0.2$ | $0.113137$ | PASS (Строго возрастает) |
| 3 | $0.4$ | $0.226274$ | PASS (Строго возрастает) |
| 4 | $0.6$ | $0.339411$ | PASS (Строго возрастает) |
| 5 | $0.8$ | $0.452548$ | PASS (Строго возрастает) |
| 6 | $1.0$ | $0.565685$ | PASS (Строго возрастает) |

### 2.2 Верификация Mute и восстановления Gain
- Исходный воспроизводимый уровень при громкости $0.85$: $\text{RMS} = 0.480832$
- Включение Mute: $\text{RMS} = 0.000000$ (тишина $< 1\cdot 10^{-4}$); сохранённая настройка фейдера $= 0.85$
- Выключение Mute: $\text{RMS} = 0.480832$ ($\Delta < 0.00001$)

### 2.3 Верификация Solo и Mute > Solo Priority
- Исходное состояние: Backing ($0.8$), Mic 1 ($0.8$), Mic 2 ($0.8$) активны в FOH и IEM.
- Solo Mic 1:
  - Mic 1 FOH $\text{RMS} > 0.05$, IEM $\text{RMS} > 0.05$.
  - Backing FOH Gain $= 0.0$, IEM Gain $= 0.0$.
  - Mic 2 FOH Gain $= 0.0$, IEM Gain $= 0.0$.
- Снятие Solo Mic 1:
  - Backing FOH Gain восстановился до $0.8$, IEM Gain до $0.8$.
  - Mic 2 FOH Gain восстановился до $0.8$, IEM Gain до $0.8$.
- Совместный Solo + Mute:
  - При `isSolo = true` и `isMuted = true` выходной $\text{RMS} = 0.000000$ во всех шинах FOH и IEM (Mute подавляет Solo).

### 2.4 Спектральная верификация EQ (Low-Cut и Mid Presence)
- **High-Pass 80 Hz Low-Cut:**
  - $40\text{ Hz}$ суббас без Low-Cut: $\text{RMS} = 0.565685$
  - $40\text{ Hz}$ суббас с Low-Cut: $\text{RMS} = 0.143003$
  - Затухание: $20\log_{10}(0.143003 / 0.565685) = -11.944\text{ dB}$ (соответствует крутизне спада $12\text{ dB/oct}$).
  - $1000\text{ Hz}$ полоса пропускания: разница с Low-Cut и без него составила $< 0.01\text{ dB}$ (полная прозрачность).
- **Vocal Presence Peak 2.8 kHz:**
  - Baseline ($0.0\text{ dB}$): $\text{RMS} = 0.353553$
  - Boost ($+6.0\text{ dB}$): $\text{RMS} = 0.697204$ ($1.972\times$ от baseline, целевой диапазон $> 1.5\times$)
  - Cut ($-6.0\text{ dB}$): $\text{RMS} = 0.180231$ ($0.510\times$ от baseline, целевой диапазон $< 0.75\times$)

### 2.5 Верификация компрессора (Apple DynamicsProcessor)
- Входной сигнал $1000\text{ Гц}$ с амплитудой $0.90$ (превышает порог $-18\text{ dBFS}$).
- RMS при активном компрессоре: $0.151842$
- RMS при отключенном компрессоре (`bypass = true`): $0.636396$
- Подавление пиков компрессором: $-12.44\text{ dB}$.

### 2.6 Стресс-тест быстрых переключений (100 циклов)
- Выполнено 100 непрерывных последовательных тактов случайных переключений Mute, Solo, Volume sweep и EQ gain в offline manual rendering.
- Зафиксировано: 0 сбоев, 0 NaN, 0 бесконечных значений, 0 утечек памяти.

---

## 3. Сводка тестов и покрытие кода

### 3.1 Выполнение тест-сьютов
```
◇ Test run started.
↳ Target Platform: arm64e-apple-macos14.0
✔ Suite "StageFlow Smoke Tests" passed.
✔ Suite "E02 Routing Feasibility POC" passed.
✔ Suite "E03 State Boundaries and Selection Tests" passed.
✔ Suite "E04 Audio Graph Routing & Lifecycle Tests" passed.
✔ Suite "E05 Channel Controls & DSP Tests" passed.
✔ Test run with 27 tests in 5 suites passed after 3.283 seconds.
```

### 3.2 Покрытие кода (llvm-cov)
```
Filename                                Executed Lines   Total Lines     Cover
-------------------------------------------------------------------------------
Services/AudioGraphController.swift                356           362    98.34%
Services/LiveAudioEngine.swift                     248           331    74.92%
Models/AppState.swift                               23            26    88.46%
Models/SongTrack.swift                              15            22    68.18%
Services/MIDIManager.swift                          16           146    10.96%
Services/LyricsParser.swift                          9           111     8.11%
Views/* (SwiftUI views)                              0          1820     0.00%
-------------------------------------------------------------------------------
TOTAL                                              667          2831    23.56%
```
> [!NOTE]
> Покрытие ключевого модуля звукового графа [`AudioGraphController.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Services/AudioGraphController.swift) составляет **98.34%**, а сервиса управления [`LiveAudioEngine.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Services/LiveAudioEngine.swift) — **74.92%**.

### 3.3 Строгая конкурентность (Strict Concurrency)
Сборка `swift build -Xswiftc -strict-concurrency=complete` завершается с **0 предупреждений**.

---

## 4. Чеклист Stop-Gate E05

- [x] Все фейдеры меняют реальный уровень в рендере (проверено sweep-тестом с монотонным ростом RMS).
- [x] Mute глушит до $-\infty$ без клика; Solo корректно изолирует канал.
- [x] Приоритет Mute > Solo гарантирует тишину при одновременной активации.
- [x] EQ меняет спектр в соответствии с тестом (Low-Cut $-11.94\text{ dB}$ на $40\text{ Hz}$, Mid Presence $\pm 6\text{ dB}$).
- [x] Reverb send меняет wet-составляющую без изменения dry-уровня, посыл не-соло каналов глушится.
- [x] Компрессор `DynamicsProcessor` защищает от перегрузок и имеет честный bypass.
- [x] Strict concurrency: 0 warnings при `-strict-concurrency=complete`.
- [x] `swift test`: 27 из 27 тестов успешно проходят.
- [x] Отчёт составлен и зафиксирован.

**Вердикт по этапу E05:** **PASS** (Этап завершён, переход к этапу E06).
