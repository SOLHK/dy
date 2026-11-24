import Foundation

@main
enum DiagnosticLogTests {
    static func main() throws {
        let sanitize = DDDiagnosticLog.sanitized
        precondition(sanitize("DDWAIT 123456 +1.5s tcs=1 rate=0.0 why=EvaluatingBufferingRate st=1 keepUp=false empty=true loaded=[0-3] token=private")
            == "playback.wait waitingSeconds=1.5 timeControlStatus=1 rate=0.0 itemStatus=1 keepUp=false bufferEmpty=true")
        precondition(sanitize("DDSTARTUP 11099990001234567 起播=0.82s dur=28")
            == "playback.started startupSeconds=0.82 durationSeconds=28")
        precondition(sanitize("DDFEED idx=2 tab s=200 code=0 signed=true raw=14 kept=10 tall=9 follow=0 more=true msg=secret URL with token")
            == "network.feed http=200 code=0 signed=true received=14 kept=10 more=true")
        precondition(sanitize("DDIMG fail http=403 bytes=4 head=deadbeef host=private.example ext=png")
            == "network.imageDecodeFailed http=403 bytes=4")
        precondition(sanitize("DDAPPLOGIN confirm newSession=true path=/private sessionid=abc") == "session.loginConfirmed newSession=true")
        precondition(sanitize("DDCHAT open miss not-found\nDDSESSION sessionid present suppressed=false") == "chat.openFailed reason=not-found")
        precondition(sanitize("DDMSG layout=resizable") == "layout.messages layout=resizable")
        for raw in ["DDAPPLOGIN baseline sessionid=secret", "DDCK export 9 sessionid=true", "DDCHAT tick=5 new=2 first=private message",
                    "DDDM shape message=private", "DDFEED idx=2 tab s=abc signed=true len=4 more=false", "DDIMG fail http=400 bytes=4secret"] {
            precondition(sanitize(raw) == nil, "Unsafe diagnostic event was accepted")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date(timeIntervalSince1970: 120.25)
        var writer = DDDiagnosticLog.Store(directory: directory)
        try writer.record("older", at: start, now: start)
        let newer = start.addingTimeInterval(0.75)
        try writer.record("newer", at: newer, now: newer)

        // Reopen storage to exercise persisted history and prune within the oldest minute.
        var reopened = DDDiagnosticLog.Store(directory: directory)
        let exportAt = start.addingTimeInterval(3600.25)
        let next = start.addingTimeInterval(3599)
        try reopened.record("latest", at: next, now: exportAt)
        let remaining = try reopened.recent(now: exportAt)
        precondition(remaining == "1970-01-01T00:02:01.000Z newer\n1970-01-01T01:01:59.250Z latest\n")
        let oldestFile = directory.appendingPathComponent("2.log")
        precondition(try! String(contentsOf: oldestFile, encoding: .utf8) == "121.0\tnewer\n")

        let afterBoundary = newer.addingTimeInterval(3600)
        try reopened.record("now", at: afterBoundary, now: afterBoundary)
        precondition(!FileManager.default.fileExists(atPath: oldestFile.path), "Expired notice must be removed on write")
        let afterStale = afterBoundary.addingTimeInterval(3600)
        let staleResult = try reopened.recent(now: afterStale)
        precondition(staleResult == nil, "Exactly one-hour-old events are outside the window")
        try reopened.clear()
        precondition(!FileManager.default.fileExists(atPath: directory.path))
        print("Diagnostic allowlist, persistence, retention and clear passed")
    }
}
