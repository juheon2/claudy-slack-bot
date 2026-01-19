# claudy-slack-bot-hook (DM용 Slack Bot 통합 버전)  

## 개요

`claudy-slack-bot-hook`는 Claude Code 세션에서 일정 시간 입력이 없을 때, 마지막 대화 맥락을 요약해 Slack으로 알림을 보내는 후크입니다. **Slack Bot API**를 사용해 특정 사용자에게 DM으로 알림을 전송하도록 개발되었습니다.

## 디렉터리 구조

* `.claude-plugin/plugin.json` – 플러그인 메타데이터
* `hooks/hooks.json` – 후크 이벤트 정의
* `scripts/start-timer.sh` – 후크 입력을 저장하고 타이머 프로세스를 시작
* `scripts/cancel-timer.sh` – 기존 타이머를 종료
* `scripts/alarm.sh` – 대화 내용을 파싱하여 Slack DM으로 알림을 전송
* `scripts/parse-transcript.sh` – Claude Code의 transcript를 파싱하여 마지막 사용자 요청, 어시스턴트 응답, 질문, TODO 상태 등을 추출

## 동작 원리

1. **타이머 시작**: Claude Code가 사용자 입력을 기다리는 상태(`idle_prompt`)가 되면 `Notification` 훅이 `start-timer.sh`를 호출합니다. 후크 입력이 임시 파일에 저장되고, 지정된 지연 시간(기본 30초)만큼 대기하는 백그라운드 프로세스가 시작됩니다.
2. **타이머 취소**: 사용자가 메시지를 입력하면 `UserPromptSubmit` 훅이 `cancel-timer.sh`를 실행하여 대기 중인 타이머 프로세스를 종료합니다.
3. **알림 전송**: 지연 시간 동안 입력이 없으면 백그라운드 프로세스가 `alarm.sh`를 호출합니다. 이 스크립트는 `parse-transcript.sh`를 통해 대화 내용을 파싱하고, Slack Bot API를 사용하여 지정된 사용자에게 DM으로 메시지를 전송합니다.
4. **DM 전송 로직**: `alarm.sh`는 `conversations.open` API를 호출하여 대상 사용자와의 DM 채널을 열고, 얻은 채널 ID에 `chat.postMessage` API를 사용해 메시지를 전송합니다.

## 설치 및 설정

### 1. 설치

```bash
# repo clone (실행 권한 포함)
git clone https://github.com/juheon2/claudy-slack-bot.git ~/claudy-slack-bot
```

#### 전역 설정 (모든 프로젝트에 적용)

`~/.claude/settings.json` 파일에 hooks 설정을 추가합니다.

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/your-username/claudy-slack-bot/scripts/start-timer.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/your-username/claudy-slack-bot/scripts/cancel-timer.sh"
          }
        ]
      }
    ]
  }
}
```

#### 프로젝트별 설정 (특정 프로젝트에만 적용)

프로젝트 루트에 `.claude/hooks.json` 파일을 생성합니다.

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "idle_prompt",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/your-username/claudy-slack-bot/scripts/start-timer.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/your-username/claudy-slack-bot/scripts/cancel-timer.sh"
          }
        ]
      }
    ]
  }
}
```

> ⚠️ 경로의 `/Users/your-username/`을 실제 경로로 변경하세요. `echo $HOME`으로 확인 가능합니다.

### 2. Slack Bot 준비

1. Slack 앱을 생성하고 Bot User를 추가합니다. (https://api.slack.com/apps)
2. OAuth & Permissions > **Bot Token Scopes**에서 `chat:write`와 `im:write` 권한을 부여합니다.
3. Install App 메뉴에서 앱을 워크스페이스에 재설치하여 **Bot Token(xoxb-…)** 을 얻습니다.
4. Claude가 DM을 보내길 원하는 사용자의 **User ID**(예: `U12345678`)를 확인합니다.

### 3. 환경변수 설정

다음 환경변수를 `~/.claude/.env` 파일에 설정하거나, 쉘에서 export합니다.

```bash
SLACK_BOT_TOKEN=xoxb-...           # Slack Bot Token
SLACK_USER_ID=U12345678            # 알림 받을 사용자 ID
CLAUDE_ALARM_DELAY=60              # 알림 대기 시간 (초, 기본값: 30)
```

## 사용법

hooks 설정 후 Claude Code를 사용하다가 일정 시간 입력이 없으면, 다음과 같은 정보를 포함한 DM을 Slack에서 받을 수 있습니다.

* 마지막 사용자 요청 (필요 시 앞뒤 일부만 표시)
* Claude의 마지막 응답
* Claude가 답변을 기다리고 있는 질문(AskUserQuestion)
* 열린 TODO 항목의 진행 상태 (완료/진행중/대기)

이 알림을 통해 다른 작업을 하다가도 현재 진행 중인 Claude Code 세션의 맥락을 빠르게 파악할 수 있습니다.

## 참고

* Slack API 호출 시 오류가 발생하면 알림이 전송되지 않을 수 있으므로, 토큰 권한과 사용자 ID가 올바른지 확인하세요.
