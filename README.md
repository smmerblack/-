# BZAdBlocker test3

An injectable Objective-C dynamic library for suppressing startup
advertisements in iOS apps. This third test build combines a conservative
generic engine with profiles for:

- 新浪邮箱 3.3.16 (`com.sina`)
- 中国移动 12.x (`cn.10086.app`)

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
`TEST-CHECKLIST.md` for the two initial apps.

## Custom domains

Copy `Resources/BZAdBlockerRules.example.txt` to the root of the target app
bundle as `BZAdBlockerRules.txt`, replace the example entries with domain names,
and re-sign. Avoid first-party account or API domains.

## Scope and limitations

This is a source-complete test implementation, not the closed ad-blocking logic
from the upstream prebuilt binaries. App updates can change class names,
endpoints, and ad SDK behavior. Exact per-app tuning is most reliable when a
decrypted IPA or runtime log is available.
