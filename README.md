# Journal

Нативное приложение для iOS 26 (SwiftUI, Liquid Glass): расписание группы, оценки, пропуски с лимитами, пометки к дням и расписание звонков.

- Только стандартные компоненты Apple: `TabView`, `NavigationStack`, `List`, `Form`, шторки, Swift Charts, кнопки и фон Liquid Glass.
- Светлая и тёмная темы — по настройке системы, один акцентный цвет.
- Данные хранятся только на устройстве. Расписание загружается с публичного сайта колледжа.
- Резервные копии из прежнего Flutter-приложения Journal открываются без изменений.

## Скриншоты без Mac

Задача `App screenshots` в GitHub Actions запускает приложение в симуляторе с демо-данными, проходит по экранам и сохраняет скриншоты (светлая и тёмная темы) в артефакт `Screenshots`. Демо-режим включается только аргументами запуска `-demo` / `-onboarding` в Debug-сборке и в выпускной IPA недоступен.

## Сборка

Проект описан в `project.yml` и генерируется [XcodeGen](https://github.com/yonaskolb/XcodeGen).
Сборку неподписанного IPA выполняет GitHub Actions (`.github/workflows/build.yml`) — Mac не нужен.

```bash
brew install xcodegen
xcodegen generate
open Journal.xcodeproj
```

Требуется Xcode 26 и iOS 26.

## Структура

```
Journal/
  Core/        даты, склонения
  Data/        модели и хранилище (JSON на устройстве)
  Logic/       звонки, лимиты, статистика, парсер и загрузка расписания
  UI/          экраны: Schedule, Grades, Absences, Settings, Onboarding, Components
JournalTests/    модульные тесты логики
JournalUITests/  обход экранов и скриншоты (запускается в CI)
.github/         сборка IPA, тесты, скриншоты
```
