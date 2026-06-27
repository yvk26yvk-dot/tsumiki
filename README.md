# つみき — 構成と公開手順

「きょうの自分をすこしだけ認める」アプリ。日々のアクション記録（A）と週次のふりかえり（C）。

## ファイル構成

```
index.html      アプリ本体（UI + ロジック）
manifest.json   PWA設定（ホーム画面に追加できる）
sw.js           オフライン動作（Service Worker）
icon-192.png    アイコン
icon-512.png    アイコン
```

## データ層の設計（重要）

`index.html` 内の `store` オブジェクトが **データ層を完全に隔離** しています。
いまは localStorage に保存していますが、将来 Supabase 等のクラウドDBへ移行する際は、
**この `store` の中身だけ差し替えれば UI 側は無変更** で済みます。

```
store.getDay(dateKey)        → その日の記録を取得
store.saveDay(dateKey, data) → その日の記録を保存
store.recent(7)              → 直近7日ぶんを取得
```

これが「A→C→B」をスムーズに繋ぐための土台です。

---

## A：いますぐ Web公開する

静的サイトなので、以下のどれでも数分で公開できます（無料）。

1. このフォルダを GitHub リポジトリに置く
2. 下記のどれかに連携 →自動で本番URLが出ます
   - **Cloudflare Pages**（おすすめ・高速）
   - **Vercel**
   - **Netlify**
   - **GitHub Pages**
3. 公開後、スマホで開き「ホーム画面に追加」→ アプリのように起動

### 公開前に足すもの（一般公開の最低限）
- プライバシーポリシー（記録＝個人的内容なので必須）
- 簡単な利用規約・説明ページ
- 独自ドメイン（任意）

---

## C：設計を固める（App Store を見据えて）

Web版で反応を見たら、ここで本番設計に移ります。

### 1. クラウドDB移行（Supabase 推奨）
App Store に出すなら localStorage だけでは「機種変で記録が消える」。
`store` をクラウドDB版に差し替える。ログイン（メール / Sign in with Apple）を追加。

### 2. ネイティブ化（Capacitor）
いまの Web コードを **そのまま iOS アプリの殻に包む**。
```
npm install @capacitor/core @capacitor/cli
npx cap init つみき com.yourname.tsumiki
npx cap add ios
npx cap copy
npx cap open ios   # Xcode が開く
```

### 3. アプリならではの機能（審査対策）
- プッシュ通知でやさしくリマインド（毎晩「きょうの記録を残しませんか」）
- ウィジェット・ヘルスケア連携など
※「Webサイトを薄くアプリ化しただけ」は審査で弾かれやすいので、独自価値が要る。

### 4. 提出に必要なもの
- Apple Developer Program（年 99 USD）
- App Store 用スクリーンショット・説明文・アイコン
- プライバシー表示（App Privacy）の入力

---

## B：中身を磨く
アクションリストの内容（いまは 3 Good Things・セルフコンパッション中心）を、
対象ユーザーに合わせて練り込む。審査でも独自価値として効く。
