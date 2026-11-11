import SwiftUI

/// Первый запуск: приветствие → выбор группы → быстрые настройки.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(ScheduleRepo.self) private var repo

    private enum Step { case welcome, group, setup }

    @State private var step: Step

    init(startAtGroup: Bool) {
        _step = State(initialValue: startAtGroup ? .group : .welcome)
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                welcome.transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            case .group:
                groupStep.transition(.move(edge: .trailing).combined(with: .opacity))
            case .setup:
                setupStep.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: step)
    }

    // MARK: Приветствие

    private var welcome: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(.white)
                            .frame(width: 104, height: 104)
                            .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                        Text("Добро пожаловать в Journal")
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text("Дневник студента: всё об учёбе в одном месте")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 56)

                    VStack(alignment: .leading, spacing: 22) {
                        feature("calendar", .blue, "Расписание", "Пары на каждый день с аудиториями, звонками и подсказкой, что идёт сейчас.")
                        feature("star.fill", .orange, "Оценки", "Средний балл по предметам, динамика и распределение по десятибалльной шкале.")
                        feature("calendar.badge.minus", .red, "Пропуски", "Отмечайте пропуски одним касанием и следите за лимитами месяца и семестра.")
                        feature("flag.fill", .indigo, "Пометки", "ОКР, зачёты и практика — важное к конкретному дню или паре.")
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 24)
            }
            Button {
                Haptics.light()
                step = .group
            } label: {
                Text("Продолжить").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 28)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }

    private func feature(_ icon: String, _ color: Color, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(color)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Группа

    private var groupStep: some View {
        NavigationStack {
            GroupPickerView(selected: store.settings.group, title: "Выберите группу") { group in
                store.setGroup(group)
                step = .setup
            }
            .toolbar {
                if !store.onboarded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Назад") { step = .welcome }
                    }
                }
            }
        }
    }

    // MARK: Настройки

    private var setupStep: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Группа \(store.settings.group)")
                        .font(.headline)
                } footer: {
                    Text("Сменить группу можно в любой момент в профиле.")
                }

                Section {
                    Picker("Часов за один пропуск", selection: Binding(get: { store.settings.absenceHours },
                                                                       set: { store.setAbsenceHours($0) })) {
                        Text("1 час").tag(1)
                        Text("2 часа").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Пропуски")
                } footer: {
                    Text("Пара — это 2 академических часа. Значение можно изменить при каждой отметке.")
                }

                Section {
                    Toggle("Автообновление расписания", isOn: Binding(get: { store.settings.autoRefresh },
                                                                      set: { store.setAutoRefresh($0) }))
                } footer: {
                    Text("Расписание на ближайшие дни будет подгружаться само.")
                }
            }
            .navigationTitle("Почти готово")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    Haptics.success()
                    store.finishOnboarding()
                    Task { await repo.prefetch(force: true, respectSetting: false) }
                } label: {
                    Text("Начать").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Назад") { step = .group }
                }
            }
        }
    }
}
