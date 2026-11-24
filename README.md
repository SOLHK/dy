# 抖音 · SOLHK 测试版

基于 [DouDuo](https://github.com/81199000/DouDuo) 开发的第三方 iOS / iPadOS 客户端，支持 iOS / iPadOS 26.0 及以上。应用使用独立的图标和 Bundle ID `com.solhk.dy`，由 SOLHK 维护，与抖音官方无关联。

SwiftUI 界面提供推荐、关注、搜索、收藏、评论和直播入口。播放器使用 AVPlayer，部分媒体由 VLCKit 播放。需要登录的功能使用应用内的抖音网页会话，实际可用性取决于平台支持和账号状态。数据处理见[隐私说明](PRIVACY.md)。

## 构建和安装

在装有 Xcode 27.1 或更新版本的 macOS 上，先下载并校验播放器依赖，再打开工程。

```sh
sh scripts/fetch-vlckit.sh
open DouDuo.xcodeproj
```

选择 `DouDuo` scheme。真机运行前在 Signing & Capabilities 中选择自己的开发团队。仓库的 GitHub Actions 提供 `DY-unsigned` 构建产物，解压后需用自己的证书和描述文件为 IPA 签名，再安装到对应设备。

## 源码来源

基于 DouDuo 提交 [`2bd2b2c`](https://github.com/81199000/DouDuo/commit/2bd2b2c8c16b6b2848c5266e109e051343d1fe05)。保留 DouDuo contributors 的 [MIT 版权声明及许可](LICENSE)。播放器依赖的许可和源码地址见 [MobileVLCKit 声明](Vendor/VLCKit/NOTICE.txt)。
