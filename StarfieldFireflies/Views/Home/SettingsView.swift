import SwiftUI

struct SettingsView: View {
    @AppStorage("sessionDuration") private var sessionDuration = 5
    @AppStorage("masterVolume") private var masterVolume = 0.7
    @AppStorage("binauralVolume") private var binauralVolume = 0.5
    @AppStorage("ambientVolume") private var ambientVolume = 0.6
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("audioFeedbackEnabled") private var audioFeedbackEnabled = true

    var body: some View {
        Form {
            audioSection
            trainingSection
            accessibilitySection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        .frame(width: 450, height: 520)
    }

    private var audioSection: some View {
        Section("音频") {
            VStack(alignment: .leading, spacing: 4) {
                Text("主音量")
                Slider(value: $masterVolume, in: 0...1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("双脑同步音波")
                Slider(value: $binauralVolume, in: 0...1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("环境音效")
                Slider(value: $ambientVolume, in: 0...1)
            }

            Toggle("音频反馈", isOn: $audioFeedbackEnabled)
        }
    }

    private var trainingSection: some View {
        Section("训练") {
            Picker("训练时长", selection: $sessionDuration) {
                Text("3 分钟").tag(3)
                Text("5 分钟").tag(5)
                Text("8 分钟").tag(8)
                Text("10 分钟").tag(10)
            }
            .pickerStyle(.segmented)
        }
    }

    private var accessibilitySection: some View {
        Section("辅助功能") {
            Toggle("减少动效", isOn: $reduceMotion)
            Toggle("触觉反馈", isOn: $hapticsEnabled)
        }
    }

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0.0 (Demo)")
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://example.com/research")!) {
                HStack {
                    Text("SSVEP 注意力训练研究")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
