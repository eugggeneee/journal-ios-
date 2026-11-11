import SwiftUI
import UniformTypeIdentifiers

struct ProfilePage: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        router.present(.group)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "person.2.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Группа \(store.settings.group)").font(.title3.weight(.bold)).foregroundStyle(.primary)
                                Text("Нажмите, чтобы сменить").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                }

                Section("Учёба") {
                    NavigationLink {
                        BellsView()
                    } label: {
                        row("Звонки", "bell.fill", .orange)
                    }
                    NavigationLink {
                        ScheduleSettingsView()
                    } label: {
                        row("Расписание", "calendar", .blue)
                    }
                    NavigationLink {
                        AbsenceSettingsView()
                    } label: {
                        row("Пропуски и семестры", "calendar.badge.minus", .red)
                    }
                }

                Section("Приложение") {
                    NavigationLink {
                        DataView()
                    } label: {
                        row("Данные и резервная копия", "externaldrive.fill", .gray)
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        row("О приложении", "info.circle.fill", .indigo)
                    }
                }
            }
            .navigationTitle("Профиль")
        }
        .toastHost()
    }

    private func row(_ title: String, _ icon: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            IconBadge(systemImage: icon, color: color, size: 30)
        }
    }
}

// MARK: - Расписание

struct ScheduleSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(ScheduleRepo.self) private var repo
    @Environment(Toaster.self) private var toaster

    @State private var refreshing = false

    var body: some View {
        Form {
            Section {
                Toggle("Автообновление", isOn: Binding(get: { store.settings.autoRefresh },
                                                       set: { store.setAutoRefresh($0) }))
            } footer: {
                Text("Расписание на ближайшие дни подгружается при запуске и возвращении в приложение. Сохранённые дни доступны без интернета.")
            }

            Section {
                Button {
                    refresh()
                } label: {
                    HStack {
                        Label("Обновить сейчас", systemImage: "arrow.clockwise")
                        Spacer()
                        if refreshing { ProgressView() }
                    }
                }
                .disabled(refreshing)
            } footer: {
                Text("Источник — публичный сайт колледжа bseumtc.by.")
            }
        }
        .navigationTitle("Расписание")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func refresh() {
        refreshing = true
        Haptics.light()
        Task {
            await repo.prefetch(force: true, respectSetting: false)
            refreshing = false
            toaster.show("Расписание обновлено")
        }
    }
}

// MARK: - Пропуски и семестры

struct AbsenceSettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    @State private var confirmEnd = false

    var body: some View {
        let now = Date()
        let sem = store.semester(on: now)
        let year = academicYear(of: now)
        let hasSplit = semesterSplit(year, store.settings.semesterSplits) != nil

        Form {
            Section {
                Picker("При быстрой отметке", selection: Binding(get: { store.settings.absenceHours },
                                                                  set: { store.setAbsenceHours($0) })) {
                    Text("1 час").tag(1)
                    Text("2 часа").tag(2)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Часов за один пропуск")
            } footer: {
                Text("Пара — это 2 академических часа. Значение можно изменить при отметке.")
            }

            Section {
                LabeledContent("Учебный год", value: sem.years)
                LabeledContent("Сейчас", value: sem.upcoming ? "Каникулы" : sem.title)
                LabeledContent("Период", value: "\(shortDate(sem.start)) – \(shortDate(sem.end))")
            } header: {
                Text("Семестр")
            }

            Section {
                if canEndSemester(now, store.settings.semesterSplits) {
                    Button {
                        confirmEnd = true
                    } label: {
                        Label("Завершить 1-й семестр", systemImage: "flag.checkered")
                    }
                }
                if hasSplit {
                    Button {
                        reopen(year: year)
                    } label: {
                        Label("Вернуть 1-й семестр", systemImage: "arrow.uturn.backward")
                    }
                }
            } footer: {
                Text("Лимит: \(kMonthLimit) ч в месяц и \(kSemesterLimit) ч в семестр без уважительной причины. После завершения 1-го семестра счёт часов начинается заново.")
            }
        }
        .navigationTitle("Пропуски")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Завершить 1-й семестр?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("Завершить сегодня") { endSemester() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Со следующего дня начнётся 2-й семестр, часы будут считаться заново. Это можно отменить.")
        }
    }

    private func endSemester() {
        let store = self.store
        let year = academicYear(of: Date())
        if store.endFirstSemester(from: Date()) {
            Haptics.success()
            toaster.show("1-й семестр завершён") { store.reopenFirstSemester(year: year) }
        }
    }

    private func reopen(year: Int) {
        let store = self.store
        let previous = store.settings.semesterSplits["\(year)"]
        store.reopenFirstSemester(year: year)
        Haptics.selection()
        toaster.show("1-й семестр возвращён") { store.restoreSemesterSplit(year: year, value: previous) }
    }
}

