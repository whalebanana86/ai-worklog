# 이걸내가 브랜드

| 언어 | 이름 | 부제 |
|---|---|---|
| 한국어 | 이걸내가 | AI와 함께한 일 |
| English | I Did That? | What I did with AI |
| 日本語 | これ、私が？ | AIと一緒にやったこと |

## 서비스 설명

**한국어**

이걸내가는 Claude Code·Codex·LM Studio와 함께한 작업을 날짜와 프로젝트별로 모아 보는 맥 앱입니다.
요청, 답변, 고친 파일과 AI 요약을 돌아보며 내가 해낸 일을 발견하세요.

짧은 소개: **흩어진 AI 작업 기록을 모아, 내가 해낸 일을 발견하는 맥 앱.**

**English**

I Did That? gathers your work with Claude Code, Codex and LM Studio by date and project.
Look back at prompts, replies, changed files and AI summaries to rediscover what you accomplished.

Short description: **A Mac app to gather your AI work and rediscover what you accomplished.**

**日本語**

これ、私が？は、Claude Code・Codex・LM Studioと一緒に行った作業を、日付とプロジェクト別にまとめるMacアプリです。
依頼、回答、変更したファイル、AIの要約を振り返り、自分が成し遂げたことを再発見できます。

短い紹介: **散らばったAIとの作業記録をまとめ、自分が成し遂げたことを再発見するMacアプリ。**

## アイコン / 아이콘

![앱 아이콘](app-icon.png)

말풍선은 “내가 이걸 했다고?”라는 발견, 큰 체크는 해낸 일, 작은 느낌표는 새삼스러운 놀라움을 나타냅니다.
파랑 `#3156E8`, 크림 `#FFF8E8`, 체크 `#2549D6`, 코랄 `#FF956E`를 사용합니다.
글자 없는 도형으로 작은 Dock·Finder 아이콘에서도 읽히게 구성했습니다.

- 원본: `scripts/make_icon.swift` (AppKit/Core Graphics로 재현 가능)
- 배포용: `Support/AppIcon.icns` (16–1024px)
- 미리보기: `docs/brand/app-icon.png` (512px)

```bash
swift scripts/make_icon.swift build.noindex/brand
python3 scripts/compress_icon.py build.noindex/brand/AppIcon.iconset Support/AppIcon.icns
cp build.noindex/brand/AppIcon.iconset/icon_512x512.png docs/brand/app-icon.png
```

앱 이름 변경 후에도 bundle ID `local.aiworklog`, 실행 파일 `AIWorkLog`, 저장 폴더 `AIWorkLog`,
GitHub 저장소 주소는 호환성을 위해 유지합니다. 저장된 기록·설정과 업데이트 확인이 이어집니다.
