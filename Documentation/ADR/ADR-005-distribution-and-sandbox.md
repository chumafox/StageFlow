# ADR-005: Distribution Model, Security Sandbox & App Packaging

- **Статус:** Принят (Accepted)
- **Дата:** 2026-11-02
- **Автор:** Antigravity / jenya

---

## Контекст и проблема

StageFlow — живое сценическое приложение для macOS, требующее одновременного доступа к:
1. Микрофонным входам (CoreAudio InputNode) для живой обработки вокала;
2. Многоканальному аудиоинтерфейсу (4 канала вывода: FOH 1–2, IEM 3–4);
3. Пользовательским аудиофайлам и фонограммам на диске, внешних накопителях и USB-флешках;
4. MIDI-контроллерам и педалям (CoreMIDI / UMP).

При распространении приложений для macOS существуют две основные модели:
1. **Mac App Store** (жесткая изоляция sandbox, запрет на некоторые низкоуровневые API);
2. **Direct Distribution** (Developer ID с нотаризацией Apple Notary Service и включенным App Sandbox или Hardened Runtime).

## Решение

Для StageFlow утверждена модель **Direct Distribution (Developer ID with App Sandbox & Hardened Runtime)**:

1. **App Sandbox с минимально необходимыми правами (Least Privilege):**
   - `com.apple.security.app-sandbox` — базовая изоляция процессов;
   - `com.apple.security.device.audio-input` — обязательное разрешение для доступа к микрофонам (`AVCaptureDevice` / `AVAudioEngine.inputNode`);
   - `com.apple.security.files.user-selected.read-write` — доступ к аудиофайлам, выбранным пользователем через системный `NSOpenPanel`;
   - `com.apple.security.files.bookmarks.app-scope` — сохранение и резолвинг `Security-Scoped Bookmarks` для гарантированного открытия файлов плейлиста после перезапуска приложения без повторного запроса пользователя.

2. **Объяснение прав (Privacy Prompt):**
   - В `Info.plist` строго прописан ключ `NSMicrophoneUsageDescription` с понятным сценическим объяснением:
     *"StageFlow requires microphone access to process and route live vocal channels (Mic 1 and Mic 2) through EQ, compression, and independent FOH and IEM mixes."*

3. **Сборка и упаковка (`.app` Bundle):**
   - Пакет приложения собирается в стандартной структуре `StageFlow.app`:
     - `Contents/MacOS/StageFlow` — скомпилированный бинарный файл Apple Silicon (arm64);
     - `Contents/Info.plist` — метаданные, идентификатор `com.stageflow.StageFlow`, версия, системные требования macOS 13.0+;
     - `Contents/Resources/` — иконки и статические ресурсы.
   - Подпись бинарника и бандла выполняется утилитой `codesign` с Hardened Runtime (`--options runtime`) и передачей файла `StageFlow.entitlements`.

4. **Защита от утечки учетных данных:**
   - Никакие приватные сертификаты, пароли связки ключей или API-токены Notary Service не сохраняются в репозитории.
   - В CI/локальном окружении ключи передаются через переменные окружения `APPLE_ID`, `APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`.
