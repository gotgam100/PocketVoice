# PocketVoice MVP Prototype

`Pocket Voice / One Voice`의 iOS 17+ MVP 프로토타입입니다.

## Current Flow

- 앱에서 인물 최대 10명 등록 (카테고리: 가족, 친구, 연인, 동료, 반려, 최애)
- 인물별 이름, 사진, 최대 10초 음성 저장
- 녹음 직후 앱 안에서 다시 듣기
- 홈 화면 위젯에서 사진을 전체 배경으로 표시
- 위젯 설정에서 표시할 인물 선택
- 위젯의 ▶ 버튼을 누르면 앱을 열지 않고 바로 재생 (한 번 더 누르면 정지)

## Widget Playback

위젯 확장(extension)은 소리를 낼 수 없으므로, ▶ 버튼은 `PlayPersonVoiceIntent`(`AudioPlaybackIntent`)를 실행합니다. iOS가 이 Intent를 앱 프로세스에서 백그라운드로 실행해 재생합니다. 이를 위해:

- `Shared/PocketVoiceIntents.swift`는 앱과 위젯 두 타깃 모두에 포함되어야 합니다.
- 앱 `Info.plist`에 `UIBackgroundModes: audio`가 필요합니다.

위젯의 사진 부분을 누르면 기존처럼 앱이 열립니다.

## Files

- `PocketVoiceApp/ContentView.swift`: 인물 목록, 인물 등록/수정, 사진 꾸미기, 녹음(최대 10초), 설정
- `PocketVoiceApp/PocketVoiceApp.swift`: 앱 시작 설정
- `PocketVoiceWidget/PocketVoiceWidget.swift`: 사진 배경 위젯
- `Shared/PocketVoiceIntents.swift`: 인물 Entity, 위젯 설정 Intent, 재생 Intent
- `Shared/PocketVoiceShared.swift`: App Group 저장소, 인물 모델, 오디오 재생

## Project File

`project.yml`(XcodeGen)이 기준입니다. 파일을 추가하면 `xcodegen generate`로 `PocketVoice.xcodeproj`를 다시 만드세요.

## Device Test Steps

1. Xcode에서 `PocketVoiceApp` scheme으로 iPhone에 Run 합니다.
2. 앱에서 `+`를 눌러 인물을 추가합니다.
3. 이름 입력, 사진 선택, 녹음(최대 10초)을 진행합니다.
4. 저장 후 홈 화면에 `Pocket Voice` 위젯을 추가합니다.
5. 위젯을 길게 눌러 `위젯 편집`에서 인물을 선택합니다.
6. 위젯의 ▶ 버튼을 누릅니다.
7. 앱이 열리지 않고 홈 화면에서 목소리가 재생되는지 확인합니다. 다시 누르면 멈춰야 합니다.
