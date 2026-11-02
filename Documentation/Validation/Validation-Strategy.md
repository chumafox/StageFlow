# Стратегия валидации StageFlow (Validation Strategy)

**Версия:** 1.0  
**Дата:** 2026-11-02  
**Статус:** Утверждено  

Каждое функциональное и нефункциональное требование StageFlow имеет строго определённый метод доказательства корректности (Unit, Offline PCM Render, Hardware Test, UI Automation/Inspection). Ни одно требование не остаётся без метода подтверждения.

---

## Матрица методов валидации требований

| ID | Требование | Метод валидации | Инструмент / Тест | Критерий приёмки (PASS) |
|---|---|---|---|---|
| **REQ-01** | Независимая маршрутизация FOH (1-2) и IEM (3-4) | **Offline PCM Render** & **Hardware Loopback** | `RoutingFeasibilityTests`, Audio Interface Ch 1-4 | Сигнал FOH отсутствует в каналах 3-4 ($< -90\text{ dBFS}$); сигнал IEM отсутствует в каналах 1-2. |
| **REQ-02** | Безопасный отказ при 2-канальном выводе (Stereo Fallback) | **Unit Test** & **UI Inspection** | `RoutingFeasibilityTests`, UI Mock | IEM явно отображается как `UNAVAILABLE`; не происходит тихого подмешивания в FOH. |
| **REQ-03** | 2 независимых микрофонных входа | **Offline Audio Test** & **Hardware Mic Check** | AudioGraph Integration Test | Подача сигнала на Ch 1 не меняет уровень Ch 2 ($< -90\text{ dBFS}$). |
| **REQ-04** | Микрофонный DSP (EQ, Compressor, Reverb) | **Offline DSP Frequency Sweep** | PCM FFT Analysis / Spectrum Test | LowCut 80Hz подавляет 40Hz на $\ge 12\text{ dB}$; High Shelf 10kHz дает заданный gain $\pm 0.5\text{ dB}$. |
| **REQ-05** | Регуляторы микшера и логарифмическая шкала | **Offline Gain Step Test** | Unit / PCM Test | $Gain = 40 \log_{10}(val)$; значение $0.0$ дает абсолютную тишину; сглаживание рампом $10\text{ мс}$. |
| **REQ-06** | Приоритет Mute над Solo | **Unit & Graph Test** | MixerLogicTests | Muted-канал молчит во всех шинах, даже если включен Solo. |
| **REQ-07** | Достоверный Peak и RMS Metering в dBFS | **Known-signal Calibration Test** | MeteringTests (Sine $-6\text{ dBFS}$) | Peak $-6.02\text{ dBFS} \pm 0.5\text{ dB}$; RMS $-9.03\text{ dBFS} \pm 0.5\text{ dB}$. Раздельные показания для FOH и IEM. |
| **REQ-08** | Clip Hold и Peak Release | **Deterministic Fake Clock Test** | MeteringTimerTests | Индикатор Clip удерживается $1.5\text{ с}$; скорость спада $20\text{ dB/s}$. |
| **REQ-09** | Управление транспортом (Play/Pause/Stop/Seek) | **Transport State Machine Test** | TransportTests | Stop сбрасывает на 00:00 без demo loop; Seek планирует точный `AVAudioFramePosition`. |
| **REQ-10** | Синхронизация времени с CoreAudio Clock | **Audio Clock Drift Test** | TransportClockTests | Расхождение между audio render time и UI временем $< 10\text{ мс}$ на 30-минутном прогоне. |
| **REQ-11** | Конец файла (EOF) | **Audio File Completion Test** | TransportCompletionTests | Плеер останавливается в состоянии `ended`, не циклится; `ON AIR` гаснет. |
| **REQ-12** | Выбор трека без автозапуска | **State Selection Test** | AppStateTests | Смена `selectedTrackID` переводит в `ready`, но не запускает воспроизведение. |
| **REQ-13** | Декодирование MIDI и UMP | **Corpus Unit Test** | MIDIDecoderTests | Все words/packets корректно декодируются в структуры событий. |
| **REQ-14** | Hot-Plug и сохранение MIDI Learn | **MIDI Lifecycle Test** | MIDILearnTests | Подключение устройства обновляет список; маппинги сохраняются в `UserDefaults/JSON`. |
| **REQ-15** | Парсинг ChordPro, LRC и долей секунд | **Parser Fixture Tests** | LyricsParserTests | Метки `.5`, `.25`, `.125` парсятся в точные миллисекунды; директивы `{...}` пропускаются. |
| **REQ-16** | Подсветка активной строки суфлёра | **Prompter Dynamic Range Test** | PrompterViewModelTests | Активна строка от текущего timestamp до timestamp следующей строки. |
| **REQ-17** | Strict Concurrency (Swift 6) | **Compiler Diagnostics Gate** | `swift build -Xswiftc -strict-concurrency=complete` | 0 предупреждений категории concurrency. |
| **REQ-18** | Отсутствие утечек памяти и UI Hitch | **Instruments Profiling** | Time Profiler, Leaks | 0 утечек CoreAudio/SwiftUI; задержка UI $< 16\text{ мс}$ (60 fps). |
