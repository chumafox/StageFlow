# Инвентаризация параметров управления аудиографом (Parameter Inventory)

**Версия:** 1.0  
**Дата:** 2026-11-02  
**Статус:** Утверждено  
**Контекст:** Реализация этапа E05 (Канальные контролы и DSP) дорожной карты `IMPLEMENTATION_PLAN.md`.

---

## 1. Сводная таблица параметров

| Идентификатор параметра | Канал / Секция | UI Контрол | Target Node / CoreAudio свойство | UI Диапазон | Аудио Диапазон | Шкала / Taper | Значение по умолчанию |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `backing.fohVolume` | Backing Track | Vertical Fader | `backingFOHGain.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ (Линейный gain) | $40\log_{10}(v)$ dB | $0.85$ (-2.8 dB) |
| `backing.iemVolume` | Backing Track | Vertical Fader | `backingIEMGain.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | $40\log_{10}(v)$ dB | $0.70$ (-6.2 dB) |
| `backing.isMuted` | Backing Track | Toggle Button | `backingFOHGain` & `backingIEMGain` effective gain | `false` / `true` | $0.0$ (Muted) / Restored | Step / $10\text{ ms}$ ramp | `false` |
| `backing.isSolo` | Backing Track | Toggle Button | Mixer Solo Logic (заглушает не-Solo) | `false` / `true` | Изолирует канал | Step / $10\text{ ms}$ ramp | `false` |
| `mic1.fohVolume` | Mic 1 (Lead) | Vertical Fader | `mic1FOHGain.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | $40\log_{10}(v)$ dB | $0.80$ (-3.8 dB) |
| `mic1.iemVolume` | Mic 1 (Lead) | Vertical Fader | `mic1IEMGain.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | $40\log_{10}(v)$ dB | $0.95$ (-0.9 dB) |
| `mic1.reverbSend` | Mic 1 (Lead) | Slider | `mic1ReverbSend.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | Линейный gain | $0.20$ |
| `mic1.isMuted` | Mic 1 (Lead) | Toggle Button | `mic1FOHGain`, `mic1IEMGain`, `mic1ReverbSend` | `false` / `true` | $0.0$ (Muted) / Restored | Step / $10\text{ ms}$ ramp | `false` |
| `mic1.isSolo` | Mic 1 (Lead) | Toggle Button | Mixer Solo Logic | `false` / `true` | Изолирует канал | Step / $10\text{ ms}$ ramp | `false` |
| `mic1.lowCut` | Mic 1 (Lead) | Checkbox | `mic1EQNode.bands[0].bypass` | `false` / `true` | HighPass 80 Hz ($Q=0.7$) | On/Off | `true` (Active) |
| `mic1.midGain` | Mic 1 (Lead) | Slider | `mic1EQNode.bands[1].gain` | $-6.0 \dots +6.0\text{ dB}$ | 2.8 kHz Peak, $Q=1.2$ | Линейный в dB | $+1.5\text{ dB}$ |
| `mic1.highGain` | Mic 1 (Lead) | Slider | `mic1EQNode.bands[2].gain` | $-6.0 \dots +6.0\text{ dB}$ | 10 kHz High Shelf | Линейный в dB | $+2.0\text{ dB}$ |
| `mic1.compBypass` | Mic 1 (Lead) | Internal/Toggle | `mic1CompressorNode.bypass` | `false` / `true` | DynamicsProcessor | Bypass On/Off | `false` (Active) |
| `mic2.fohVolume` | Mic 2 (Backing) | Vertical Fader | `mic2FOHGain.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | $40\log_{10}(v)$ dB | $0.80$ (-3.8 dB) |
| `mic2.iemVolume` | Mic 2 (Backing) | Vertical Fader | `mic2IEMGain.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | $40\log_{10}(v)$ dB | $0.95$ (-0.9 dB) |
| `mic2.reverbSend` | Mic 2 (Backing) | Slider | `mic2ReverbSend.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | Линейный gain | $0.20$ |
| `mic2.isMuted` | Mic 2 (Backing) | Toggle Button | `mic2FOHGain`, `mic2IEMGain`, `mic2ReverbSend` | `false` / `true` | $0.0$ (Muted) / Restored | Step / $10\text{ ms}$ ramp | `false` |
| `mic2.isSolo` | Mic 2 (Backing) | Toggle Button | Mixer Solo Logic | `false` / `true` | Изолирует канал | Step / $10\text{ ms}$ ramp | `false` |
| `mic2.lowCut` | Mic 2 (Backing) | Checkbox | `mic2EQNode.bands[0].bypass` | `false` / `true` | HighPass 80 Hz ($Q=0.7$) | On/Off | `true` (Active) |
| `mic2.midGain` | Mic 2 (Backing) | Slider | `mic2EQNode.bands[1].gain` | $-6.0 \dots +6.0\text{ dB}$ | 2.8 kHz Peak, $Q=1.2$ | Линейный в dB | $+1.5\text{ dB}$ |
| `mic2.highGain` | Mic 2 (Backing) | Slider | `mic2EQNode.bands[2].gain` | $-6.0 \dots +6.0\text{ dB}$ | 10 kHz High Shelf | Линейный в dB | $+2.0\text{ dB}$ |
| `mic2.compBypass` | Mic 2 (Backing) | Internal/Toggle | `mic2CompressorNode.bypass` | `false` / `true` | DynamicsProcessor | Bypass On/Off | `false` (Active) |
| `reverb.returnFOH`| Reverb Return | Internal Fader | `reverbReturnFOH.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | Линейный gain | $1.0$ (0 dB) |
| `reverb.returnIEM`| Reverb Return | Internal Fader | `reverbReturnIEM.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | Линейный gain | $1.0$ (0 dB) |
| `master.fohVolume`| Master FOH | Vertical Fader | `fohMixer.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | $40\log_{10}(v)$ dB | $1.0$ (0 dB) |
| `master.iemVolume`| Master IEM | Vertical Fader | `iemMixer.outputVolume` | $0.0 \dots 1.0$ | $0.0 \dots 1.0$ | $40\log_{10}(v)$ dB | $1.0$ (0 dB) |

---

## 2. Логика Mute и Solo (Mute > Solo Priority & Truth Table)

### 2.1 Правила вычисления эффективного усиления (Effective Gain)

Пусть множество каналов $C = \{\text{backing}, \text{mic1}, \text{mic2}\}$.
Каждый канал $c \in C$ имеет:
- Установленные пользователем уровни: $V_{\text{FOH}}(c)$, $V_{\text{IEM}}(c)$, $V_{\text{REV}}(c)$ (для микрофонов).
- Флаги состояния: $M(c) \in \{\text{true}, \text{false}\}$ (`isMuted`), $S(c) \in \{\text{true}, \text{false}\}$ (`isSolo`).

1. **Глобальный флаг Solo:**
   $$\text{AnySolo} = \bigvee_{i \in C} S(i)$$

2. **Эффективное состояние глушения (Effective Mute):**
   $$\text{IsSilenced}(c) = M(c) \lor (\text{AnySolo} \land \neg S(c))$$

3. **Приоритет Mute > Solo:**
   Если $M(c) = \text{true}$ и $S(c) = \text{true}$, то $\text{IsSilenced}(c) = \text{true}$. Mute подавляет Solo.

4. **Эффективные выходные коэффициенты:**
   $$G_{\text{FOH}}(c) = \begin{cases} 0.0, & \text{если } \text{IsSilenced}(c) \\ V_{\text{FOH}}(c), & \text{иначе} \end{cases}$$
   $$G_{\text{IEM}}(c) = \begin{cases} 0.0, & \text{если } \text{IsSilenced}(c) \\ V_{\text{IEM}}(c), & \text{иначе} \end{cases}$$
   $$G_{\text{REV}}(c) = \begin{cases} 0.0, & \text{если } \text{IsSilenced}(c) \\ V_{\text{REV}}(c), & \text{иначе} \end{cases}$$

> [!IMPORTANT]
> Обратите внимание: $G_{\text{REV}}(c) = 0.0$ при глушении канала. Это гарантирует, что не-солирующий или замьюченный микрофон не производит реверберационного «хвоста» в шины FOH и IEM.

### 2.2 Таблица состояний (Truth Table)

| `AnySolo` | $S(c)$ | $M(c)$ | $\text{IsSilenced}(c)$ | $G_{\text{FOH}}(c)$ | $G_{\text{IEM}}(c)$ | $G_{\text{REV}}(c)$ | Статус |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| `false` | `false` | `false` | `false` | $V_{\text{FOH}}$ | $V_{\text{IEM}}$ | $V_{\text{REV}}$ | Normal Playback |
| `false` | `false` | `true`  | `true`  | $0.0$ | $0.0$ | $0.0$ | Explicit Mute |
| `true`  | `true`  | `false` | `false` | $V_{\text{FOH}}$ | $V_{\text{IEM}}$ | $V_{\text{REV}}$ | Solo Active |
| `true`  | `true`  | `true`  | `true`  | $0.0$ | $0.0$ | $0.0$ | Mute Overrides Solo |
| `true`  | `false` | `false` | `true`  | $0.0$ | $0.0$ | $0.0$ | Silenced by other Solo |
| `true`  | `false` | `true`  | `true`  | $0.0$ | $0.0$ | $0.0$ | Silenced (Mute + other Solo) |

---

## 3. Спецификация DSP компонентов

### 3.1 Эквалайзер (AVAudioUnitEQ)
- **Band 0:** High-Pass Filter, $f_0 = 80.0\text{ Hz}$, добротность $Q = 0.707$. Подавляет низкочастотный гул микрофонной стойки, шум дыхания и сценическую вибрацию. Bypass при `lowCutEnabled == false`.
- **Band 1:** Parametric Peaking Filter, $f_0 = 2800.0\text{ Hz}$ ($2.8\text{ кГц}$), $Q = 1.2$. Управляет вокальной разборчивостью (Presence). Диапазон регулировки: $[-6.0\text{ dB}, +6.0\text{ dB}]$.
- **Band 2:** High-Shelf Filter, $f_0 = 10000.0\text{ Hz}$ ($10\text{ кГц}$). Придает открытость и блеск верхним частотам (Air band). Диапазон регулировки: $[-6.0\text{ dB}, +6.0\text{ dB}]$.

### 3.2 Динамический процессор (DynamicsProcessor)
Защищает аудиотракт от клиппирования при форсированном живом пении:
- **Threshold:** $-18.0\text{ dBFS}$
- **Headroom:** $5.0\text{ dB}$ (эффективный Ratio $\approx 3:1$)
- **Attack Time:** $0.005\text{ s}$ ($5\text{ ms}$)
- **Release Time:** $0.100\text{ s}$ ($100\text{ ms}$)
- **Bypass:** `false` по умолчанию. При необходимости отключается без клика.

---

## 4. Сглаживание параметров (Anti-Click Ramping)

1. **CoreAudio Parameter Smoothing:**
   Все узлы `AVAudioMixerNode` в macOS CoreAudio имеют аппаратное/встроенное сглаживание параметров громкости (`outputVolume`) длительностью $\approx 1500\text{ фреймов}$ ($\approx 31\text{ мс}$ при $48\text{ кГц}$).
2. **Гарантия отсутствия щелчков:**
   При переключении Mute / Solo и при скачкообразном перемещении ползунков фейдера CoreAudio выполняет непрерывную линейную интерполяцию коэффициентов передачи между смежными буферами, исключая ступенчатые разрывы в аудиосигнале.
