import Foundation

enum DDDiagnosticLog {
    static let queue = DispatchQueue(label: "douduo.log", qos: .utility)
    static let directoryName = "DyDiagnostics"
    private static let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(directoryName, isDirectory: true)
    nonisolated(unsafe) private static var store = Store(directory: directory)

    static func appendOnLogQueue(_ message: String, at date: Date) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let event = sanitized(message) else { return }
        try? store.record(event, at: date, now: Date())
    }

    static func exportRecent() async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    guard let events = try store.recent(now: Date()), !events.isEmpty else { return nil }
                    let info = Bundle.main.infoDictionary
                    let name = info?["CFBundleDisplayName"] as? String ?? "抖音"
                    let version = info?["CFBundleShortVersionString"] as? String ?? "-"
                    let build = info?["CFBundleVersion"] as? String ?? "-"
                    let os = ProcessInfo.processInfo.operatingSystemVersion
                    let heading = "\(name) \(version) (\(build)) · iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\n"
                        + "最近一小时诊断日志 · UTC\n\n"
                    return Data((heading + events).utf8)
                })
            }
        }
    }

    static func clearOnLogQueue() -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        do {
            try store.clear()
            return true
        } catch {
            return false
        }
    }

    // Each recipe consumes a known shape and only emits fixed labels and validated captures.
    // Raw strings and positional identifiers never become part of the file.
    private struct Rule {
        let label: String
        let expression: NSRegularExpression
        let fields: [String]

        init(_ label: String, _ pattern: String, _ fields: String = "") {
            self.label = label
            expression = try! NSRegularExpression(pattern: "^" + pattern)
            self.fields = fields.split(separator: " ").map(String.init)
        }

        func render(_ body: String) -> String? {
            guard let result = expression.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
                  result.numberOfRanges == fields.count + 1 else { return nil }
            let values = fields.enumerated().compactMap { offset, key in
                Range(result.range(at: offset + 1), in: body).map { "\(key)=\(body[$0])" }
            }
            return ([label] + values).joined(separator: " ")
        }
    }

    private static let rules: [String: [Rule]] = [
        "DDSWIPEIN": [.init("playback.swipe", #"\S+ dur=(\d{1,7}) ready=(true|false) buf=(\d{1,7}(?:\.\d{1,3})?)s local=(true|false)\b"#, "durationSeconds ready bufferedSeconds local")],
        "DDSWIPET": [.init("playback.swipeTiming", #"\S+ lift→active=(-?\d{1,7}) active→rate=(-?\d{1,7}) rate→playing=(-?\d{1,7}) playing→move=(-?\d{1,7}) total=(-?\d{1,7})ms maxGap=(\d{1,7})ms drops=(\d{1,7})\b"#, "liftToActiveMs activeToRateMs rateToPlayingMs playingToMoveMs totalMs longestFrameMs droppedFrames")],
        "DDSTARTUP": [
            .init("playback.started", #"\S+ 起播=(\d{1,7}(?:\.\d{1,3})?)s dur=(\d{1,7})\b"#, "startupSeconds durationSeconds"),
            .init("playback.leftBeforeStart", #"\S+ 未起播就离开 等=(\d{1,7}(?:\.\d{1,3})?)s dur=(\d{1,7})\b"#, "waitingSeconds durationSeconds"),
        ],
        "DDSTALL": [.init("playback.stall", #"\S+ 卡=(\d{1,7}(?:\.\d{1,3})?)s at=(\d{1,7}(?:\.\d{1,3})?)/(\d{1,7})s\b"#, "stallSeconds positionSeconds durationSeconds")],
        "DDWAIT": [.init("playback.wait", #"\S+ \+(\d{1,7}(?:\.\d{1,3})?)s tcs=(\d{1,2}) rate=(\d{1,3}(?:\.\d{1,3})?) why=\S+ st=(-?\d{1,2}) keepUp=(true|false) empty=(true|false)\b"#, "waitingSeconds timeControlStatus rate itemStatus keepUp bufferEmpty")],
        "DDPLAYFAIL": [
            .init("playback.failed", #"\S+ at=(\d{1,7}(?:\.\d{1,3})?) err=[^/\s]+/(-?\d{1,7}) app=(\d{1,2})\b"#, "positionSeconds errorCode appState"),
            .init("playback.failed", #"\S+ at="#),
        ],
        "DDPRELOADFAIL": [.init("playback.preloadFailed", #"\S+ local=(true|false) err=[^/\s]+/(-?\d{1,7})\b"#, "local errorCode")],
        "DDREBUILD": [.init("playback.rebuilt", #"\S+ resume=(nil|\d{1,7}(?:\.\d{1,3})?) alt=(true|false)\b"#, "resumeSeconds alternateSource")],
        "DDRESUME": [
            .init("playback.resumeMasked", #"skip id="#),
            .init("playback.audioResumed", #"\S+ 音频会话被关后恢复 t=(\d{1,7}(?:\.\d{1,3})?)\b"#, "positionSeconds"),
        ],
        "DDLIFE": [
            .init("app.background", #"background now="#),
            .init("app.foreground", #"foreground now="#),
        ],
        "DDLIVE_READY": [.init("live.ready", #"room=\S+ elapsed=(\d{1,7}(?:\.\d{1,3})?) videoOut=(true|false)\b"#, "startupSeconds videoOut")],
        "DDLIVEPLAY": [.init("live.play", #"room=\S+ protocol=(FLV|HLS) q=\S+ cache=(\d{1,7}) drawable=(true|false) session=([01])\b"#, "protocol cacheMs drawable audioSession")],
        "DDLIVE_RESUME": [.init("live.resume", #"action=(reuse|reconnect|ignore)\b"#, "action")],
        "DDLIVE_FALLBACK": [.init("live.fallback", #"reason=.* remaining=(\d{1,5})$"#, "remainingSources")],
        "DDLIVE_WARM": [.init("live.preload", #"idx=\d+ proto=(FLV|HLS) code=(-?\d{1,3}) bytes=(\d{1,10}) elapsed=(\d{1,7}(?:\.\d{1,3})?)\b"#, "protocol http bytes elapsedSeconds")],
        "DDFEED": [
            .init("network.feed", #"idx=\d+ tab s=(-?\d{1,3}) code=(-?\d{1,7}|undefined|null) signed=(true|false) raw=(\d{1,7}) kept=(\d{1,7}) tall=\d+ follow=\d+ more=(true|false)\b"#, "http code signed received kept more"),
            .init("network.feed", #"idx=\d+ tab s=(-?\d{1,3}) signed=(true|false) len=(\d{1,10}) more=(true|false)\b"#, "http signed bytes more"),
        ],
        "DDCALL": [
            .init("network.webRequestFailed", #"err code=.* attempt=(\d{1,3})$"#, "attempt"),
            .init("network.webRequestFailed", #"err code="#),
        ],
        "DDREFRESH": [.init("network.feedRefreshFailed", #"failed kept="#)],
        "DDFOLLOWLIVE": [.init("live.followListFailed", #"outcome=(request_failed|decode_failed)\b"#, "reason")],
        "DDFOLLOWROOM": [.init("live.followRoomFailed", #"outcome=(request_failed|decode_failed)\b"#, "reason")],
        "DDSTREAMNET": [.init("network.streamResponse", #"\S+ (-?\d{1,3}) range=(\d{1,14})-(\d{1,14})\b"#, "http rangeStart rangeEnd")],
        "DDSTREAM": [.init("network.streamFailed", #"err \S+ [^/\s]+/(-?\d{1,7})\b"#, "errorCode")],
        "DDCACHE": [.init("storage.videoCacheFailed", #"fail host="#)],
        "DDOFFLINE": [.init("playback.offlineFallbackFailed", #"fallback failed="#)],
        "DDPRELOADFAIL2": [.init("playback.preloadFailed", #"\S+ err=[^/\s]+/(-?\d{1,7})\b"#, "errorCode")],
        "DDIMG": [
            .init("network.imageDecodeFailed", #"fail http=(-?\d{1,3}) bytes=(\d{1,10})\b"#, "http bytes"),
            .init("network.imageFailed", #"error host=\S* (-?\d{1,7})$"#, "errorCode"),
        ],
        "DDPHOTO": [.init("network.photoFetchFailed", #"fetch err\b"#)],
        "DDMINE": [.init("network.profileFailed", #"(refresh|self) err\b"#, "action")],
        "DDUPLOAD": [.init("network.uploadFailed", #"fail (-?\d{1,7})\b"#, "errorCode")],
        "DDPOST": [.init("network.publishFailed", #"error\b"#)],
        "DDSESSION": [
            .init("session.lost", #"lost sessionid \(not by app\)"#),
            .init("session.changed", #"sessionid (gone|present) suppressed=(true|false)\b"#, "state suppressed"),
            .init("session.commentRecovery", #"comment recovery: (sessionid gone|server says logged out|profile check inconclusive)\b"#, "decision"),
            .init("session.cacheWriteFailed", #"保存失败"#),
        ],
        "DDAPPLOGIN": [
            .init("session.loginShown", #"auto-show \("#),
            .init("session.loginConfirmed", #"confirm newSession=(true|false)\b"#, "newSession"),
        ],
        "DDQR": [.init("session.qrRequestFailed", #"get 失败"#)],
        "DDCOMMENT": [.init("network.commentTranslationFailed", #"translate err\b"#)],
        "DDREPLY": [.init("network.replyFailed", #"cid=\S+ error="#)],
        "DDSEND": [
            .init("network.commentSendFailed", #"comment op=\S+ phase=web-ui-error\b"#),
            .init("live.chatSendFailed", #"live javascript-error\b"#),
        ],
        "DDCHAT": [
            .init("chat.opened", #"open stranger=(true|false) ms=(\d{1,7}) prep_ms=(\d{1,7}) settle=(\d{1,7})f/(\d{1,7})ms composer=(true|false)\b"#, "stranger elapsedMs prepareMs settleFrames settleMs composerConnected"),
            .init("chat.openFailed", #"open miss (no-web|dom-not-ready|not-found)\b"#, "reason"),
            .init("chat.openBusy", #"open skip (?:busy|composer-working)\b"#),
            .init("chat.composer", #"composerReady=(true|false)\b"#, "ready"),
        ],
        "DDMSGOPEN": [.init("layout.messagesOpened", #"tap→built=(\d{1,7})ms tap→appear=(\d{1,7})ms\b"#, "buildMs appearMs")],
        "DDMSG": [.init("layout.messages", #"layout=(resizable|legacy)\b"#, "layout")],
        "DDMSGCACHE": [.init("chat.cacheWriteFailed", #"save failed\b"#)],
        "DDMSGVIDEO": [.init("chat.sharedVideoFailed", #"detail fail\b"#)],
        "DDNOTICE": [.init("chat.noticeFailed", #"(?:error\b|read-on-exit failed\b)"#)],
        "DDSTRANGER_TIMING": [.init("chat.strangerScanFailed", #"scan_error code=(-?\d{1,7})\b"#, "errorCode")],
        "DDSHARELINK": [.init("network.shareLinkFailed", #"detail err\b"#)],
        "DDTAB": [.init("layout.homeTab", #"(?:select|tap) target=(follow|recommend|live) from=(follow|recommend|live)\b"#, "target from")],
        "DDSTATUSBAR": [.init("layout.statusBar", #"refresh hidden=(true|false)\b"#, "hidden")],
        "DDSTORAGE": [.init("storage.cleaned", #"launch cleanup removed=(\d{1,7}) freed=(\d{1,7})MB\b"#, "removed freedMB")],
    ]

    static func sanitized(_ message: String) -> String? {
        let line = message.prefix(512).prefix(while: { !$0.isNewline })
        guard let separator = line.firstIndex(of: " "), let recipes = rules[String(line[..<separator])] else { return nil }
        let body = String(line[line.index(after: separator)...])
        for recipe in recipes {
            if let event = recipe.render(body) { return event }
        }
        return nil
    }

    struct Store {
        private static let retention: TimeInterval = 3600
        private static let maxMinuteBytes = 256 * 1024
        let directory: URL
        private var nextPruneAt: TimeInterval = -.infinity

        init(directory: URL) { self.directory = directory }

        mutating func record(_ event: String, at date: Date, now: Date) throws {
            let time = date.timeIntervalSince1970
            let current = now.timeIntervalSince1970
            if current >= nextPruneAt { try prune(now: current) }
            guard time > current - Self.retention else { return }
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                #if os(iOS)
                var folder = directory
                var attributes = URLResourceValues()
                attributes.isExcludedFromBackup = true
                try folder.setResourceValues(attributes)
                #endif
            }
            let file = directory.appendingPathComponent(String(Int64(time / 60)) + ".log")
            let row = "\(time)\t\(event)\n"
            if !FileManager.default.fileExists(atPath: file.path) {
                try Data(row.utf8).write(to: file, options: .atomic)
            } else if (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) >= Self.maxMinuteBytes {
                // Keep recent events available even when a subsystem floods the log within a minute.
                let rows = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
                let kept = rows.suffix(rows.count / 2).joined(separator: "\n")
                try Data((kept + "\n" + row).utf8).write(to: file, options: .atomic)
            } else {
                let fileHandle = try FileHandle(forWritingTo: file)
                defer { try? fileHandle.close() }
                try fileHandle.seekToEnd()
                try fileHandle.write(contentsOf: Data(row.utf8))
            }
            nextPruneAt = min(nextPruneAt, time + Self.retention)
        }

        mutating func recent(now: Date) throws -> String? {
            let current = now.timeIntervalSince1970
            try prune(now: current)
            var events: [(time: TimeInterval, event: Substring)] = []
            for (_, file) in try files() {
                for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                    let fields = line.split(separator: "\t", maxSplits: 1)
                    if fields.count == 2, let time = TimeInterval(fields[0]), time > current - Self.retention, time <= current {
                        events.append((time, fields[1]))
                    }
                }
            }
            guard !events.isEmpty else { return nil }
            events.sort { $0.time < $1.time }
            let timestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            return events.map { "\(timestamp.format(Date(timeIntervalSince1970: $0.time))) \($0.event)\n" }.joined()
        }

        mutating func clear() throws {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
            nextPruneAt = -.infinity
        }

        private mutating func prune(now: TimeInterval) throws {
            let cutoff = now - Self.retention
            let oldestBucket = Int64(cutoff / 60)
            var oldest: TimeInterval = .infinity
            for (minute, file) in try files() {
                if minute < oldestBucket {
                    try FileManager.default.removeItem(at: file)
                } else if minute == oldestBucket || !oldest.isFinite {
                    let rows = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
                    let kept = rows.filter { line in
                        guard let field = line.split(separator: "\t", maxSplits: 1).first,
                              let time = TimeInterval(field), time > cutoff else { return false }
                        oldest = min(oldest, time)
                        return true
                    }
                    if kept.isEmpty {
                        try FileManager.default.removeItem(at: file)
                    } else if kept.count != rows.count {
                        try Data((kept.joined(separator: "\n") + "\n").utf8).write(to: file, options: .atomic)
                    }
                }
            }
            nextPruneAt = oldest + Self.retention
        }

        private func files() throws -> [(Int64, URL)] {
            guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .compactMap { file in
                    guard file.pathExtension == "log", let minute = Int64(file.deletingPathExtension().lastPathComponent) else { return nil }
                    return (minute, file)
                }
                .sorted { $0.0 < $1.0 }
        }
    }
}
