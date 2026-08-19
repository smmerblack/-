# Test checklist

Use a clean copy of each app and keep the original IPA available for rollback.

## Baseline

- Device system: iOS 17.0
- Sina Mail: version 3.3.16, expected bundle ID `com.sina`
- China Mobile: version 12.x, expected bundle ID `cn.10086.app`
- Dylib: `BZAdBlocker.dylib`, arm64, minimum iOS 13.0
- Expected menu version: `0.2.0-test2`

## Test each app

1. Force-quit the app.
2. Launch once without the dylib and record the startup-ad duration.
3. Inject the dylib, re-sign the IPA, install it, and launch it three times.
4. Confirm the startup advertisement no longer appears or is skipped quickly.
5. Confirm account login still works.
6. For Sina Mail, send and receive a test email and open an attachment.
7. For China Mobile, open balance, bill, recharge, order, and customer-service pages.
8. Three-finger double-tap anywhere to open the settings panel.
9. Confirm **已触发跳过** or **已清理界面** increases when an ad is suppressed.

## If a page fails

1. Open the panel and change **拦截强度** to **安全**.
2. Restart the app and test again.
3. If the issue remains, disable **广告请求拦截** while leaving **启动页清理** on.
4. Record the app version, failed page, and whether the ad returned.

Do not enable debug logging during normal use. When enabled, this test build logs
only blocked host names and class names, not request bodies, email content, or
account values.
