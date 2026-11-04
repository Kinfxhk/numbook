# Numbook · 記事計數簿

**The notepad that adds up.** Every line you type is a calculation; the answer sits on the right, aligned by its decimal point.
**會計算的記事簿。** 輸入一行即計算一次，答案排在右邊，小數點自動對齊。

Offline first: nothing is computed in the cloud, and the page works with the network unplugged.
離線優先：不經雲端計算，拔掉網線仍然可用。

**[Open the web app · 開網頁版](https://kinfxhk.github.io/numbook/)** · **[All downloads · 全部下載](https://github.com/Kinfxhk/numbook/releases/latest)** · **[Buy Me a Coffee](https://buymeacoffee.com/kinfxhk)**

The web app is installable: in Chrome or Edge, **Install Numbook** puts it in the Dock and it opens with the network unplugged. Notes are stored on the device, and closing the tab never loses the last line — the status bar shows *editing…* until the write lands.
網頁版可以安裝：在 Chrome／Edge 選擇「安裝 Numbook」即可加入 Dock，離線也能開啟。資料存在本機，關閉分頁不會失去最後一行 —— 狀態欄會顯示 *editing…* 直到寫入完成。

<img src="docs/screenshot-desktop-zh.png" alt="Numbook desktop: a monthly budget note with answers aligned on the decimal point">

## Interface · 介面

- **Sidebar · 側欄** — folders, an unfiled group, search across titles and note bodies, pin and long-press menus. / 資料夾、未分類組、跨標題與內文搜尋、釘選與長按選單。
- **Editor · 編輯區** — one plain text area with line numbers; every line is evaluated as you type. / 一個純文字編輯區加行號，輸入時即時計算。
- **Answer column · 答案欄** — right-aligned, decimal-aligned, user-sized (drag the splitter, or double-tap to auto-fit). / 右對齊、小數點對齊，可以拖曳調整寬度，雙擊自動貼合最長答案。
- **Status bar · 狀態欄** — lines · answers · save state · rate date. One home for save state, never a pop-up card. / 行數、答案數、儲存狀態、匯率日期；儲存狀態只在一處顯示，不會彈出卡片遮住內容。
- **Header · 頂欄** — exactly two buttons: sheets menu and settings. Every switch lives in a tabbed settings dialog (Appearance / Editor / Data / Cheat sheet). / 只有兩個按鈕：記事選單與設定；所有開關收在分頁設定（外觀／編輯／資料／計算表）。

<p>
<img src="docs/screenshot-desktop-en-dark.png" width="49%" alt="Numbook dark theme in English: Tokyo trip note with tagged totals">
<img src="docs/screenshot-mobile.png" width="24%" alt="Numbook on a phone: same note, answers still aligned">
</p>

Dark theme, English interface and a phone layout are the same build — three languages (English / 繁體中文 / 简体中文) ship in the app and follow the system locale.
深色主題、英文介面、手機排版都是同一個 build；介面內建三種語言（English／繁體中文／简体中文），預設跟隨系統語言。

## Why it's different · 功能優勢

**1. Offline is a correctness constraint, not a feature bullet.**
No network call can change or block an answer. The only optional fetch is the daily exchange rate, and it can be switched off — the page then makes zero external requests.
**離線是正確性約束，不是賣點口號。** 沒有任何網絡請求可以改變或阻擋答案。唯一可選的網絡行為是每日匯率，關閉後即零外部請求。

**2. Chinese is native input, not a translation layer.**
`打八折 480` → 384, `八五折 200` → 170, `分帳 3 人 380` → 126.666666667, `合共` / `總共` / `加` `減` `乘` `除` `的` `百分之幾` all work next to English syntax.
**中文是原生輸入，不是翻譯層。** 打八折、分帳、合共、加減乘除、的、百分之幾，可與英文語法混用。

**3. Totals built for a balance sheet.**
`sum` per section, `total` / `grand total` / `合共` across the whole note, `total of #tag` for tagged lines. Subtotals are recognised as summaries, so nothing is counted twice.
**小計為資產負債表而設。** 每節 `sum`、全頁 `total`／`grand total`／`合共`、`total of #tag` 按標籤加總；小計會被當成摘要，不會重複計算。

**4. Every answer can be explained.**
Press the chevron beside a complex answer and it shows each operation in order. When a line is ambiguous the app shows nothing rather than a guess (an uppercase `X` is not a times sign).
**每個答案都可以解釋。** 複雜答案旁邊有箭頭，逐項列出運算；含糊的行寧願不答，不會亂猜（大寫 `X` 不當乘號）。

**5. One engine, five delivery targets.**
The engine is pure Dart with no Flutter imports, so the same rules run on Android, Windows, Linux and the web — and compile to a single CLI binary for scripts and agents.
**一個引擎，五個交付方式。** 引擎是純 Dart、不依賴 Flutter，同一套規則運行於 Android、Windows、Linux、Web，還可以編譯成單一 CLI binary，供 script 與 agent 使用。

**6. The cheat sheet cannot lie.**
Settings → Cheat sheet (計算表) lists every word you can type with the answer it really gives — and a test evaluates every row, so the page cannot drift away from the engine.
**計算表不會說錯。** 設定 → 計算表列出所有可以輸入的字與真正答案，而且有測試逐行驗算，頁面不會偏離引擎。

## What it does · 功能

```
rent = 2500                    →  2,500
food = 400                     →  400
rent + food                    →  2,900

# Trip to Tokyo
flights = 4,280 #trip          →  4,280
hotel 3 × 850 #trip            →  2,550
total of #trip                 →  6,830

100 USD in HKD                 →  HK$780.00
5 kg + 3 lb                    →  6.36077711 kg
25% off 159.99 + 10% tax       →  131.99175
9 is to 16 as 27 is to what    →  48
2026-10-30 + 2 weeks           →  13 November 2026
3pm HKT in New York            →  30 October 2026 at 3:00 AM
6+3x30                         →  96
30乘3                           →  90
```

**Calculating · 計算**
- Line-by-line answers; a broken line never breaks the page. A blank line is spacing, not a section break: `total` still counts the lines above it. / 逐行答案，壞了一行不會拖垮整頁；空行只是間距，`total` 仍然計算上面所有行。
- Variables (`rent = 2500`), references (`prev`, `line 3`), `sum` / `average` / `count` per section. / 變數、引用（`prev`、`line 3`）、每節 `sum`／`average`／`count`。
- Percentages in plain words: `15% of 300`, `25% off 159.99`, `20 is what % of 80`, `5% of what is 150`, plus Chinese retail forms. / 口語百分比，加中文零售寫法。
- Remainders: `7 % 2` or `10 mod 3` → 1 (a `%` with a number after it is never a percentage). / 餘數；`%` 後面有數字就是取餘，不會當成百分比。
- Scale words: `1.5 million + 200 thousand` → 1,700,000; `$30/day is what per year` → $10,950.00. / 數量級字眼與年化。
- Units (length, mass, area, volume, speed, time, data, angle, temperature); mixed units convert on the fly. / 單位換算，混合單位即時轉換。
- Currency with daily ECB rates, cached for offline use. / 貨幣使用 ECB 每日匯率，快取後離線仍可使用。
- Dates, durations and time zones: `today + 3 workdays`, `2026-10-31 - 2026-01-01` → 303 days, `3pm HKT in New York`. / 日期、時長、時區。
- `if … then … else`; rule of three; compound interest; scientific notation (`1e3`). / 條件式、三數法、複利、科學記數。
- Functions in any shape people type them: `sin 30 deg`, `sin30deg`, `max(1, 9, 4)`, `round 3.14159 2`, `pi`. / 函數無論怎樣輸入都能識別。

**Totals that suit a balance sheet · 資產負債表式小計**

```
# Assets
cash 500,000                   →  500,000
stocks 300,000                 →  300,000
sum                            →  800,000

# Liabilities
mortgage -500,000              →  -500,000
cards -20,000                  →  -20,000
sum                            →  -520,000

合共                             →  280,000
```

`total` / `sum` can be used inside an expression too (`total * 7.8 + 16000`), and money plus a plain number is read in that currency.
`total`／`sum` 亦可放入算式（`total * 7.8 + 16000`）；金額加上純數字時，會沿用該貨幣。

**Reading real-world notes · 讀真實筆記**
- `Topstep: −$10,408.52` — the label stays out of the maths, the unicode minus keeps its sign, money keeps its cents. / 標籤不會進入算式，unicode 負號保留，金額保留仙位。
- `// any line` becomes a draft: greyed, not calculated. / `//` 開頭變為草稿：變灰、不計算。
- `**bold**`, `_italic_`, `~~strike~~`, `__underline__`, `{red}colour{/}` — select text and use the small format bar; markers are plain text, so the file stays portable and the maths still works. / 格式標記是純文字，檔案仍然便於攜帶，計算仍然運行。

**Workspace · 工作區**
- Folders in the sidebar, with an unfiled group for everything else. / 側欄資料夾，其餘歸「未分類」。
- Search across titles and note bodies; folders flatten while a query is active. / 搜尋標題與內文；有搜尋字時資料夾會攤平。
- Long-press a sheet to move or delete it; long-press a folder to rename or delete it — deleting a folder keeps its sheets. / 長按記事可移動或刪除；長按資料夾可改名或刪除 —— 刪除資料夾不會刪除記事。

**Answers you can trust · 可信答案**

```
(2.5+7.5)*1.11/10-15^2
    2.5 + 7.5 = 10
    10 * 1.11 = 11.1
    11.1 / 10 = 1.11
    15 ^ 2 = 225
    1.11 - 225 = -223.89
```

**Shortcuts · 快捷鍵** — `⌘/Ctrl+S` save (flushed, with visible confirmation), `⇧S` strikethrough, `⇧D` duplicate, `B`/`I`/`U` wrap, `F` search, `W` close tab, `N` new sheet, `\` sidebar, `⇧A` answers, `+`/`-`/`0` zoom, `Ctrl/⌘ + wheel` or trackpad pinch to zoom the whole layout (100–200 %).
`⌘/Ctrl+S` 儲存（即時寫入並顯示確認）、`⇧S` 刪除線、`⇧D` 複製記事、`B`／`I`／`U` 套用格式、`F` 搜尋、`W` 關閉分頁、`N` 新記事、`\` 側欄、`⇧A` 答案、`+`／`-`／`0` 縮放、`Ctrl/⌘ + 滾輪` 或觸控板捏合縮放整個版面（100–200%）。

## Install · 下載

| Platform · 平台 | Download · 檔案 | Notes · 說明 |
|---|---|---|
| Android | `app-release.apk` | signed with the release key · 用 release key 簽署 |
| Windows | `Tallynote-<version>-setup.exe` | per-user install, Start-menu shortcut, uninstaller · 單用戶安裝、開始選單捷徑、解除安裝 |
| Windows (portable) | `tallynote-windows.zip` | unzip and run `tallynote.exe` · 解壓即用 |
| Linux | `tallynote_<version>_amd64.deb` | installs to `/usr/lib/tallynote` with a desktop entry · 安裝到 `/usr/lib/tallynote`，並加入桌面捷徑 |
| Linux (portable) | `tallynote-linux.tar.gz` | unpack and run `bundle/tallynote` · 解壓即用 |
| Web | [kinfxhk.github.io/numbook](https://kinfxhk.github.io/numbook/) | deployed from `main`, installable as a PWA · 由 `main` 部署，可安裝成 PWA |
| macOS / iOS | not yet · 尚未 | needs a full Xcode install · 需要完整的 Xcode |
| Linux / Windows arm64 | not yet · 尚未 | Flutter publishes no arm64 host SDK (flutter/flutter#114349) · Flutter 尚未提供 arm64 host SDK |

Every release also ships `SHA256SUMS.txt`; the version is in the file names above as `<version>`.
每個 release 都附 `SHA256SUMS.txt`；上面 `<version>` 的位置就是版本號。

Binary names still carry the old `tallynote` prefix (installer, `.deb` package, executable) on purpose: renaming them breaks the sign-in/update path of existing installs, so they change in one coordinated packaging pass, not here.
執行檔名仍然沿用舊 `tallynote` 前綴（安裝程式、`.deb` 包名、執行檔）：改名會斷開現有安裝與更新路徑，所以留待下一次整體打包改動才處理。

## From the command line · 命令列

The engine is pure Dart, so it also compiles to a single binary — handy for scripts and agents:
引擎是純 Dart，可以編譯成單一 binary，方便 script 與 agent：

```bash
dart compile exe bin/tallynote.dart -o build/tallynote
./build/tallynote "5 kg + 3 lb"
./build/tallynote -f budget.txt --json --total --strict
```

`--json` returns `value` (typed) alongside `display`; `--strict` turns off the human-friendly guessing so a broken line is an error. See [docs/agents.md](docs/agents.md) for the agent/MCP plan.
`--json` 會同時回傳 `value`（帶型別）與 `display`；`--strict` 關閉人性化猜測，壞行即報錯。Agent／MCP 計劃見 [docs/agents.md](docs/agents.md)。

## Design principles · 設計原則

1. **Offline is correct.** No network call can change an answer. The only optional fetch is the daily rate refresh, and it can be switched off in Settings. / **離線即正確。** 沒有網絡請求可以改變答案；唯一可選的是每日匯率更新，可在設定中關閉。
2. **One meaning, one trigger.** A word belongs to exactly one feature; the precedence ladder and a machine-checked trigger registry keep new features from colliding. / **一個意思，一個觸發。** 每個字只屬於一個功能；優先次序表與機器檢查的觸發登記防止新功能互相衝突。
3. **No answer beats a wrong answer.** / **不答勝過答錯。**

## Build · 建置

```bash
flutter pub get
flutter test
flutter run -d android     # or linux, windows, chrome
flutter build apk --release
flutter build web --release --base-href /numbook/ --no-web-resources-cdn
```

Windows needs the **Desktop development with C++** workload:
Windows 需要 **Desktop development with C++** 工作負載：

```powershell
winget install --id Microsoft.VisualStudio.2022.BuildTools -e --silent `
  --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
flutter build windows --release
```

`--no-web-resources-cdn` matters: CanvasKit is served from the bundle, so opening the page touches no CDN. CI builds Android, Linux, Windows and Web on every push; the Windows `tallynote.exe` in the release was built and run natively on Windows 11.
`--no-web-resources-cdn` 有作用：CanvasKit 由 bundle 提供，開啟頁面不會接觸 CDN。每次 push，CI 都會建置 Android、Linux、Windows、Web；release 內的 Windows `tallynote.exe` 是在 Windows 11 原生建置並運行過。

## Release · 發佈（macOS App Store）

`tools/release.py` 用 App Store Connect API 自動化上架流程。前置條件：

1. `~/.hermes/secrets/numbook-asc/` 有 API key（p8，權限必須是 **App Manager**，在 App Store Connect › Users and Access 檢查）與 `config.json`。
2. Xcode 已登入 Apple ID（`upload`／`full` 用 Xcode 的 session 上傳，API key 只處理 metadata 與 TestFlight）。
3. 密鑰檔案只放本機，chmod 700 目錄／600 檔案，勿提交。

```bash
python3 tools/release.py status            # 查看最新 builds
python3 tools/release.py build             # flutter analyze/test/build + xcodebuild archive（不上傳）
python3 tools/release.py upload --archive build/Numbook-asc.xcarchive
python3 tools/release.py wait              # 等最新 build 離開 PROCESSING
python3 tools/release.py compliance        # 宣告無非豁免加密
python3 tools/release.py add-to-group      # 最新 VALID build 加入 KinFx 內部測試群組
python3 tools/release.py full              # build → upload → wait → compliance → add-to-group
```

每日 09:00 的 Hermes cron `numbook-release-watch` 跑 `release.py watch`：有新 build 需要宣告合規或分發時才發通知，冇事就靜默。TestFlight 安裝新 build 仍需人手在 TestFlight app 撳一下（或開啟 TestFlight 自動更新）；macOS 冇 CLI 可以代撳。

## License · 授權

MIT. Tallynote is an independent implementation of the notepad-calculator idea, and is not affiliated with any commercial notepad calculator.
MIT。Tallynote 是記事計算機概念的獨立實作，與任何商業記事計算機無關聯。
