import SwiftUI

// MARK: - Выбор предмета

/// Экран выбора предмета: предметы из расписания, все известные и добавление нового.
struct SubjectPickerView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: String
    var suggested: [String] = []
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ s: String) -> Bool {
        if trimmed.isEmpty { return true }
        return store.subjectName(s).localizedCaseInsensitiveContains(trimmed) || s.localizedCaseInsensitiveContains(trimmed)
    }

    private var suggestedList: [String] {
        var seen = Set<String>()
        return suggested.filter { !$0.isEmpty && seen.insert($0).inserted && matches($0) }
    }

    private var otherList: [String] {
        store.knownSubjects().filter { !suggested.contains($0) && matches($0) }
    }

    private var canAdd: Bool {
        guard !trimmed.isEmpty else { return false }
        let all = store.knownSubjects() + suggested
        return !all.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame || store.subjectName($0).caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        List {
            if !suggestedList.isEmpty {
                Section("Из расписания") {
                    ForEach(suggestedList, id: \.self) { row($0) }
                }
            }
            if !otherList.isEmpty {
                Section(suggestedList.isEmpty ? "Предметы" : "Другие предметы") {
                    ForEach(otherList, id: \.self) { row($0) }
                }
            }
            if canAdd {
                Section {
                    Button {
                        store.addExtraSubject(trimmed)
                        selected = trimmed
                        Haptics.selection()
                        dismiss()
                    } label: {
                        Label("Добавить «\(trimmed)»", systemImage: "plus.circle.fill")
                    }
                }
            }
            if suggestedList.isEmpty && otherList.isEmpty && !canAdd {
                Section {
                    Text("Начните вводить название, чтобы найти или добавить предмет")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Предмет")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Найти или добавить")
    }

    private func row(_ s: String) -> some View {
        Button {
            selected = s
            Haptics.selection()
            dismiss()
        } label: {
            HStack {
                Text(store.subjectName(s)).foregroundStyle(.primary)
                Spacer()
                if s == selected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
    }
}

/// Строка формы «Предмет», ведущая на экран выбора.
struct SubjectField: View {
    @Environment(AppStore.self) private var store
    @Binding var subject: String
    var suggested: [String] = []

    var body: some View {
        NavigationLink {
            SubjectPickerView(selected: $subject, suggested: suggested)
        } label: {
            HStack {
                Label("Предмет", systemImage: "book.closed")
                Spacer()
                Text(subject.isEmpty ? "Выберите" : store.subjectName(subject))
                    .foregroundStyle(subject.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

// MARK: - Часы и причина

/// Переключатель «1 час / 2 часа (пара)».
struct HoursPicker: View {
    @Binding var hours: Int
    var onChange: ((Int) -> Void)? = nil

    var body: some View {
        Picker("Сколько часов", selection: Binding(get: { hours }, set: { newValue in
            hours = newValue
            Haptics.selection()
            onChange?(newValue)
        })) {
            Text("1 час").tag(1)
            Text("2 часа (пара)").tag(2)
        }
        .pickerStyle(.segmented)
    }
}

/// Две кнопки причины пропуска. [selected]: nil — ничего не выбрано.
struct ExcuseButtons: View {
    var selected: Bool? = nil
    var enabled: Bool = true
    let onPick: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            tile(excused: false)
            tile(excused: true)
        }
    }

    private func tile(excused: Bool) -> some View {
        let color = absenceColor(excused: excused)
        let isSelected = selected == excused
        return Button {
            onPick(excused)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: excused ? "checkmark.seal.fill" : "calendar.badge.minus")
                    .font(.title2)
                Text(excused ? "По уважительной" : "Без уважительной")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? Color.white : color)
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.horizontal, 8)
            .background(isSelected ? color : color.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(excused ? "По уважительной причине" : "Без уважительной причины")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Выбор пары

/// Квадратик с номером пары.
struct PairSquare: View {
    let number: Int
    let selected: Bool
    var marked: Bool = false
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(number)")
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: size, height: size)
                .background(selected ? Color.accentColor : Color(.tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if marked {
                        Circle().fill(Color.red).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                            .offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(number) пара")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Чип выбора.
struct ChoiceChip: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage = systemImage { Image(systemName: systemImage).font(.subheadline) }
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
