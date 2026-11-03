# 儲存／檔案／列印 現況審核

審核對象：`main` @ `14f9ce0`（v0.2.2）。方法：讀 `lib/data/document.dart`、`lib/main.dart`、`bin/tallynote.dart`、`pubspec.yaml`，並實際跑 CLI 與測試。

## 一句總結

**「不會失去你輸入的字」這部分是齊備的；「與外界交換檔案」這部分完全沒有。**
資料只存在 app 內部（SharedPreferences 一個 JSON blob），沒有檔案、沒有匯出、沒有匯入、沒有列印。

---

> 更新（2026-10-30 晚）：下面 P0–P2 已實作並推出 v0.3.0；P3（真正「檔案即文件」）仍未完成。
>
> 更新（2026-10-31，v0.3.1）：Web 版加入了自己的 service worker。實測：伺服器關閉之後
> 仍能重新開啟；輸入完畢後立即關閉分頁，重新開啟時內容仍在；寫入失敗（quota／私密視窗）時，狀態欄會顯示
> 「未儲存」，不會再誤報「已儲存」。

## 1. 逐項對照

| 你問的 | 狀態 | 實際情況 | 位置 |
|---|---|---|---|
| **儲存（保存進度）** | ✅ 齊全 | 停止輸入 400ms 後自動寫入；⌘/Ctrl+S 立即寫入；切換 sheet、app 進入背景、關閉前都會 flush | `main.dart` `_onText` / `_saveNow` / `_flush` / `didChangeAppLifecycleState` |
| | ✅ | 摺疊區塊時儲存**完整源文**，不會儲存摺疊後的投影 | `_contentToSave` |
| | ✅ | 損壞 JSON → 複製到 `tallynote.sheets.v1.bak`，`_keepBackup` 阻止覆寫 | `document.dart:150` |
| **格式（存成甚麼）** | ⚠️ 只有一種 | 內部 JSON：`{v:2, folders:[…], sheets:[{id,title,content,folderId,pinned,customTitle,updated}]}`；key `tallynote.sheets.v1` | `document.dart:168` |
| | ✅ | File → Export Markdown／CSV／純文字；`.tallynote` 檔案（同一 JSON schema，帶 app 標記） | — |
| **另存檔（Save As）** | ✅ 已做 | File → Save a copy… 存 `.tallynote`（file_picker，全平台） | ⌘/Ctrl+⇧D 複製一個新 sheet（標題加 `(copy)`），**不是檔案** | `document.dart` `duplicate()` |
| **開舊檔（外部檔案）** | ✅ 已做 | File → Open file… 匯入 `.tallynote`／`.json`，id 全部重新產生，不會覆寫 | 當時 GUI 完全沒有 import；只有 CLI `tallynote -f note.txt` 讀純文字逐行計算 | `bin/tallynote.dart:87` |
| **開新檔** | ⚠️ 只有「新 sheet」 | `⌘N` / 「New sheet」建立空白 sheet；沒有「新檔案」概念 | `main.dart` / `sidebar.dart` |
| **Print** | ✅ 已做 | File → Print / PDF…（printing + pdf，A4、等寬、答案右對齊） | 沒有 `printing`/`pdf` 依賴、沒有任何列印或輸出 PDF 路徑 | — |
| **備份／還原** | ⚠️ 只完成一半 | 只有「壞檔自動 .bak」；沒有手動「匯出備份」「匯入備份」 | `document.dart:150` |
| **多檔／工作區** | ❌ | 所有 sheet 放在同一個 store，沒有「一個檔案 = 一組 sheet」 | — |
| **匯率快取** | ✅ | `tallynote.rates.v1` + `tallynote.rates.date.v1` | `rates.dart` |

### 一個要指出的落差

最初的設計筆記（`~/.hermes/cache/scratch/tallynote-design.md`，不在 repo）寫「local JSON files with `.tallynote` extension」，但**實作從頭到尾都是 SharedPreferences，沒有任何檔案**。repo 內沒有任何文件再提及 `.tallynote`，所以現時沒有互相矛盾的文件，只有「尚未完成的承諾」。要麼補上實作（P3），要麼在 roadmap 明確寫「檔案格式暫緩」。

---

## 2. 建議（按「不會後悔」排序）

| 優先 | 做甚麼 | 為何先做 | 估時 |
|---|---|---|---|
| **P0** | **匯出／匯入 JSON 備份**（`tallynote-backup-2026-10-30.json`，全部 sheet + folders） | 唯一能救「換機／重裝」的功能；不用改動架構，讀寫同一個 payload | 半日 |
| **P1** | **匯出 Markdown / CSV**（唯讀快照，CSV 每行 `line,answer`） | 純文字、零依賴，桌面已可用；貼到報告／Excel 即可使用 | 一日 |
| **P2** | **Print → PDF**（`printing` + `pdf`，A4、等寬字、保留答案欄） | 所需的列印；同一條路徑順便做「匯出 PDF」 | 一日 |
| **P3** | 真 `.tallynote` 檔案（開啟／另存） | 需要 `file_picker`，並訂定檔案格式，以及與 prefs 並存的策略（建議：prefs 存「最近」，檔案存「專案」） | 兩日 |

**平台注意**
- `share_plus`（手機分享）／`file_picker`（開啟檔案）／`printing` 都是平台 plugin：Android 直接；Windows/Linux 桌面要 XDG portal 或 zenity，Linux 要加依賴；Web 用 anchor download + `Printing.layoutPdf`。
- macOS／iOS 不在範圍內，所以不用處理 share sheet。

---

## 3. 明確不建議

- 不要把所有 sheet 變成一個個檔案（會令「打開 app 就能立即輸入」變慢，亦要處理檔案同步衝突）。
- 不要做雲端同步（與離線定位衝突）。
- 不要做「自動備份到某資料夾」——用戶不知道何時寫入、何時刪除；寧願手動一鍵匯出。

---

## 4. 驗證方法

- CLI：`dart run bin/tallynote.dart -f <file>`（讀檔）、`echo "1+1" | …`（stdin）
- 儲存：`flutter test test/save_safety_test.dart test/storage_hardening_test.dart`（5 個測試覆蓋 fold-save、跨 sheet debounce、lifecycle flush、壞檔 .bak）
- 全套：`flutter analyze` + `flutter test` → 84 tests
