//
//  DictationResultsView.swift
//  VocabMaster2
//
//  Created on 2026/02/11.
//

import SwiftUI
import SwiftData

struct DictationResultsView: View {
    @Bindable var session: DictationSession
    @StateObject private var audioService = AudioService.shared

    var body: some View {
        VStack(spacing: 16) {
            // 标题
            Text("听写答案")
                .font(.title2)
                .fontWeight(.bold)
                .padding()

            // 答案列表
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(session.words.enumerated()), id: \.element.id) { index, word in
                        DictationAnswerRow(
                            index: index + 1,
                            word: word,
                            audioService: audioService
                        )
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct DictationAnswerRow: View {
    let index: Int
    let word: Word
    @ObservedObject var audioService: AudioService

    var body: some View {
        HStack(spacing: 16) {
            // 序号
            Text("\(index)")
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(width: 30)

            // 音频播放按钮
            Button {
                audioService.play(relativePath: word.audioPath)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .foregroundColor(.blue)
                    .font(.title3)
            }

            // 单词
            Text(word.word)
                .font(.title3)
                .fontWeight(.medium)

            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