// MARK: - Данные

struct DataView: View {
    @Environment(AppStore.self) private var store
    @Environment(Toaster.self) private var toaster

    @State private var importing = false
    @State private var pendingImport: String?
    @State private var errorText: String?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Сейчас в приложении") {
                LabeledContent("Оценки", value: "\(store.grades.count)")
                LabeledContent("Пропуски", value: "\(store.absences.count)")
                LabeledContent("Пометки", value: "\(store.marks.count)")
            }

            Section {
                ShareLink(item: store.exportJson(), subject: Text("Резервная копия Journal")) {
                    Label("Поделиться копией", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = store.exportJson()
                    Haptics.success()
                    toaster.show("Копия скопирована")
                } label: {
                    Label("Скопировать в буфер", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Резервная копия")
            } footer: {
                Text("Данные хранятся только на этом устройстве. Сохраните копию, если меняете телефон или переустанавливаете приложение.")
            }

            Section {
                Button {
                    importing = true
                } label: {
                    Label("Открыть файл…", systemImage: "folder")
                }
                Button {
                    if let text = UIPasteboard.general.string, !text.isEmpty {
                        pendingImport = text
                    } else {
                        errorText = "В буфере обмена нет текста."
                    }
                } label: {
                    Label("Вставить из буфера", systemImage: "doc.on.clipboard")
                }
            } header: {
                Text("Восстановление")
            } footer: {
                Text("Подходят копии из этого и из прежнего приложения Journal. Текущие данные будут заменены.")
            }

            Section {
                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Label("Удалить оценки, пропуски и пометки", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Данные")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .plainText, .text]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
                    pendingImport = text
                } else {
                    errorText = "Не удалось прочитать файл."
                }
            case .failure:
                errorText = "Не удалось открыть файл."
            }
        }
        .confirmationDialog("Заменить текущие данные?", isPresented: Binding(get: { pendingImport != nil },
                                                                              set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("Заменить", role: .destructive) { runImport() }
            Button("Отмена", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Оценки, пропуски, пометки и настройки будут заменены данными из копии.")
        }
        .confirmationDialog("Удалить все записи?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { clear() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Настройки группы и звонков сохранятся. Это можно отменить сразу после удаления.")
        }
        .alert("Не получилось", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func runImport() {
        guard let text = pendingImport else { return }
        pendingImport = nil
        let store = self.store
        let backup = store.exportJson()
        if let error = store.importJson(text) {
            errorText = error
        } else {
            Haptics.success()
            toaster.show("Данные восстановлены") { _ = store.importJson(backup) }
        }
    }

    private func clear() {
        let store = self.store
        let backup = store.exportJson()
        store.clearUserData()
        Haptics.medium()
        toaster.show("Записи удалены") { _ = store.importJson(backup) }
    }
}

// MARK: - О приложении

struct AboutView: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Text("Journal").font(.title2.weight(.bold))
                    Text("Версия \(version)").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                Text("Дневник студента: расписание группы, оценки по десятибалльной шкале, пропуски с лимитами и пометки к дням.")
            }

            Section("Источники и приватность") {
                Text("Расписание загружается с публичного сайта колледжа bseumtc.by. Приложение неофициальное.")
                Text("Оценки, пропуски и настройки хранятся только на вашем устройстве. Аккаунтов и сторонних сервисов нет.")
            }
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}
