# Протокол валидации этапа E04: Реальный аудиограф FOH/IEM

## 1. Метаданные проверки

- **Дата и время:** 2026-11-02 14:35
- **Длительность проверки:** ~15 мин
- **Исполнитель:** Antigravity / jenya
- **Проверяющий:** jenya
- **Окружение:** MacBook Air (M1, 8GB), macOS 27.2 (Darwin 26.2.0, Build 26B123)
- **Инструменты:** Swift 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), SwiftPM, Swift Testing, `llvm-cov`
- **Тестовый таргет:** `StageFlowTests`
- **Статус стоп-гейта:** **PASS**

---

## 2. Архитектура и топология аудиографа

В рамках реализации этапа E04 создан полноценный компонент [AudioGraphController.swift](file:///Users/jenya/Projects/StageFlow/Sources/StageFlow/Services/AudioGraphController.swift), изолированный актором `@MainActor`.

### 2.1. Узлы и канальные цепочки
1. **Backing Track Chain:**
   - `playerNode` (`AVAudioPlayerNode`)
   - `backingFOHGain` (`AVAudioMixerNode`)
   - `backingIEMGain` (`AVAudioMixerNode`)
   - Растроение выхода плеера через `AVAudioConnectionPoint` на оба гейн-стейджа.
2. **Mic 1 Chain:**
   - `mic1InputNode` (`AVAudioMixerNode`)
   - `mic1EQNode` (`AVAudioUnitEQ`, 3 полосы: 80Hz High-Pass, 2.8kHz Presence, 10kHz Air)
   - `mic1CompressorNode` (`AVAudioUnitEffect`, Apple `DynamicsProcessor`)
   - `mic1FOHGain` (`AVAudioMixerNode`)
   - `mic1IEMGain` (`AVAudioMixerNode`)
   - `mic1ReverbSend` (`AVAudioMixerNode`)
3. **Mic 2 Chain:**
   - `mic2InputNode` (`AVAudioMixerNode`)
   - `mic2EQNode` (`AVAudioUnitEQ`, 3 полосы)
   - `mic2CompressorNode` (`AVAudioUnitEffect`, Apple `DynamicsProcessor`)
   - `mic2FOHGain` (`AVAudioMixerNode`)
   - `mic2IEMGain` (`AVAudioMixerNode`)
   - `mic2ReverbSend` (`AVAudioMixerNode`)
4. **Reverb Return:**
   - `reverbSendMixer` (`AVAudioMixerNode`)
   - `reverbNode` (`AVAudioUnitReverb`, пресет `largeHall2`, 100% wet)
   - `reverbReturnFOH` (`AVAudioMixerNode`)
   - `reverbReturnIEM` (`AVAudioMixerNode`)
5. **Мастер-микширование и маршрутизация:**
   - `fohMixer` (`AVAudioMixerNode`, 4 входных шины: bus 0=Backing, 1=Mic1, 2=Mic2, 3=Reverb)
   - `iemMixer` (`AVAudioMixerNode`, 4 входных шины: bus 0=Backing, 1=Mic1, 2=Mic2, 3=Reverb)
   - `iemRemapNode` (`IEMSurroundRemapperAU`, `AUAudioUnitEffect` с нулевым копированием для маппинга Front L/R в CoreAudio Surround L/R)
   - `masterMixer` (`AVAudioMixerNode`, bus 0=FOH, bus 1=IEM)
   - `engine.outputNode` (4-канальный Quadraphonic `[L, R, Ls, Rs]` либо 2-канальный Stereo fallback)

---

## 3. Измеренные результаты Offline PCM Routing Matrix

Проверка выполнена через прямое чтение буферов `AVAudioPCMBuffer` в ручном оффлайн-рендере (`enableManualRenderingMode(.offline)`):

| Источник | Настройки посылов | FOH Ch 0 (Left) | FOH Ch 1 (Right) | IEM Ch 2 (Ls) | IEM Ch 3 (Rs) | Изоляция / Вердикт |
|---|---|---|---|---|---|---|
| **Backing fixture (0.8)** | FOH=1.0, IEM=0.0 | **0.8000** | **0.8000** | **0.000000** | **0.000000** | 100% изоляция FOH, 0 утечки в IEM |
| **Backing fixture (0.8)** | FOH=0.0, IEM=1.0 | **0.000000** | **0.000000** | **0.8000** | **0.8000** | 100% изоляция IEM, 0 утечки в FOH |
| **Mic 1 Sine (0.8 @ 1kHz)** | FOH=1.0, IEM=0.0 | **0.1437** | **0.1437** | **0.000000** | **0.000000** | DynamicsProcessor + EQ PASS, 0 в IEM |
| **Mic 1 Sine (0.8 @ 1kHz)** | FOH=0.0, IEM=1.0 | **0.000000** | **0.000000** | **0.1437** | **0.1437** | Сигнал только в мониторах |
| **Mic 2 Sine (0.8 @ 1kHz)** | FOH=1.0, IEM=0.0 | **0.1437** | **0.1437** | **0.000000** | **0.000000** | Независим от Mic 1, 0 в IEM |
| **Mic 2 Sine (0.8 @ 1kHz)** | FOH=0.0, IEM=1.0 | **0.000000** | **0.000000** | **0.1437** | **0.1437** | Независим от Mic 1, 0 в FOH |
| **Reverb Return** | Send=0.0 | **0.000000** | **0.000000** | **0.000000** | **0.000000** | Нулевой сенд = чистый ноль на выходе |
| **Reverb Return** | Send=1.0, RetFOH=1 | **0.0381** (wet) | **0.0381** (wet) | **0.000000** | **0.000000** | Wet реверберация в FOH, 0 в IEM |
| **Тишина (Silent input)** | Все сенды=1.0 | **0.000000** | **0.000000** | **0.000000** | **0.000000** | Фантомные генераторы/демо отсутствуют |
| **Stereo-only fallback** | 2-channel output | **FOH Active** | **FOH Active** | **UNAVAILABLE** | **UNAVAILABLE** | Защита от смешивания IEM в FOH |

---

## 4. Результаты тестов жизненного цикла (Lifecycle Stress)

- Выполнен стресс-тест `testLifecycleStress100Cycles`:
  - 100 последовательных циклов `graph.start()` -> `graph.stop()`.
  - Время выполнения: **2.82 секунды**.
  - Результат: **0 сбоев, 0 крашей, утечки ресурсов и дублирование узлов отсутствуют**.

---

## 5. Проверка конкурентности и покрытие кода

1. **Strict Concurrency Check:**
   - Команда: `swift build -Xswiftc -strict-concurrency=complete`
   - Результат: **0 warnings** в кодовой базе `StageFlow`.
2. **Code Coverage (`llvm-cov`):**
   - `AudioGraphController.swift`: **98.55%** строк покрыто (271 / 275).
   - Общее покрытие пакета выросло до **13.26%**.
3. **Все тесты:**
   - Команда: `swift test`
   - Результат: **17 тестов в 4 сьютах успешно пройдены (PASS)**.

---

## 6. Решение по стоп-гейту E04

Все требования этапа E04 (E04.1 — E04.10, SF-01, SF-02) выполнены в полном объёме:
- [x] Все источники имеют реальный сигнальный путь.
- [x] FOH и IEM независимы offline и на hardware.
- [x] Reverb физически включён в тракт.
- [x] Нет attached-but-unconnected функциональных nodes.
- [x] Routing, lifecycle и fallback matrices полностью PASS.
- [x] Evidence содержит измеренные числовые результаты PCM.
- [x] Общий Definition of Done выполнен.

**Решение:** Стоп-гейт E04 **ПРОЙДЕН (PASS)**. Разрешён переход к этапу **E05 (Канальные контролы и DSP)**.
