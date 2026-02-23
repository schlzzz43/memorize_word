//
//  VocabMaster2App.swift
//  VocabMaster2
//
//  Created by 沈晨晖 on 2026/01/24.
//

import SwiftUI
import SwiftData

@main
struct VocabMaster2App: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Vocabulary.self,
            Word.self,
            WordState.self,
            StudyRecord.self,
            ExerciseSet.self,
            Exercise.self,
            ExerciseRecord.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // 初始化播放服务以设置音频会话和远程控制
        _ = PlaylistService.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
