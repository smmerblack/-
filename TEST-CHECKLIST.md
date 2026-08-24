# Test checklist

Use a clean copy of each app and keep the original IPA available for rollback.

## Baseline

- Device system: iOS 17.0
- Sina Mail: version 3.3.16, expected bundle ID `com.sina`
- China Mobile: version 12.5.2 (build `2607241316125200`), expected bundle ID
  `cn.10086.app`
- Taobao: version 10.59.20 (build `53695709`), expected bundle ID
  `com.taobao.taobao4iphone`
- Tencent Video: version 9.04.31 (build `25924`), expected bundle ID
  `com.tencent.live4iphone`
- Guazi Video: version 1.1 (build `1`), expected bundle ID
  `com.Tajjwab.numberPulse`
- Dylib: `BZAdBlocker.dylib`, arm64, minimum iOS 13.0
- Expected menu version: `0.10.0-test10`

## Test each app

1. Force-quit the app.
2. Launch once without the dylib and record the startup-ad duration.
3. Inject the dylib, re-sign the IPA, install it, and launch it three times.
4. Confirm the startup advertisement no longer appears or is skipped quickly.
5. For China Mobile, confirm its main tab appears without the former five-second
   white screen. Compare from tapping the icon until the main tab becomes
   interactive against both test5 and the reference dylib.
6. For Taobao, confirm the homepage becomes interactive without displaying an
   ad or leaving a five-second launch placeholder.
7. For Tencent Video, confirm the homepage becomes interactive without a
   startup ad or five-second blank/placeholder screen.
8. For Guazi Video, confirm the normal GUAZi brand loading screen may remain,
   but the full-screen “捕鱼王/无限暴击” advertisement never appears and the
   homepage becomes interactive near the former 3.5-second ad-start point,
   rather than after roughly 10.43 seconds from tapping the icon. These values
   restore the approximately one-second black segment trimmed from the test9
   screen recording; the advertisement itself lasted about 6.97 seconds.
   Confirm the “GUAZi × 1P游戏” popup is closed and the homepage promotion tiles
   labelled PG官方/开元棋牌/P直播/全国空降/新葡京/同城小姐/免费约妞 are no longer
   visible. Normal film cards, categories, search, playback, tabs, and account
   pages must remain usable.
9. Leave the app open for at least 30 seconds, switch to another app, wait five
   seconds, and return. Repeat three times and confirm the resume ad is skipped.
10. Confirm account login still works.
11. For Sina Mail, send and receive a test email and open an attachment.
12. For China Mobile, open balance, bill, recharge, order, and customer-service pages.
13. For Taobao, open search, product detail, cart, order, login, and payment
    handoff pages; also test one notification or product deep link.
14. For Tencent Video, play a normal video, pause it at least three times in
    portrait and full screen, and confirm no poster/video pause ad appears while
    the normal pause controls remain usable. Resume playback, seek, change
    clarity, test PiP/casting if available, and confirm playback remains normal.
15. Three-finger double-tap anywhere to open the settings panel.
16. Confirm **已触发跳过** or **已清理界面** increases when an ad is suppressed.
17. In China Mobile, confirm **当前规则** reads
    **中国移动 12.5.2 直接进入**.
18. In Taobao, confirm **当前规则** reads
    **淘宝 10.59.20 冷/热启动直跳**.
19. In Tencent Video, confirm **当前规则** reads
    **腾讯视频 9.04.31 开屏/返回/暂停广告直跳**.
20. In Guazi Video, confirm **当前规则** reads
    **瓜子影视 1.1 开屏/返回直跳 + 弹窗/首页清理**.
21. In China Mobile, confirm login state, privacy agreement on a clean install,
    app-update prompts, and push/deep-link launches still work; these flows must
    not be bypassed by the direct-entry hook.

## If a page fails

1. Open the panel and change **拦截强度** to **安全**.
2. Restart the app and test again.
3. If the issue remains, disable **广告请求拦截** while leaving **启动页清理** on.
4. Record the app version, failed page, and whether the ad returned.

Do not enable debug logging during normal use. When enabled, this test build logs
only blocked host names and class names, not request bodies, email content, or
account values.
