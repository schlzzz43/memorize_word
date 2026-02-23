//
//  ContentView.swift
//  VocabMaster2
//
//  Created by 沈晨晖 on 2026/01/24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var settings = AppSettings.shared
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(0)

            VocabularyListView()
                .tabItem {
                    Label("词库", systemImage: "books.vertical.fill")
                }
                .tag(1)

            PlayerTabView()
                .tabItem {
                    Label("播放器", systemImage: "play.circle.fill")
                }
                .tag(2)

            ExerciseSetListView()
                .tabItem {
                    Label("习题", systemImage: "doc.text.fill")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .preferredColorScheme(settings.themeMode.colorScheme)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Vocabulary.self, Word.self, WordState.self, StudyRecord.self, ExerciseSet.self, Exercise.self, ExerciseRecord.self], inMemory: true)
}
