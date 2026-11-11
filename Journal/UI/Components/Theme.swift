import SwiftUI
import UIKit

// MARK: - Тактильный отклик

enum Haptics {
    @MainActor static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    @MainActor static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    @MainActor static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    @MainActor static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

// MARK: - Цвета оценок и статусов

/// Шкала оценок: плавный переход от красного к зелёному. Узлы: оценка → оттенок (градусы).
private let scaleGrade: [Double] = [1, 3, 4.5, 6, 7.5, 9, 10]
private let scaleHue: [Double] = [4, 14, 30, 44, 76, 128, 152]

func gradeHue(_ v: Double) -> Double {
    let x = min(10, max(1, v))
    for i in 0..<(scaleGrade.count - 1) where x <= scaleGrade[i + 1] {
        let t = (x - scaleGrade[i]) / (scaleGrade[i + 1] - scaleGrade[i])
        return scaleHue[i] + (scaleHue[i + 1] - scaleHue[i]) * t
    }
    return scaleHue[scaleHue.count - 1]
}

private func dynamicColor(light: UIColor, dark: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

private func hsb(_ hue: Double, _ s: Double, _ b: Double) -> UIColor {
    UIColor(hue: CGFloat((hue.truncatingRemainder(dividingBy: 360)) / 360), saturation: CGFloat(s), brightness: CGFloat(b), alpha: 1)
}

/// Насыщенный цвет оценки (столбики, графики, обводки).
func gradeFill(_ v: Double) -> Color {
    let h = gradeHue(v)
    return dynamicColor(light: hsb(h, 0.78, 0.93), dark: hsb(h, 0.62, 1.0))
}

/// Цвет текста и значка оценки: тёмнее заливки в светлой теме, чтобы читалось на светлой подложке.
func gradeText(_ v: Double) -> Color {
    let h = gradeHue(v)
    return dynamicColor(light: hsb(h, 0.95, 0.58), dark: hsb(h, 0.45, 1.0))
}

func gradeFill(_ v: Int) -> Color { gradeFill(Double(v)) }
func gradeText(_ v: Int) -> Color { gradeText(Double(v)) }

/// Цвет пропуска: красный — без уважительной причины, зелёный — по уважительной.
func absenceColor(excused: Bool) -> Color { excused ? .green : .red }

/// Цвет предупреждения «лимит близко».
let warnColor = Color.orange

/// Цвет пометок.
let markColor = Color.indigo

// MARK: - Базовые компоненты

/// Плашка с номером пары или оценкой.
struct NumberBadge: View {
    let text: String
    let color: Color
    var textColor: Color? = nil
    var size: CGFloat = 46

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(textColor ?? color)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, 3)
            .frame(width: size, height: size)
            .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Круглая иконка в цветной подложке для списков.
struct IconBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Небольшая плашка с текстом и значком.
struct Pill: View {
    let text: String
    var systemImage: String? = nil
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage = systemImage {
                Image(systemName: systemImage).font(.caption.weight(.bold))
            }
            Text(text).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
    }
}

/// Контейнер карточки на сгруппированном фоне.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                    if let tint = tint {
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint.opacity(0.14))
                    }
                }
            }
    }
}

/// Крупная итоговая карточка с мягким цветным градиентом.
struct HeroCard<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.30), tint.opacity(0.10)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
    }
}

/// Горизонтальная полоса прогресса.
struct ProgressBar: View {
    let value: Double
    var color: Color = .accentColor
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * CGFloat(min(1, max(0, value)))))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.smooth, value: value)
        .accessibilityHidden(true)
    }
}

/// Число, которое плавно «перекатывается» при изменении.
struct AnimatedNumber: View {
    let value: Double
    let text: String

    var body: some View {
        Text(text)
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(.smooth, value: value)
    }
}

/// Заголовок раздела на странице без списка.
struct SectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let trailing = trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Стиль кнопки-карточки: лёгкое сжатие при нажатии.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}
