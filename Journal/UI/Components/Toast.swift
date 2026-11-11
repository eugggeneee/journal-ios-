import SwiftUI

/// Короткое сообщение внизу экрана; с кнопкой «Отменить», если действие можно откатить.
@MainActor
@Observable
final class Toaster {
    struct Item: Identifiable {
        let id = UUID()
        let message: String
        let undo: (() -> Void)?
    }

    var current: Item?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    func show(_ message: String, undo: (() -> Void)? = nil) {
        let item = Item(message: message, undo: undo)
        hideTask?.cancel()
        withAnimation(.smooth) { current = item }
        let seconds: UInt64 = undo == nil ? 3 : 5
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.hide(id: item.id)
        }
    }

    func hide(id: UUID? = nil) {
        if let id = id, current?.id != id { return }
        hideTask?.cancel()
        withAnimation(.smooth) { current = nil }
    }

    func performUndo() {
        guard let item = current else { return }
        hide(id: item.id)
        Haptics.selection()
        item.undo?()
    }
}

private struct ToastBar: View {
    @Environment(Toaster.self) private var toaster

    var body: some View {
        if let item = toaster.current {
            HStack(spacing: 12) {
                Text(item.message)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if item.undo != nil {
                    Button("Отменить") { toaster.performUndo() }
                        .font(.subheadline.weight(.bold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .id(item.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    /// Показывает сообщения [Toaster] над нижней панелью.
    func toastHost() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { ToastBar() }
    }
}
