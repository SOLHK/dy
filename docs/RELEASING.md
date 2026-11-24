# 构建与测试包

项目在 GitHub Actions 的 iOS build 工作流中编译和打包。每次提交到 main 会生成一份未签名的 iPhoneOS IPA 及其 SHA-256 文件。仓库成员可从运行记录中的 DyZheye-unsigned 下载。

在 Mac 本地构建时，先用 sh scripts/fetch-vlckit.sh 下载并校验依赖，再打开 DouDuo.xcodeproj。自签安装请使用对应的 Apple 开发签名与设备配置。

软件版本与构建号在 project.yml 和 Xcode 工程的构建设置中维护。
