import Foundation

@MainActor
final class HallViewModel: ObservableObject {
    @Published var cards: [Card] = []
    @Published var loading = true
    @Published var loadingMore = false
    @Published var error: String?
    @Published var hasMore = false
    @Published var scene: String?
    @Published var keyword = ""

    private let api = AppServices.shared.api
    private let throttle = RefreshThrottle()
    private var page = 1
    private var loaded = false

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true
        await refresh()
    }

    func refresh(manual: Bool = false) async {
        if manual && !throttle.tryAcquire() { return }
        loading = !manual && cards.isEmpty
        error = nil
        page = 1
        do {
            let result = try await api.hall(
                scene: scene,
                keyword: keyword.isEmpty ? nil : keyword,
                page: 1,
                size: 20,
                bypassCache: manual
            )
            cards = result.items ?? []
            hasMore = result.hasMore
            loading = false
        } catch {
            if Task.isCancelled { return }
            loading = false
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !loading, !loadingMore, hasMore else { return }
        loadingMore = true
        do {
            let result = try await api.hall(
                scene: scene,
                keyword: keyword.isEmpty ? nil : keyword,
                page: page + 1,
                size: 20
            )
            page += 1
            cards.append(contentsOf: result.items ?? [])
            hasMore = result.hasMore
            loadingMore = false
        } catch {
            if !Task.isCancelled { loadingMore = false }
        }
    }

    func selectScene(_ value: String?) async {
        guard scene != value else { return }
        scene = value
        await refresh()
    }

    func search(_ value: String) async {
        keyword = value
        await refresh()
    }
}
