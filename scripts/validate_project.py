#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"validation error: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    required = [
        ROOT / "LICENSE",
        ROOT / "NOTICE.md",
        ROOT / "Makefile",
        ROOT / "Sources/BZAdBlocker/BZABBootstrap.m",
        ROOT / "Sources/BZAdBlocker/BZABCMCCBlocker.m",
        ROOT / "Sources/BZAdBlocker/BZABTaobaoBlocker.m",
        ROOT / "Sources/BZAdBlocker/BZABTencentVideoBlocker.h",
        ROOT / "Sources/BZAdBlocker/BZABTencentVideoBlocker.m",
        ROOT / "Sources/BZAdBlocker/BZABGuaziBlocker.h",
        ROOT / "Sources/BZAdBlocker/BZABGuaziBlocker.m",
        ROOT / "Sources/BZAdBlocker/BZABCore.m",
        ROOT / "Sources/BZAdBlocker/BZABNetworkBlocker.m",
        ROOT / "Sources/BZAdBlocker/BZABSDKBlocker.m",
        ROOT / "Sources/BZAdBlocker/BZABViewBlocker.m",
        ROOT / "Sources/BZAdBlocker/BZABMenuController.m",
        ROOT / "Sources/BZMenuKit/include/BZMenuKit.h",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        fail("missing required files: " + ", ".join(missing))

    objc_files = sorted((ROOT / "Sources").rglob("*.[mh]"))
    if len(objc_files) < 20:
        fail(f"expected BZMenuKit and blocker sources, found only {len(objc_files)} files")

    header_by_name: dict[str, list[Path]] = {}
    for header in (ROOT / "Sources").rglob("*.h"):
        header_by_name.setdefault(header.name, []).append(header)

    import_pattern = re.compile(r'^\s*#import\s+"([^"]+)"', re.MULTILINE)
    unresolved: list[str] = []
    for source in objc_files:
        text = source.read_text(encoding="utf-8")
        for imported in import_pattern.findall(text):
            if Path(imported).name not in header_by_name:
                unresolved.append(f"{source.relative_to(ROOT)} -> {imported}")
    if unresolved:
        fail("unresolved local imports: " + "; ".join(unresolved))

    blocker_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (ROOT / "Sources/BZAdBlocker").glob("*.[mh]")
    )
    for marker in [
        'NSString * const BZABVersion = @"0.9.0-test9"',
        '@"com.sina"',
        '@"cn.10086.app"',
        '@"com.taobao.taobao4iphone"',
        '@"com.tencent.live4iphone"',
        '@"com.Tajjwab.numberPulse"',
        '@"pangolin-sdk-toutiao.com"',
        '@"1rtb.com"',
        'recordTriggeredSkipWithClass',
        'UIApplicationWillEnterForegroundNotification',
        'BZABExtendSuppressionWindow',
        'BZABCurrentSuppressionGeneration',
        'CMStartViewController',
        'showADWithDataDict:videoUrlStr:',
        'showADWithData:videoPath:',
        'showADWithContentView:time:',
        'isNeedSkipStartAd',
        'addStartInitTimer',
        'skipStartViewAndEnterMainPage',
        'CMStartViewController.direct-entry',
        'TBBootImageManager',
        'showBootImageViewAtColdStart:',
        'skipBootImageViewAtColdStart:',
        'showBootImageViewAtHotStart',
        'isColdTaobaoSplashAdvWillShow',
        'isColdStartBootImageWillShow',
        'isHotStartTaobaoSplashAdvWillShow',
        'TBBootImageManager.cold-hot-native-skip',
        'QADSplashSDK',
        'shouldDisplaySplash',
        'enableHotLaunchSplashWithPIPState',
        'enableHotLaunchSplashWithBackgroundStayTime',
        'QADPauseViewController',
        'needBlockPauseRequest',
        'showView',
        'cancelPauseModel',
        'hiddenView',
        'QADPauseContainView',
        'showPauseItem:reportHandler:',
        'QADSplashSDK+QADPauseViewController.native-skip',
        'RCTTiming',
        'createTimer:duration:jsSchedulingTime:repeats:',
        'setTextStorage:contentFrame:descendantViews:',
        'RCTTiming.guazi-five-second-fast-forward',
        'duration >= 4500.0 && duration <= 6500.0',
        'forwardedDuration = 50.0',
        '@"关闭广告"',
        '@"PG官方"',
        '@"开元棋牌"',
        '@"全国空降"',
        '@"同城小姐"',
        '@"Guazi.popup-ad-overlay"',
        '@"Guazi.popup-react-close"',
        '@"Guazi.home-ad-tile"',
        'RCTTiming+Guazi.native-fast-path',
        'nativeFastPathReady',
        'numberOfTouchesRequired = 3',
        '__attribute__((constructor))',
    ]:
        if marker not in blocker_text:
            fail(f"expected marker not found: {marker}")

    for forbidden_marker in ['CydiaSubstrate', 'MSHookMessageEx', 'substrate.h']:
        if forbidden_marker in blocker_text:
            fail(f"unexpected runtime dependency: {forbidden_marker}")

    embedded_binaries = list(ROOT.rglob("*.dylib")) + list(ROOT.rglob("*.deb"))
    if embedded_binaries:
        fail("prebuilt binaries must not be embedded in source delivery")

    # A lightweight lexical balance check catches truncated patches without
    # pretending to replace an Objective-C compiler.
    pairs = {"(": ")", "[": "]", "{": "}"}
    for source in objc_files:
        text = source.read_text(encoding="utf-8")
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.DOTALL)
        text = re.sub(r"//.*?$", "", text, flags=re.MULTILINE)
        text = re.sub(r'@?"(?:\\.|[^"\\])*"', '""', text)
        stack: list[tuple[str, int]] = []
        for index, character in enumerate(text):
            if character in pairs:
                stack.append((character, index))
            elif character in pairs.values():
                if not stack or pairs[stack[-1][0]] != character:
                    fail(f"unbalanced token {character!r} in {source.relative_to(ROOT)}")
                stack.pop()
        if stack:
            fail(f"unclosed token {stack[-1][0]!r} in {source.relative_to(ROOT)}")

    print(
        f"validated {len(objc_files)} Objective-C files; "
        "profiles=com.sina,cn.10086.app,com.taobao.taobao4iphone,"
        "com.tencent.live4iphone,com.Tajjwab.numberPulse; version=0.9.0-test9"
    )


if __name__ == "__main__":
    main()
