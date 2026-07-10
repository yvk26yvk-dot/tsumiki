#!/bin/bash
# アプリ資産を www/ に集めて cap sync する。
# sw.js は除外(WKWebViewはService Worker非対応。index.html側もNATIVEガード済み)
set -e
cd "$(dirname "$0")/.."
rm -rf www && mkdir www
cp index.html supabase.min.js manifest.json www/
cp kotei-normal.png kotei-care.png kotei-cheer.png kotei-body.png icon-192.png icon-512.png www/
npx cap sync ios
