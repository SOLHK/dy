import SwiftUI

struct DDReleaseNotesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("抖音折页").font(.title2.weight(.semibold))
                    Text(DDAppVersion.display).font(.subheadline).foregroundStyle(.secondary)
                    Text("原生短视频客户端，支持 iPhone 和 iPad。首版采用折页图标与深靛色频道栏，提供推荐、关注、直播、搜索和离线播放入口。")
                    Text("本项目基于 DouDuo 开发，由 SOLHK 独立维护。")
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ddBackground)
            .navigationTitle("本版说明")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }.accessibilityIdentifier("whatsnew.close")
                }
            }
        }
    }
}
