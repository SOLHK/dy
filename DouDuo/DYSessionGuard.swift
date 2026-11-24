import Foundation
import SwiftUI
import WebKit

/// 平台登录凭据失效时提示用户重新登录。切换账号和主动退出期间不弹提示。
@MainActor
final class DYSessionWatch: NSObject, WKHTTPCookieStoreObserver {
    static let shared = DYSessionWatch()
    private var last: String??
    private var started = false
    /// App 自己在退出 / 切换账号 / 登录页里：这时 sessionid 消失是预期内的，不弹
    var suppressed = 0
    var loginScreenOpen = false

    func start() {
        guard !started else { return }
        started = true
        WKWebsiteDataStore.default().httpCookieStore.add(self)
        Task { last = .some(await DYLoginState.sessionValue()) }
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in await self.check() }
    }

    private func check() async {
        let now = await DYLoginState.sessionValue()
        defer { last = .some(now) }
        guard case .some(let before) = last else { return }
        if Self.isLoss(before: before, now: now, suppressed: suppressed > 0 || loginScreenOpen) {
            DYLiveModel.log("DDSESSION lost sessionid (not by app) → prompt relogin")
            NotificationCenter.default.post(name: .dySessionLost, object: nil)
        } else if (before == nil) != (now == nil) {
            DYLiveModel.log("DDSESSION sessionid \(now == nil ? "gone" : "present") suppressed=\(suppressed > 0 || loginScreenOpen)")
        }
    }

    /// 只有「原来有登录、现在没了、又不是 App 自己做的」才算登录被弄丢
    nonisolated static func isLoss(before: String?, now: String?, suppressed: Bool) -> Bool {
        before != nil && now == nil && !suppressed
    }
}

extension Notification.Name {
    /// 本机抖音登录被清掉（不是 App 自己退出 / 切换）
    static let dySessionLost = Notification.Name("douduo.sessionLost")
}

/// 根界面挂一次：登录丢了弹提示，可直接去登录
struct DYSessionLostAlert: ViewModifier {
    var onRelogin: () -> Void
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .dySessionLost)) { _ in show = true }
            .alert("抖音登录已失效", isPresented: $show) {
                Button("重新登录") { onRelogin() }
                Button("稍后", role: .cancel) {}
            } message: {
                Text("本机的抖音登录被清掉了，评论、私信、关注要重新登录后才能用。未发出的评论草稿还在。")
            }
    }
}
