# 微信任务收件箱

一个不依赖快捷指令的 iPhone MVP：在微信复制文字后打开 App，它会读取剪贴板、识别是否存在待办和时间，并将任务写入 Apple 提醒事项。定时提醒可直接显示在 Apple 日历中。

## 使用体验

1. 在微信长按一条消息并复制。
2. 打开“微信任务收件箱”。
3. App 自动识别并保存；不确定的内容会用“[待确认]”标记保存。

消息只交给设备端 Apple Intelligence（可用时）或本地规则处理；本工程不上传文字，也没有 API Key。

## 在 iPhone 上运行

需要一台安装了 Xcode 和 iOS 26 SDK 或更高版本的 Mac。

1. 用 Xcode 打开 `WeChatTaskInbox.xcodeproj`。
2. 选中 `WeChatTaskInbox` target，在 **Signing & Capabilities** 选择你的开发团队，并把 Bundle Identifier 改成唯一值。
3. 连接 iPhone，选择真机后点 Run。
4. 首次打开时允许 App 访问“提醒事项”和粘贴板。

设备端 Apple Intelligence 可用时，App 会用它理解中文自然语言；否则仍可通过本地规则识别常见的“提交、回复、跟进、开会、明天、下周”等表达。

## 没有 Mac：免费侧载路线

这个工程已包含 GitHub Actions 工作流。将整个 `WeChatTaskInbox` 文件夹作为一个 GitHub 仓库推送后，在 GitHub 的 **Actions** 页面运行 `Build unsigned IPA`，即可下载 `WeChatTaskInbox-unsigned.ipa`。

该 IPA 没有开发者签名，专门供 SideStore 在你的 iPhone 上用免费 Apple 账户重新签名和安装。这样不需要 Apple Developer Program，也不需要 Mac。免费账户的限制是：最多 3 个活跃侧载 App，并且每 7 天需要在 SideStore 刷新一次签名。

安全提醒：Apple 账户只能在 SideStore 内由你本人登录，不要把密码或验证码发给任何人。

## 验收样例

复制以下文字后打开 App：

```
周五前把报价单发给客户
```

预期：创建一条标题为“把报价单发给客户”的提醒事项。

```
明天下午三点和客户开会，地点在国贸
```

预期：创建带有明天下午三点提醒时间的待办；在日历中打开“已计划提醒事项”后也能看到它。

## 当前边界

普通 iPhone App 不能读取微信通知或后台监听剪贴板，因此这版的最低操作是“复制消息、打开 App”。这是 iOS 的系统边界，不是 App 内部逻辑的限制。
