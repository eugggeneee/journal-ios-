import XCTest

/// Проходит по экранам приложения в демо-режиме и сохраняет скриншоты как вложения теста.
/// Запускается только в CI (схема Screenshots) и не влияет на обычную сборку.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Сценарии

    func testOnboarding() {
        let app = launch(dark: false, args: ["-onboarding"])
        shot("00-onboarding-welcome", wait: 2)
        if tap(app.buttons["Продолжить"]) {
            shot("00-onboarding-group", wait: 5)
        }
    }

    func testLightTour() {
        tour(dark: false, full: true)
    }

    func testDarkTour() {
        tour(dark: true, full: false)
    }

    // MARK: - Обход

    private func tour(dark: Bool, full: Bool) {
        let s = dark ? "dark" : "light"
        let app = launch(dark: dark, args: ["-demo"])
        shot("01-schedule-\(s)", wait: 3)

        if full {
            if tap(item(app, "Английский язык")) {
                shot("02-lesson-\(s)")
                closeSheet(app)
            }
            if tap(app.buttons["Отметить пропуск 4 пары"]) {
                shot("03-absence-quick-\(s)")
                closeSheet(app)
            }
            if tap(app.buttons["Выбрать дату"]) {
                shot("04-date-picker-\(s)")
                closeSheet(app)
            }
            if tap(app.buttons["Добавить"]) {
                shot("05-add-menu-\(s)")
                dismissMenu(app)
            }
            if tap(app.buttons["Ещё"]) {
                if tap(app.buttons["Звонки"]) {
                    shot("06-day-bells-\(s)")
                    closeSheet(app)
                } else {
                    dismissMenu(app)
                }
            }
        }

        tapTab(app, "Оценки")
        shot("10-grades-\(s)", wait: 1.5)
        if full {
            if tap(item(app, "Математика")) {
                shot("11-grades-subject-\(s)", wait: 1.5)
                back(app)
            }
            if tap(app.segmentedControls.buttons["Журнал"]) {
                shot("12-grades-journal-\(s)")
                tap(app.segmentedControls.buttons["Предметы"])
            }
            if tap(app.buttons["Добавить оценку"]) {
                shot("13-grade-form-\(s)")
                closeSheet(app)
            }
        }

        tapTab(app, "Пропуски")
        shot("20-absences-\(s)", wait: 1.5)
        if full {
            if tap(item(app, "1-й семестр")) {
                shot("21-semester-\(s)")
                closeSheet(app)
            }
        }

        tapTab(app, "Профиль")
        shot("30-profile-\(s)", wait: 1.2)
        if full {
            if tap(item(app, "Звонки")) {
                shot("31-bells-\(s)")
                back(app)
            }
            if tap(item(app, "Пропуски и семестры")) {
                shot("32-absence-settings-\(s)")
                back(app)
            }
            if tap(item(app, "Данные и резервная копия")) {
                shot("33-data-\(s)")
                back(app)
            }
        }
    }

    // MARK: - Помощники

    private func launch(dark: Bool, args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        if dark { app.launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        app.launch()
        return app
    }

    private func shot(_ name: String, wait: TimeInterval = 1.0) {
        Thread.sleep(forTimeInterval: wait)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Ищет кнопку по части подписи (карточки и строки списков объединяют тексты в одну кнопку),
    /// а если такой нет — обычный текст на экране.
    private func item(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: 4) { return button }
        return app.staticTexts[text].firstMatch
    }

    @discardableResult
    private func tap(_ element: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    private func tapTab(_ app: XCUIApplication, _ name: String) {
        let inBar = app.tabBars.buttons[name]
        if inBar.waitForExistence(timeout: 4) {
            inBar.tap()
        } else {
            tap(app.buttons[name].firstMatch)
        }
    }

    private func closeSheet(_ app: XCUIApplication) {
        for name in ["Готово", "Отмена"] {
            let button = app.buttons[name]
            if button.exists && button.isHittable {
                button.tap()
                Thread.sleep(forTimeInterval: 0.8)
                return
            }
        }
        app.swipeDown(velocity: .fast)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func dismissMenu(_ app: XCUIApplication) {
        // Закрываем всплывающее меню касанием в верхней части экрана.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.exists {
            button.tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
    }
}
