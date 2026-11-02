# Каталог тестовых фикстур (Fixture Catalog)

**Версия:** 1.0  
**Дата создания:** 2026-11-02  
**Назначение:** Документирование детерминированных тестовых материалов для этапов E01–E14.

---

## 1. Текстовые фикстуры (Lyrics, LRC, ChordPro)

Расположение: `Tests/Fixtures/Lyrics/`

| Файл | Формат / Кодировка | Назначение | Ожидаемые свойства |
|---|---|---|---|
| `synced_lrc_standard.lrc` | LRC (UTF-8) | Базовый тест синхронизированного LRC | 5 строк, стандартные метки вида `[00:04.00]`, монотонно возрастающие. |
| `synced_lrc_fractional.lrc` | LRC (UTF-8) | Валидация парсинга дробной доли секунды (SF-08) | Метки с 1, 2 и 3 знаками (`.5` = 500ms, `.25` = 250ms, `.125` = 125ms). |
| `valid_chordpro.txt` | ChordPro (UTF-8) | Валидация синтаксиса аккордов и директив | Директивы `{title}`, `{artist}` игнорируются; аккорды `[Am]`, `[F]` извлекаются с точными character index. |
| `cyrillic_unicode.lrc` | LRC + ChordPro + Unicode (UTF-8) | Кириллица и эмодзи в тексте и аккордах | Корректное определение длины строк без битых символов и смещения индексов. |
| `malformed_tags.lrc` | LRC (UTF-8) | Проверка устойчивости к повреждённым тегам | Строки без временных меток, невалидные теги не вызывают crash или исключение. |
| `empty.txt` | Текст (0 байт) | Тест пустого файла | Корректное возвращение fallback / empty list без падений. |

---

## 2. Программно-генерируемые аудио-фикстуры (Audio Fixtures)

Генерируются детерминированно в памяти через `AVAudioPCMBuffer` и `AVAudioFormat`:

| Идентификатор | Формат | Длительность | Сигнал | Назначение |
|---|---|---|---|---|
| `audio-silence-48k-stereo` | 48 kHz, Float32 Stereo | 2.0 с | Все сэмплы = 0.0 | Проверка уровня шума, silence threshold, mute leak. |
| `audio-sine-1k-minus6db-48k` | 48 kHz, Float32 Stereo | 3.0 с | Синус 1000 Гц, пик = 0.5 (−6.02 dBFS) | Калибровка измерителей уровня (peak −6.02 dBFS, RMS −9.03 dBFS). |
| `audio-impulse-48k` | 48 kHz, Float32 Stereo | 1.0 с | Одиночный импульс (1.0 на frame 0) | Измерение задержки (latency) и проверка фильтров/EQ. |
| `audio-channel-id-4ch-48k` | 48 kHz, Float32 4-channel | 2.0 с | Ch1: 220Hz, Ch2: 440Hz, Ch3: 880Hz, Ch4: 1760Hz | Проверка многоканальной маршрутизации и отсутствия взаимопроникновения шин FOH/IEM. |

---

## 3. MIDI Fixtures

Расположение: `Tests/Fixtures/MIDI/` и программные тестовые UMP-пакеты:

| Идентификатор | Тип | Назначение | Ожидаемое действие |
|---|---|---|---|
| `ump-cc-7-volume` | UMP Packet (0xB0 0x07 0x7F) | CC 7 (Master Volume) | Изменение громкости FOH Master на 1.0 |
| `ump-cc-1-modwheel` | UMP Packet (0xB0 0x01 0x40) | CC 1 (Modulation Wheel) | Изменение Reverb Send на ~0.50 |
| `ump-cc-64-sustain` | UMP Packet (0xB0 0x40 0x7F) | CC 64 (Sustain Pedal) | Переключение Play/Pause |
| `ump-note-on-60` | UMP Packet (0x90 0x3C 0x64) | Note On C4 (Note 60) | Триггер Play/Pause |
| `ump-multi-word-sysex` | UMP Packet (Multi-word) | SysEx / неизвестные команды | Безопасный пропуск без crash и без зависания |
