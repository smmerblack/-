# BZAdBlocker test13

An injectable Objective-C dynamic library for suppressing startup
advertisements in iOS apps. This thirteenth test build combines a conservative
generic engine with profiles for:

- 新浪邮箱 3.3.16 (`com.sina`)
- 中国移动 12.5.2 (`cn.10086.app`)
- 淘宝 10.59.20 (`com.taobao.taobao4iphone`)
- 腾讯视频 9.04.31 (`com.tencent.live4iphone`)
- 瓜子影视 1.1 (`com.Tajjwab.numberPulse`)

The target test environment is iOS 17.0 with TrollStore or self-signed IPA
injection. The dylib itself supports iOS 13.0 and later.

## What it does

- Blocks requests to dedicated mobile-ad hosts through `NSURLProtocol`.
- Dynamically suppresses common startup-ad SDK entry points, including
  Meishu/MSAdSDK, Pangle/BU/PAG, GDT, Baidu, Kuaishou, and Sigmob-style splash
  classes when they are present at runtime.
- Searches the whole startup view tree for visible “跳过”/“Skip” controls and
  activates them even when the surrounding class name is obfuscated.
- Suppresses recognizable splash-ad views and presented view controllers during
  a bounded startup window.
- Reopens an 8-second suppression window whenever the app returns from the
  background, covering resume ads without continuously scanning normal pages.
- Allows reused skip controls and SDK objects to be handled once per suppression
  cycle instead of only once for the entire process lifetime.
- Uses China Mobile 12.5.2's current `showADWithData:videoPath:`,
  `isNeedSkipStartAd`, `addStartInitTimer`, and
  `skipStartViewAndEnterMainPage` flow. The normal home initialization starts
  first; on the next main-queue turn the app's own startup-completion method is
  invoked instead of waiting for the advertisement timeout.
- Never installs the generic network protocol, runtime SDK enumeration, or
  repeated view-tree scans inside version-specific dedicated targets. Blocking
  China Mobile's advertisement request was the cause of the visible blank
  timeout in test5. Unprofiled apps retain the full generic engine.
- Uses Taobao 10.59.20's own `TBBootImageManager` flow for both launch modes.
  Cold start is redirected from `showBootImageViewAtColdStart:` to
  `skipBootImageViewAtColdStart:`; a return from the background makes
  `showBootImageViewAtHotStart` return `NO` before any splash view or five-second
  timer is created.
- Keeps Taobao's `readyBootImageView` initialization intact and disables the
  generic request/UI engine only inside Taobao, avoiding both homepage breakage
  and a hidden-ad timeout.
- Uses Tencent Video 9.04.31's `QADSplashSDK` native decisions. Returning `NO`
  from `shouldDisplaySplash` makes the original cold-start flow execute its own
  no-ad completion immediately. Hot-start eligibility is declined through
  `enableHotLaunchSplashWithPIPState` and
  `enableHotLaunchSplashWithBackgroundStayTime`, so the original foreground
  flow exits without constructing a five-second splash or timeout.
- Blocks Tencent Video pause ads at
  `QADPauseViewController.needBlockPauseRequest`, before the pause-ad request or
  view is created. `QADPauseViewController.showView` and
  `QADPauseContainView.showPauseItem:reportHandler:` provide presentation-layer
  fallbacks without changing the normal video player's pause controls.
- Uses the Guazi Video 1.1 capture to block only `/App/Ad/*` and
  `/App/IndexList/homeFloatAd`, regardless of the rotating API hostname. Each
  match receives an immediate HTTP 200 business response with a non-success ad
  code, empty message, and no ad data. Keeping the message empty prevents the
  App from rendering the blocker response as a `no ad` toast. Other API paths,
  media cards, login, and homepage initialization remain untouched.
- The capture tied `/App/Ad/splashInfo` to the supplied 920×1994 full-screen
  splash and `/App/Ad/activityInfo` to the 1000×1380 popup. It also identified
  the app's ad config, banner, notice, vajra, skit, bars-index, and floating-home
  endpoints under the two exact path families above.
- Reverts test11's broad acceleration of 4.5–8.5 second new-architecture React
  Native timers, which could also match a normal homepage initialization timer
  and produce a black screen. test13 leaves object timers unchanged and keeps
  only the already-safe legacy millisecond fallback from test10.
- Restores test10's conservative React Native image geometry. Web and text
  cleanup remain narrow fallbacks for the supplied close text and homepage
  promotion labels.
- Closes Guazi's React Native popup advertisement and hides homepage promotion
  tiles only when at least two app-specific labels from the supplied sample are
  present. Single generic words such as “直播” or “更多” are not sufficient.
- Keeps Guazi on a dedicated path: only its exact captured ad paths use the URL
  protocol; generic domain/path heuristics, SDK enumeration, and broad
  class-name suppression are not installed in this app.
- Protects common login, mail, account, billing, payment, recharge, and order
  paths from first-party heuristic blocking.
- Provides BZMenuKit controls without a persistent floating button. Open the
  menu with a three-finger double-tap.
- Defaults to **平衡** mode. **安全** only blocks dedicated ad hosts and strongly
  identified ad UI. **增强** also blocks hosts with explicit ad subdomains.

## Build

Xcode with the iPhoneOS SDK is required. From Terminal on macOS:

```sh
./build.sh
```

The output is `build/BZAdBlocker.dylib`. The included GitHub Actions workflow
uses GitHub's `macos-26` runner so the iOS 26 glass API referenced by upstream
BZMenuKit is available while retaining an iOS 13 deployment target.

## Injection

Inject `BZAdBlocker.dylib` into a decrypted IPA using the TrollStore/self-signing
tool you already use, then let that tool re-sign the complete IPA. Do not inject
the upstream prebuilt `bzhelper` binaries into this project; this source tree is
standalone.

Start with the default **平衡** mode. If login, mail, billing, recharge, or other
core functions fail, switch to **安全** and restart the app. Follow
`TEST-CHECKLIST.md` for the five profiled apps.

For China Mobile, the version-specific direct-entry path is intentionally
limited to startup-ad suppression. Its generic network and UI scanners are not
installed, reducing launch overhead and avoiding advertisement-response timing
delays. The legacy `showADWithDataDict:videoUrlStr:` selector remains supported
for older China Mobile builds.

For Taobao, the dedicated path only changes the app's native splash display
decision. Account, shopping, payment, deep-link, privacy, update, and normal
homepage initialization paths are not bypassed.

For Tencent Video, the dedicated path changes only QAD splash eligibility and
pause-ad loading/presentation. Normal playback, manual pause/resume, player
controls, login, VIP, casting, download, PiP, and homepage initialization are
left on the app's original paths.

For Guazi Video, the dedicated path keeps React Native timers and homepage
initialization intact. Its request rules are intentionally tied to the semantic
ad paths observed in version 1.1 rather than to the currently selected API
hostname. If a future update changes those paths, the rule must be re-profiled
from a new capture.

## Custom domains

Copy `Resources/BZAdBlockerRules.example.txt` to the root of the target app
bundle as `BZAdBlockerRules.txt`, replace the example entries with domain names,
and re-sign. Avoid first-party account or API domains.

## Scope and limitations

This is a source-complete test implementation, not the closed ad-blocking logic
from the upstream prebuilt binaries. App updates can change class names,
endpoints, and ad SDK behavior. Exact per-app tuning is most reliable when a
decrypted IPA or runtime log is available.
