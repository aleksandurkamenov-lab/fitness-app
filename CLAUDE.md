# Fitness App: правила за Claude

Лично iOS приложение (SwiftUI + SwiftData, iOS 26+). Потребителят (Aleksandur) не е програмист: Claude пише целия код. Отговори на български, кратко (английски технически термини са ок). Здравни числа: "ориентировъчно, не е медицински съвет".

## Структура
- `FitnessApp/` е синхронизирана папка в Xcode: нов .swift файл вътре се включва автоматично, pbxproj не се пипа.
- `Models/` SwiftData и enum-и, `Services/` логика (BodyMath, RecoveryMath, HealthService, WHOOP, Polar), `Features/<Таб>/` екрани, `Features/ChartScrub.swift` общ помощник за графики (`.chartScrub(...)`).
- Entitlements: `FitnessApp.entitlements` в корена (извън синхронизираната папка).
- Нови полета в @Model: винаги със стойност по подразбиране (леко мигриране).

## Версии
Всяка промяна: commit "vN: ..." + ред в `CHANGELOG.md` + смяна на "Версия vN" във футъра на `Features/Workouts/WorkoutsView.swift`. Клон `stage-1-body`. Git tag дава HTTP 403, не се ползват.
Събирай няколко промени в една версия, когато е възможно.

## Пускане на телефона (Mac през computer-use)
1. Редактирай в `/home/claude/fitness-app`, commit, push.
2. `cp` променените файлове в `/mnt/project-files/app-sync/FitnessApp/...`, изчакай ~12 s.
3. `device_commit_files` (force=true) към `/Users/aleksandarkamenov/Documents/fitness app/FitnessApp/...`.
4. Сравни `md5sum` на Mac (`$HOME/mnt/fitness app/FitnessApp/...`) със същите файлове: стари копия чупеха билда.
5. Xcode: Stop (350,120), 3 s, Run (324,120), ~45 s; увеличи [380,100,1000,140] и виж "Running FitnessApp on Kamenov" (не симулатор). При Build Failed отвори списъка с грешки (1318,120).
6. `computer_release_lock`. Потребителят може да въвежда Mac парола и да отключва телефона.
Xcode е "click" ниво: без писане. Линукс средата няма swift: кодът не се компилира тук, затова внимавай със синтаксиса.

## Код
- `Section { } header: { } footer: { }` (не `Section("t") { } footer:`).
- Числови полета: `.keyboardDoneButton()`. Профил: `.profileButton()` във всеки таб.
- Закръгляне на нормите: `formatted(.number.precision(.fractionLength(0...2)))`.
- Графики: вмъквай `.chartScrub(...)` за точна стойност при докосване; ключове в Chart да са уникални.

## Данни от устройства
WHOOP API v2 (OAuth, ключове в Keychain), Polar AccessLink v3, Apple Health. WHOOP и Polar не пишат HRV/Recovery в Health.
