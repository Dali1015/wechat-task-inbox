import SwiftUI

struct ContentView: View {
    @StateObject private var model = CaptureViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("微信任务收件箱")
                        .font(.title2.bold())
                    Text("在微信复制一条消息后，打开这里即可自动整理。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                statusCard

                Button {
                    Task { await model.processClipboard(allowDuplicate: true) }
                } label: {
                    Label("重新读取剪贴板", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)

                Spacer()

                Text("文字默认只在本机处理；定时提醒可在苹果日历中显示。")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await model.processClipboard()
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        Group {
            switch model.state {
            case .ready:
                Label("等待读取剪贴板中的微信消息", systemImage: "doc.on.clipboard")
                    .foregroundStyle(.secondary)
            case .processing:
                ProgressView("正在识别任务与时间…")
            case .saved(let task):
                VStack(alignment: .leading, spacing: 8) {
                    Label("已添加到提醒事项", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(task.title).font(.headline)
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            .font(.subheadline)
                    }
                    Text("识别方式：\(task.source.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .ignored(let message):
                Label(message, systemImage: "minus.circle")
                    .foregroundStyle(.secondary)
            case .duplicate:
                Label("这条剪贴板内容已经处理过。", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var isProcessing: Bool {
        if case .processing = model.state { return true }
        return false
    }
}
