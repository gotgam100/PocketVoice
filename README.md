# PocketVoice MVP Prototype

`Pocket Voice / One Voice`의 iOS 17+ MVP 프로토타입입니다.

## Current Flow

- 앱에서 인물 최대 10명 등록
- 인물별 이름, 사진, 3초 음성 저장
- 녹음 직후 앱 안에서 다시 듣기
- 홈 화면 위젯에서 사진을 전체 배경으로 표시
- 위젯 설정에서 표시할 인물 선택
- 위젯 탭 시 앱 미니 플레이어가 열리고 자동 재생

위젯 안에서 직접 오디오를 재생하는 방식은 실기기에서 소리가 나지 않아 제외했습니다. MVP는 `위젯 탭 -> 앱 미니 플레이어 -> 자동 재생` 방식입니다.

## Files

- `PocketVoiceApp/ContentView.swift`: 인물 목록, 인물 등록/수정, 사진 선택, 3초 녹음, 미니 플레이어
- `PocketVoiceApp/PocketVoiceApp.swift`: `pocketvoice://play?person=...` URL 처리
- `PocketVoiceWidget/PocketVoiceWidget.swift`: 사진 배경 위젯과 인물 선택 설정
- `Shared/PocketVoiceShared.swift`: App Group 저장소, 인물 모델, 위젯 설정 Intent, 오디오 재생

## Device Test Steps

1. Xcode에서 `PocketVoiceApp` scheme으로 iPhone에 Run 합니다.
2. 앱에서 `+`를 눌러 인물을 추가합니다.
3. 이름 입력, 사진 선택, `3초 녹음`을 진행합니다.
4. 저장 후 홈 화면에 `Pocket Voice` 위젯을 추가합니다.
5. 위젯을 길게 눌러 `위젯 편집`에서 인물을 선택합니다.
6. 위젯을 탭합니다.
7. 앱 미니 플레이어가 열리고 선택한 인물의 목소리가 자동 재생되는지 확인합니다.

## Known iOS Limitation

미니 플레이어의 `닫기` 버튼은 앱 안의 인물 목록으로 돌아갑니다. iOS 공개 API로 앱에서 사용자를 홈 화면으로 보내거나 앱을 자연스럽게 종료하는 기능은 제공되지 않습니다.
