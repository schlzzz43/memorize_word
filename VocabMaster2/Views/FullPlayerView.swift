//
//  FullPlayerView.swift
//  VocabMaster2
//
//  Created on 2026/01/28.
//

import SwiftUI

/// 完整播放器视图
struct FullPlayerView: View {
    @ObservedObject var playlistService: PlaylistService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // 顶部拖动指示器
            dragIndicator
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 24) {
                    // 当前单词信息
                    currentWordInfo
                        .padding(.top, 20)

                    // 进度条
                    progressView

                    // 播放控制按钮
                    playbackControls
                        .padding(.vertical, 20)

                    // 播放内容选项
                    playbackContentSection

                    // 播放顺序选项
                    playbackOrderSection

                    // 其他选项
                    otherOptionsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(.systemBackground))
    }

    // MARK: - 拖动指示器
    private var dragIndicator: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)

            Button {
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "chevron.down")
                    Text("收起")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 当前单词信息
    private var currentWordInfo: some View {
        VStack(spacing: 12) {
            if let word = playlistService.currentWord {
                Text(word.word)
                    .font(.system(size: 36, weight: .bold))

                Text(word.pronunciation)
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text(word.meaning)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("未选择单词")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - 进度条
    private var progressView: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景轨道
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)

                    // 进度
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(playlistService.currentWordIndex + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text(playlistService.progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var progress: CGFloat {
        guard playlistService.playlist.count > 0 else { return 0 }
        return CGFloat(playlistService.currentWordIndex) / CGFloat(playlistService.playlist.count)
    }

    // MARK: - 播放控制
    private var playbackControls: some View {
        HStack(spacing: 30) {
            // 跳到第一个
            Button {
                playlistService.skipToFirst()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .foregroundColor(playlistService.canPlayPrevious ? .primary : .secondary.opacity(0.3))
            }
            .disabled(!playlistService.canPlayPrevious)

            // 上一个
            Button {
                playlistService.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundColor(playlistService.canPlayPrevious ? .primary : .secondary.opacity(0.3))
            }
            .disabled(!playlistService.canPlayPrevious)

            // 播放/暂停
            Button {
                togglePlayback()
            } label: {
                Image(systemName: playbackIcon)
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
            }

            // 下一个
            Button {
                playlistService.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundColor(playlistService.canPlayNext ? .primary : .secondary.opacity(0.3))
            }
            .disabled(!playlistService.canPlayNext)

            // 跳到最后一个
            Button {
                playlistService.skipToLast()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .foregroundColor(playlistService.canPlayNext ? .primary : .secondary.opacity(0.3))
            }
            .disabled(!playlistService.canPlayNext)
        }
    }

    private var playbackIcon: String {
        switch playlistService.playbackState {
        case .playing:
            return "pause.circle.fill"
        case .paused, .idle:
            return "play.circle.fill"
        }
    }

    private func togglePlayback() {
        switch playlistService.playbackState {
        case .playing:
            playlistService.pause()
        case .paused, .idle:
            playlistService.play()
        }
    }

    // MARK: - 播放内容选项
    private var playbackContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放内容")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(PlaybackContent.allCases, id: \.self) { content in
                    Button {
                        playlistService.playbackContent = content
                    } label: {
                        HStack {
                            Image(systemName: playlistService.playbackContent == content ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(playlistService.playbackContent == content ? .blue : .secondary)

                            Text(content.rawValue)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(playlistService.playbackContent == content ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                        )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 播放顺序选项
    private var playbackOrderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("播放顺序")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(PlaybackOrder.allCases, id: \.self) { order in
                    Button {
                        playlistService.playbackOrder = order
                        // 重新应用播放顺序
                        playlistService.reapplyPlaybackOrder()
                    } label: {
                        HStack {
                            Image(systemName: playlistService.playbackOrder == order ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(playlistService.playbackOrder == order ? .blue : .secondary)

                            Text(order.rawValue)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(playlistService.playbackOrder == order ? Color.blue.opacity(0.1) : Color(.secondarySystemBackground))
                        )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - 其他选项
    private var otherOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("其他选项")
                .font(.headline)

            VStack(spacing: 8) {
                Toggle(isOn: $playlistService.backgroundPlaybackEnabled) {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundColor(.blue)
                        Text("后台播放")
                            .foregroundColor(.primary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                )

                Toggle(isOn: $playlistService.autoPlayNext) {
                    HStack {
                        Image(systemName: "repeat")
                            .foregroundColor(.blue)
                        Text("自动播放下一个")
                            .foregroundColor(.primary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
        .padding(.vertical, 8)
    }
}
