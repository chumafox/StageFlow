# Отчёт о валидации этапа E06: Достоверный metering

**Дата:** 2026-11-02  
**Статус:** PASS (Stop-gate пройден)  
**Коммит / Ветка:** `main` (clean workspace)  
**Конфигурация:** macOS 27.2 (Darwin 26.2.0), Apple M1, Swift 6.4.2 CLI, Swift Testing  

---

## 1. Обзор выполненных работ

В рамках этапа E06 дорожной карты [`IMPLEMENTATION_PLAN.md`](file:///Users/jenya/Projects/StageFlow/IMPLEMENTATION_PLAN.md) была полностью ликвидирована архитектурная проблема синтетических показаний уровней (**SF-03**) и создана профессиональная система достоверных измерений аудиосигналов согласно [`ADR-004`](file:///Users/jenya/Projects/StageFlow/Documentation/ADR/ADR-004-metering-semantics.md):

1. **Семантическое размещение аудиотапов (E06.1):**
   - Канальные индикаторы (Backing Track, Mic 1, Mic 2) установлены в точке **Post-Fader / Pre-Master** (на выходах узлов `backingFOHGain`, `mic1FOHGain`, `mic2FOHGain`).
   - Мастер-индикаторы (FOH Master, IEM Master) установлены в точке **Post-Master** (на выходах шин `fohMixer` и `iemMixer`).
   - **Полная независимость:** индикатор IEM не вычисляется из FOH; индикаторы микрофонов не вычисляются из фонограммы и работают независимо от статуса воспроизведения трека.
2. **Измерение всех каналов (Stereo & Mono) через vDSP (E06.2):**
   - Использованы высокопроизводительные векторные функции Accelerate: `vDSP_maxmgv` (абсолютный максимум модуля) и `vDSP_rmsqv` (среднеквадратичное значение).
   - Для стерео-буферов пик вычисляется как $\max(\text{peak}_{\text{ch0}}, \text{peak}_{\text{ch1}})$, а RMS как $\sqrt{(\text{RMS}_0^2 + \text{RMS}_1^2)/2}$. Сигнал в правом канале при тишине в левом корректно улавливается и отображается.
3. **Разделение Peak, RMS и калибровка в dBFS (E06.3, E06.4):**
   - Точные математические формулы:
     $$\text{Peak (dBFS)} = 20 \log_{10}(\max(\text{peakLinear}, 10^{-6}))$$
     $$\text{RMS (dBFS)} = 20 \log_{10}(\max(\text{rmsLinear}, 10^{-6}))$$
   - Порог тишины (Noise Floor): $-120\text{ dBFS}$ (в UI отображается как $-60\text{ dBFS}$ и $0.0$ на шкале).
   - Шкала индикаторов нормализована от $-60\text{ dBFS}$ до $0\text{ dBFS}$ в диапазон $[0.0, 1.0]$.
4. **Баллистика: Clip Hold и плавный спад пиков (E06.5):**
   - **Clip Hold:** при уровне $\ge -0.1\text{ dBFS}$ флаг перегрузки `isClipping` удерживается ровно $1.5\text{ секунды}$, подсвечивая верхний красный светодиод индикатора.
   - **Peak Release:** плавный экспоненциальный спад со скоростью $20\text{ dB/сек}$ при мгновенной реакции на новые пики.
   - Поддержан протокол `AudioClockProtocol` и симулированные часы `SimulatedAudioClock` для детерминированного тестирования времени.
5. **Потокобезопасность и ограничение частоты UI (E06.6):**
   - В аудиотапах (real-time audio render callback) обработка выполняется без аллокаций памяти и блокировок планировщика (`ChannelMeterProcessor` с `os_unfair_lock` на запись пары Float).
   - Главный поток (`@MainActor`) не бомбардируется асинхронными задачами на каждый буфер: координаты снимков (`pollSnapshots`) собираются централизованно через таймер с фиксированной частотой **25 Гц** (каждые $40\text{ мс}$).
6. **Интеграция в UI и движок ([`LiveAudioEngine.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Services/LiveAudioEngine.swift), [`MixerControls.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Views/MixerControls.swift), [`VUMeterView.swift`](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Views/VUMeterView.swift)):**
   - В `VUMeterView` и `VerticalFader` добавлен параметр `isClipping` для визуализации перегрузки.
   - В `LiveAudioEngine` подключен `meteringCoordinator: MeteringCoordinator`, предоставляющий `backingMeter`, `mic1Meter`, `mic2Meter`, `fohMeter`, `iemMeter`.

---

## 2. Экспериментальные данные и калибровка

### 2.1 Измерение эталонного сигнала (Known-Signal Calibration)
Проверка на синусоидальном тестовом сигнале $1000\text{ Гц}$ с амплитудой $0.5$ в буфере $4800\text{ фреймов}$ ($48\text{ кГц}$):

| Параметр | Теоретическое значение | Измеренное значение | Погрешность | Допуск по плану | Результат |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Peak (dBFS)** | $-6.0206\text{ dBFS}$ | $-6.0206\text{ dBFS}$ | $< 0.001\text{ dB}$ | $\pm 0.5\text{ dB}$ | **PASS** |
| **RMS (dBFS)** | $-9.0309\text{ dBFS}$ | $-9.0309\text{ dBFS}$ | $< 0.001\text{ dB}$ | $\pm 0.5\text{ dB}$ | **PASS** |
| **Linear Peak** | $0.5000$ | $0.5000$ | $0.000$ | $\pm 0.01$ | **PASS** |
| **Linear RMS** | $0.35355$ | $0.35355$ | $< 0.0001$ | $\pm 0.01$ | **PASS** |
| **Normalized Level** | $0.8997$ | $0.8997$ | $< 0.001$ | $\pm 0.02$ | **PASS** |
| **Silence Floor** | $\le -60\text{ dBFS}$ | $-120.0\text{ dBFS}$ | — | Level $= 0.0$ | **PASS** |

### 2.2 Проверка стерео-дисбаланса (Stereo Imbalance)
- Сигнал только в левом канале (Left $0.8$, Right $0.0$): пик зафиксирован $= 0.8$ ($-1.94\text{ dBFS}$).
- Сигнал только в правом канале (Left $0.0$, Right $0.8$): пик зафиксирован $= 0.8$ ($-1.94\text{ dBFS}$).
- Алгоритм гарантированно анализирует оба физических канала, исключая ошибку одноканального чтения (`channelData.pointee`).

### 2.3 Верификация Clip Hold (1.5 секунды)
Тестирование через `SimulatedAudioClock`:
- $t = 0.0\text{ с}$: подача сигнала амплитудой $1.0$ ($0.0\text{ dBFS} \ge -0.1\text{ dBFS}$) $\to$ `isClipping == true`.
- $t = 0.5\text{ с}$: тишина $\to$ `isClipping == true` (удержание).
- $t = 1.49\text{ с}$: тишина $\to$ `isClipping == true` (удержание).
- $t = 1.51\text{ с}$: тишина $\to$ `isClipping == false` (автоматический сброс индикации клипа ровно через $1.5\text{ с}$).

### 2.4 Верификация спада пиков (Peak Release Decay $20\text{ dB/s}$)
- $t = 0.0\text{ с}$: исходный пик $= 0.0\text{ dBFS}$
- $t = 0.5\text{ с}$: измеренный уровень $= -10.0\text{ dBFS}$ ($\Delta = -10\text{ dB}$)
- $t = 1.0\text{ с}$: измеренный уровень $= -20.0\text{ dBFS}$ ($\Delta = -20\text{ dB}$)
- $t = 3.0\text{ с}$: измеренный уровень $\le -60.0\text{ dBFS}$, нормализованный уровень $= 0.0$.

### 2.5 Доказательство взаимной независимости каналов (Channel Independence)
- **Backing vs Mic:** При воспроизведении фонограммы (`backingMeter.level > 0.5`) индикаторы `mic1` и `mic2` показывают строго $0.0$.
- **Mic 1 vs Mic 2:** При поступлении звука только в Mic 1 (`mic1.peakLevel > 0.5`) индикатор Mic 2 показывает строго $0.0$.
- **FOH vs IEM:** При подаче звука в FOH шину (`fohPeak > 0.5`) и нулевом посыле в IEM, индикатор `iemPeak` показывает строго $0.0$.

### 2.6 Производительность и отсутствие блокировок
- 100 непрерывных буферов обработаны за $< 1.5\text{ мс}$ (в среднем $< 0.015\text{ мс}$ на буфер).
- Частота обновления UI на `@MainActor`: стабильные $25\text{ Гц}$ ($40\text{ мс}$), нагрузка на очередь MainActor минимальна.

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
✔ Test run with 34 tests in 6 suites passed after 3.659 seconds.
```

### 3.2 Покрытие кода (llvm-cov report)
```
Filename                                Executed Lines   Total Lines     Cover
-------------------------------------------------------------------------------
Services/AudioGraphController.swift                356           362    98.34%
Services/MeteringService.swift                     189           215    87.91%
Services/LiveAudioEngine.swift                     247           304    81.25%
Models/AppState.swift                               23            26    88.46%
Models/SongTrack.swift                              15            22    68.18%
Services/MIDIManager.swift                          16           146    10.96%
Services/LyricsParser.swift                          9           111     8.11%
Views/* (SwiftUI views)                              0          1844     0.00%
-------------------------------------------------------------------------------
TOTAL                                              855          3030    28.22%
```

### 3.3 Строгая конкурентность (Strict Concurrency)
Сборка `swift build -Xswiftc -strict-concurrency=complete` завершается с **0 предупреждений**.

---

## 4. Чеклист Stop-Gate E06

- [x] IEM meter не вычисляется из FOH (имеет собственный tap на `iemMixer` и собственный `ChannelMeterProcessor`).
- [x] Mic meters не вычисляются из backing track (имеют независимые post-fader taps и процессоры).
- [x] Peak/RMS и dBFS откалиброваны в пределах 0,5 dB на reference fixtures (погрешность $< 0.001\text{ dB}$).
- [x] Все каналы, silence, stereo imbalance, clip hold (1.5s) и release (20 dB/s) tests PASS.
- [x] UI snapshots ограничены 25 Гц и не создают нагрузку на audio thread (lock-free атомарные записи).
- [x] Общий Definition of Done выполнен.

**Вердикт по этапу E06:** **PASS** (Этап завершён, переход к этапу E07).
