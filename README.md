# VocabMaster2

A native iOS vocabulary learning app built with SwiftUI and SwiftData, supporting English and Japanese vocabulary learning through spaced repetition and multi-mode testing.

## Features

- **Three study modes**: Learn new words, review old words, random test
- **Four test types**: Spelling, meaning (4-choice), listening, audio-meaning
- **Spaced repetition**: State machine tracking (unlearned → reviewing → mastered)
- **Exercise sets**: Dictation mode with session tracking
- **Audio playback**: Word pronunciation with background playback and remote controls
- **Vocabulary books**: Organize word collections, import via WiFi upload (ZIP format)
- **Statistics**: Study metrics, error analysis, progress visualization
- **Word lookup**: In-app dictionary lookup
- **Theme support**: Light / Dark mode

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift |
| UI | SwiftUI |
| Persistence | SwiftData |
| Architecture | MVVM |
| Reactive | Combine |
| Audio | AVFoundation |
| Minimum iOS | 18.2 |

## Project Structure

```
VocabMaster2/
├── Models/              # SwiftData models
│   ├── Vocabulary.swift         # Vocabulary collection
│   ├── Word.swift               # Individual word
│   ├── WordState.swift          # Learning progress state
│   ├── StudyRecord.swift        # Study session history
│   ├── ExerciseSet.swift        # Exercise set container
│   ├── Exercise.swift           # Individual exercise
│   ├── ExerciseRecord.swift     # Exercise history
│   ├── TestMode.swift           # Test mode enum
│   └── AppSettings.swift        # User preferences (UserDefaults)
│
├── Services/            # Business logic
│   ├── StudyService.swift           # Study orchestration, task generation
│   ├── StudySessionManager.swift    # Session lifecycle
│   ├── VocabularyService.swift      # Vocabulary CRUD and word import
│   ├── AudioService.swift           # AVAudioPlayer wrapper
│   ├── PlaylistService.swift        # Background playback, remote controls
│   ├── ExerciseService.swift        # Exercise session logic
│   ├── ExerciseImportService.swift  # Exercise set import
│   ├── StatisticsService.swift      # Study metrics calculation
│   ├── WordRecognitionService.swift # Speech-to-text
│   ├── WordLookupService.swift      # Dictionary lookup
│   ├── VocabularyBookService.swift  # Vocabulary book management
│   ├── WiFiUploadService.swift      # HTTP server for vocab import (port 8080)
│   ├── StudyRecordExportService.swift # Export study history
│   └── ZIPUtility.swift             # ZIP archive operations
│
├── Views/               # SwiftUI views
│   ├── HomeView.swift               # Landing page, quick-start, progress
│   ├── StudySessionView.swift       # Main study interface
│   ├── VocabularyListView.swift     # Vocabulary management
│   ├── WordListView.swift           # Filterable word list
│   ├── WordDetailView.swift         # Word detail with audio
│   ├── ExerciseSetListView.swift    # Exercise set browser
│   ├── ExerciseSessionView.swift    # Exercise session UI
│   ├── DictationModeView.swift      # Dictation exercise
│   ├── DictationResultsView.swift   # Dictation results
│   ├── StatisticsView.swift         # Charts and metrics
│   ├── SettingsView.swift           # User preferences
│   ├── FullPlayerView.swift         # Full audio player
│   ├── MiniPlayerView.swift         # Mini player overlay
│   ├── PlayerTabView.swift          # Player tab container
│   ├── WiFiUploadView.swift         # Network vocab transfer
│   ├── VocabularyBookListView.swift # Vocabulary book browser
│   ├── VocabularyBookDetailView.swift
│   ├── WordLookupPopover.swift
│   ├── SafariView.swift
│   └── Components/                  # Reusable UI components
│
├── Utilities/
│   └── RandomUtility.swift
│
├── Resources/           # Audio assets (not in version control)
└── Assets.xcassets/
```

## Building

Open `VocabMaster2.xcodeproj` in Xcode and run. No external dependencies.

```bash
# Build for simulator
xcodebuild -project VocabMaster2.xcodeproj \
  -scheme VocabMaster2 \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

## Vocabulary Import Format

Import vocabularies via WiFi upload (ZIP file containing a text file):

```
word|pronunciation|part of speech, meaning|example1|translation1|example2|translation2|...
```

Example:
```
apple|/ˈæpl/|n. 苹果|I eat an apple.|我吃一个苹果。|The apple is red.|这个苹果是红色的。
```

The ZIP may also include MP3 audio files organized as:
```
Audio/[Vocabulary Name]/[word].mp3
Audio/[Vocabulary Name]/[word]_1.mp3   # Example 1
Audio/[Vocabulary Name]/[word]_2.mp3   # Example 2
```

## Learning State Machine

```
unlearned ──pass──► reviewing ──N consecutive correct──► mastered
              ▲         │                                     │
              └─ fail ──┘◄──────────── fail ─────────────────┘
```

- N (mastery threshold) is configurable (default: 3)
- Failures reset the consecutive correct counter
- Mastered words re-enter the review queue on failure

## Key Settings

| Setting | Default | Range |
|---------|---------|-------|
| Daily learning count | 20 | 5–100 |
| Random test count | 10 | 5–50 |
| Mastery threshold (N) | 3 | 1–10 |
| Error statistics Top N | 10 | 5–20 |
