//
//  MiniPlayerView.swift
//  VocabMaster2
//
//  Created on 2026/01/28.
//

import SwiftUI

/// 迷你播放器视图
struct MiniPlayerView: View {
    @ObservedObject var playlistService: PlaylistService
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 左侧：单词信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(.blue)

                        if let word = playlistService.currentWord {
                            Text(word.word)
                                .font(.headline)
                                .foregroundColor(.primary)
                        } else {
                            Text("未选择单词")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }

                        Text("(\(playlistService.progressText))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let word = playlistService.currentWord {
                        Text(word.meaning)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 右侧：播放/暂停按钮
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: playbackIcon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 0)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: -2)
    }

    private var playbackIcon: String {
        switch playlistService.playbackState {
        case .playing:
            return "pause.fill"
        case .paused, .idle:
            return "play.fill"
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
}
