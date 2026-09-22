# 0922 Render 재연결 긴급 계획

상태: **계획만** — 코드 수정·push는 지시 후  
문제: Render 대시보드에서 서비스를 바꿨어도, 약 자세히/홈은 앱에 **박힌 공개 URL**로만 간다. 대시보드 주소로는 앱이 안 붙는다.

---

## 왜 다른 서버로 보였나

앱은 `https://dashboard.render.com/web/srv-dap1i6rtqb8s73f0gdgg/deploys` 를 모른다.

약 자세히·홈·OCR 등록은 `ApiConfig.localFeatureBaseUrl` → 기본값 **`https://alkong-yakong-j0jn.onrender.com`**.

```
lib/core/network/api_config.dart
medicationFeatureBaseUrl = https://alkong-yakong-j0jn.onrender.com
localFeatureBaseUrl = LOCAL_API_BASE_URL 있으면 그것, 없으면 위 값
```

로그인 등 일부는 `ApiConfig.baseUrl` → Android 기본 **`https://alkong-yakong.onrender.com`** (팀 공용).

그래서 Render 쪽에서 서비스를 바꿔도, **앱을 그 공개 URL로 다시 빌드하지 않으면** 약 화면은 계속 j0jn을 친다. j0jn을 재시작해도 이 PC의 미push 코드는 안 올라간다.

---

## 0. 30초 확인 (지금 할 일)

[그 대시보드](https://dashboard.render.com/web/srv-dap1i6rtqb8s73f0gdgg) 연다.

적을 것 세 줄:

| 칸 | 어디서 보나 | 예 |
|---|---|---|
| 공개 URL | Settings 또는 서비스 헤더 | `https://????.onrender.com` |
| Git 브랜치 | Settings → Build & Deploy | `main` / `woong2` 등 |
| Auto-Deploy | 같은 화면 | On Commit 여부 |

그 공개 URL이 `alkong-yakong-j0jn.onrender.com`이면 **앱이 이미 그 서비스**다. 그때 화면이 안 바뀐 이유는 서버가 아니라 **GitHub에 이 워크트리 코드가 없음**이다. 재시작으로는 해결 안 됨.

공개 URL이 다르면 **앱이 엉뚱한 호스트를 하드코딩**한 것이다. 아래 1→2→3.

브라우저에서 공개 URL + `/health` 연다. 200이면 그 서버 살아 있음.

---

## 1. 앱을 그 Render 공개 URL에 붙인다

대상 파일: `lib/core/network/api_config.dart` 의 `medicationFeatureBaseUrl`.

- 대시보드 공개 URL이 `https://예시.onrender.com` 이면 그 값을 `medicationFeatureBaseUrl`에 넣는다.
- 임시만이면 코드 수정 없이:

```text
flutter run --dart-define=LOCAL_API_BASE_URL=https://대시보드공개URL
```

`LOCAL_API_BASE_URL`은 Render 환경변수가 아니다. **앱 빌드 때**만 먹는다. 이미 깔린 APK는 예전 주소 그대로다. 주소 바꾼 뒤에는 **앱을 다시 run / 재설치**.

약 자세히가 쓰는 클라이언트는 `user_medicines_controller.dart` 의 `ApiConfig.localFeatureBaseUrl`. 홈 today-medicines도 같다 (`medication_controller.dart`).

팀 공용 `productionBaseUrl` (`alkong-yakong.onrender.com`)은 로그인·챗봇용으로 남겨 둔 설계다. 약 자세히만 개인 Render로 가려면 `medicationFeatureBaseUrl`만 맞추면 된다. 약·로그인도 한 서버로 합칠지는 이번 긴급 범위에서 정하지 않는다.

---

## 2. 그 Render가 이 코드(홈~자세히)를 돌리게 한다

Render Auto-Deploy는 **GitHub에 push된 커밋**만 받는다. 로컬 미커밋 수정은 어떤 서비스를 재시작해도 안 간다.

순서:

1. 대시보드의 Git 브랜치가 뭔지 확인한다.
2. 그 브랜치에 홈~자세히 백엔드 변경을 커밋·push 한다. (push는 지시 후)
3. Deploys에 새 배포가 **Live** 될 때까지 기다린다. Restart만 하지 않는다.
4. 그 공개 URL로 `GET /api/v1/users/{id}/medicines/{프리마란코드}` 를 본다.
   - `explanation.treatment_uses` 첫 항목 title이 `알레르기로 인한 가려움`이면 새 코드다.
   - `treatment_uses`가 `[]`이고 본문이 `두드러기, 고초열, …`이면 아직 옛 배포다.

Render SQLite는 이 PC의 `alkongyakong.db`와 다른 파일이다. 배포 후에도 프로필이 옛 한 줄이면, 그 서버에서 `ensure_medicine_detail`이 다시 타야 한다. (배포 직후 한 번 약 자세히 조회로 생성되는 경로가 이미 있다.)

---

## 3. 앱에서 최종 확인

1. 1번으로 빌드한 앱을 연다.
2. 로그 `[API] ... baseUrl=` 이 대시보드 공개 URL과 같은지 본다. (`api_client.dart` 기동 로그)
3. 프리마란 약 자세히: `어떤 치료에 쓰이나요?`에 허가 쉼표 나열이 아니라 `알레르기로 인한 가려움` 제목이 나와야 한다.

안 나오면 앱 주소와 서버 배포 둘 중 하나가 아직 옛것이다. health와 medicines JSON을 같은 호스트로 다시 본다.

---

## 이번에 하지 않음

- 팀 공용 `alkong-yakong.onrender.com` 덮어쓰기
- 지시 없는 git push / 커밋
- OCR 확인 화면 추가 수정

---

## 한 줄

대시보드 공개 URL을 읽고 → 앱 `medicationFeatureBaseUrl`(또는 dart-define)을 그 URL로 맞추고 앱을 다시 돌리고 → 그 서비스가 보는 Git 브랜치에 코드를 push해서 **Deploy**한다. Restart만으로는 안 된다.
