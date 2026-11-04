# App Store listing — Numbook (macOS) 0.5.2

App Store Connect 貼上用的稿。主語言：繁體中文。

## 基本資料

| 欄位 | 值 |
|---|---|
| 名稱（30 字內） | Numbook |
| 副標題（30 字內） | 會計算的記事簿 |
| Bundle ID | app.tallynote.tallynote（與 Android applicationId 一致，可做 Universal Purchase） |
| SKU | numbook-mac-1 |
| 版本 | 0.5.2（build 22） |
| 類別 | 生產力工具（public.app-category.productivity） |
| 價格 | 待定（見下面定價） |
| 版權 | © 2026 KinFx |
| 年齡分級 | 4+ |
| 私隱政策 URL | https://kinfxhk.github.io/numbook/privacy.html |
| 支援 URL | https://kinfxhk.github.io/numbook/support.html |
| 營銷 URL | https://kinfxhk.github.io/numbook/ |

## 描述（zh-Hant）

> 一行一個算式，答案就在右邊。Numbook 是記事簿，也是一部計算機：
> 打「機票 2 * 4380」，右邊即刻出 8,760；打「總計」，整段自動加總。

**為甚麼用記事簿的方式計數**
- 每一行都可以是算式，也可以只是文字；文字行不會打斷計算
- `# 標題` 分段，`總計` 加總該段，`total of #標籤` 加總有標籤的行
- 變數與引用：`租金 = 12500`，之後打 `租金 * 12` 就得
- 單位與貨幣：`3 kg`、`18600 JPY`，需要時自動換算（歐洲央行參考匯率）
- 日期：`days until 2026-12-25` 直接答日數
- 中文零售寫法：`八折`、`分帳 3 人 1200`

**桌面版的特點**
- 側欄記事列表＋資料夾＋搜尋；分頁同時開幾份記事
- 答案欄可拖拉調寬，雙擊自動對齊最長的答案
- 匯出 CSV／PDF、列印；整個記事可匯出再匯入
- 全部快捷鍵（⌘S 儲存、⌘F 搜尋、⌘N 新記事、⌘+/- 縮放、⌘, 設定）

**離線與私隱**
- 沒有帳號，記事只存在你的 Mac 上
- 唯一網絡連線是匯率（可關閉；關閉後完全離線）
- 不需要「輔助使用」權限，不改 SIP，不收集任何資料

## 關鍵字（100 字元內）

```
計算機,記事簿,計算,算數,notepad,calculator,Soulver,Numi,預算,分帳,匯率,離線
```

## 截圖（1280×800）

1. `docs/appstore/01-editor-1280x800.png` — 編輯器＋答案欄（繁中示範）

拍攝方法：`flutter build macos --release` → 開 app → `screencapture -l` 取窗口 →
`app/Assets/make-shots.swift`（macfeel repo）合成 1280×800。示範內容由 app 自己的
SharedPreferences 寫入，畫面是真 app 渲染，不是重繪。

## App Review 備註

> Numbook 是一個記事簿形式的計算機。所有記事存在使用者本機（app 沙盒內的
> SharedPreferences），不上傳、沒有帳號。
>
> 唯一網絡用途是選擇性的匯率更新：向 api.frankfurter.app 取歐洲央行參考匯率，
> 請求只帶日期與貨幣代碼，不含任何使用者資料；使用者可在設定關閉，關閉後 app 完全不連網。
> 已啟用 App Sandbox + `com.apple.security.network.client`，沒有其他 entitlement。

## 定價（建議，待你決定）

一次性買斷（用戶偏好，不用訂閱）：
- 香港區 HK$48；其他區等值（US$5.99 / NT$180）
- 免費試用方式：App Store 不支援試用期，若要試用就用免費版限 3 份記事（未實作）

## 未做（刻意）

- iOS 版：`ios/` target 未建立（`flutter create --platforms=ios .` 即可），
  而且有一個已知缺陷要先修 —— 手機上兩位數行號會被裁（`editorMetrics` 的 gutter 22px），
  這是 skill 內標明阻擋 iOS 上架的一項。
- 商店文案的英文版：現有 README 已有英文段落，可直接改寫成英文 listing。
