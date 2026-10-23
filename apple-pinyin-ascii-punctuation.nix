# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PinyinASCII contributors
#
# Home Manager 模块：Apple 拼音原生半角标点 + 全局 ANSI 键位补充转换。
# 用法：imports = [ ./apple-pinyin-ascii-punctuation.nix ];
#       services.apple-pinyin-ascii-punctuation.enable = true;
# 需要 macOS 的辅助功能授权；不读取正文、组词范围或输入源。
# 普通 []-= 始终原样通过；按美式物理键位补充原生遗漏的符号。
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.apple-pinyin-ascii-punctuation;
  # 完整许可随单个模块、生成的 C 源码和 App 一起分发，不改变导入方仓库的许可。
  licenseText = ''
    MIT License

    Copyright (c) 2026 PinyinASCII contributors

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
  '';
  # Apple 原生半角处理逗号、句号、括号等；这里只补它遗漏的 11 个字符。
  # 每项依次为普通、Shift 字符，空格表示原样通过；普通数字和 []-= 不拦截。
  keyMap = {
    ANSI_4 = " $";
    ANSI_6 = " ^";
    ANSI_Minus = " _";
    ANSI_LeftBracket = " {";
    ANSI_RightBracket = " }";
    ANSI_Backslash = "\\ ";
    ANSI_Quote = "'\"";
    ANSI_Comma = " <";
    ANSI_Period = " >";
    ANSI_Grave = "` ";
  };
  source = pkgs.writeText "pinyin-ascii.c" ''
    /*
    ${licenseText}
    */
    #include <ApplicationServices/ApplicationServices.h>
    #include <Carbon/Carbon.h>
    #include <assert.h>
    #include <stdio.h>

    /* 按 Apple ANSI 虚拟键位定义映射，未适配其他符号布局；未列出的键不转换。 */
    enum { KEYCODE_COUNT = 128 };

    static const char symbolsByKeyCode[KEYCODE_COUNT][3] = {
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (key: value: "[kVK_${key}] = ${builtins.toJSON value},") keyMap
      )}
    };

    /* 纯策略：只补原生遗漏符号；不查询组词状态，普通 []-= 永远不在转换表中。 */
    static UniChar asciiSymbol(unsigned key, CGEventFlags flags) {
      CGEventFlags shortcuts = kCGEventFlagMaskCommand | kCGEventFlagMaskControl |
                               kCGEventFlagMaskAlternate | kCGEventFlagMaskSecondaryFn;
      if (key >= KEYCODE_COUNT || (flags & shortcuts)) return 0;
      char value = symbolsByKeyCode[key][(flags & kCGEventFlagMaskShift) != 0];
      return value == ' ' ? 0 : (unsigned char)value;
    }

    /* 使用独立私有事件源，而不是复制原事件的路由及输入法元数据。
       保留物理键码供 Apple 拼音解释分音；ASCII 字符已确定，清除 Shift 等修饰。
       该路径参考 Tail Input；定向合成输入与实体键盘仍需分别验证。 */
    static CGEventRef eventWithSymbol(CGEventRef original, UniChar value) {
      CGEventSourceRef source = CGEventSourceCreate(kCGEventSourceStatePrivate);
      if (!source) return NULL;
      CGKeyCode key = (CGKeyCode)CGEventGetIntegerValueField(original, kCGKeyboardEventKeycode);
      CGEventRef result = CGEventCreateKeyboardEvent(source, key, true);
      CFRelease(source);
      if (result) {
        CGEventKeyboardSetUnicodeString(result, 1, &value);
        CGEventSetFlags(result, 0);
        CGEventSetTimestamp(result, CGEventGetTimestamp(original));
        CGEventSetIntegerValueField(result, kCGKeyboardEventAutorepeat,
          CGEventGetIntegerValueField(original, kCGKeyboardEventAutorepeat));
      }
      return result;
    }

    static CFMachPortRef eventTap;

    /* 只替换按下事件；所有抬键、候选翻页键和快捷键直接返回原对象。
       Quartz 接管新事件的所有权；创建失败则放行，不重发事件、不维护配对状态。 */
    static CGEventRef handleKeyboardEvent(CGEventTapProxy proxy, CGEventType type,
                                          CGEventRef event, void *context) {
      (void)proxy;
      (void)context;
      if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        if (eventTap && CFMachPortIsValid(eventTap) && AXIsProcessTrusted())
          CGEventTapEnable(eventTap, true);
        return event;
      }
      if (type != kCGEventKeyDown) return event;
      UniChar value = asciiSymbol(
        (unsigned)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode), CGEventGetFlags(event));
      CGEventRef result = value ? eventWithSymbol(event, value) : NULL;
      return result ? result : event;
    }

    #ifdef TEST
    /* 测真实回调的对象身份和字节内容；透传不能悄悄改成内容相同的新事件。 */
    static void checkKeyEvent(CGEventType type, CGKeyCode key, CGEventFlags flags, UniChar expected) {
      CGEventRef original = CGEventCreateKeyboardEvent(NULL, key, type == kCGEventKeyDown);
      assert(original);
      CGEventSetFlags(original, flags);
      CGEventSetTimestamp(original, 123456);
      CGEventSetIntegerValueField(original, kCGKeyboardEventAutorepeat, 1);
      CGEventSetIntegerValueField(original, kCGEventSourceUserData, 0x50494e59);
      CFDataRef before = CGEventCreateData(NULL, original);
      assert(before);
      CGEventRef result = handleKeyboardEvent(NULL, type, original, NULL);
      if (expected) {
        UniChar value = 0;
        UniCharCount length = 0;
        assert(result && result != original);
        CGEventKeyboardGetUnicodeString(result, 1, &length, &value);
        assert(length == 1 && value == expected);
        assert(CGEventGetType(result) == kCGEventKeyDown && CGEventGetFlags(result) == 0);
        assert(CGEventGetIntegerValueField(result, kCGKeyboardEventKeycode) == key);
        assert(CGEventGetTimestamp(result) == CGEventGetTimestamp(original));
        assert(CGEventGetIntegerValueField(result, kCGKeyboardEventAutorepeat) == 1);
        assert(CGEventGetIntegerValueField(result, kCGEventSourceUserData) == 0);
        int64_t state = CGEventGetIntegerValueField(result, kCGEventSourceStateID);
        assert(state != kCGEventSourceStateCombinedSessionState && state != kCGEventSourceStateHIDSystemState);
        CFRelease(result);
      } else assert(result == original);
      CFDataRef after = CGEventCreateData(NULL, original);
      assert(after && CFEqual(before, after));
      CFRelease(after);
      CFRelease(before);
      CFRelease(original);
    }

    int main(void) {
      /* 独立键位样例防止左右括号或 Shift 映射互换仍通过字符集合测试。 */
      const struct { CGKeyCode key; bool shift; UniChar value; } cases[] = {
        { kVK_ANSI_4, true, '$' }, { kVK_ANSI_6, true, '^' },
        { kVK_ANSI_Minus, true, '_' }, { kVK_ANSI_LeftBracket, true, '{' },
        { kVK_ANSI_RightBracket, true, '}' }, { kVK_ANSI_Backslash, false, '\\' },
        { kVK_ANSI_Quote, false, 0x27 }, { kVK_ANSI_Quote, true, 0x22 },
        { kVK_ANSI_Comma, true, '<' }, { kVK_ANSI_Period, true, '>' },
        { kVK_ANSI_Grave, false, 0x60 }
      };
      for (unsigned key = 0; key <= KEYCODE_COUNT; key++) {
        for (unsigned shift = 0; shift < 2; shift++) {
          UniChar expected = 0;
          CGEventFlags flags = shift ? kCGEventFlagMaskShift : 0;
          for (unsigned i = 0; i < sizeof cases / sizeof *cases; i++)
            if (cases[i].key == key && cases[i].shift == (bool)shift) expected = cases[i].value;
          assert(asciiSymbol(key, flags) == expected);
          checkKeyEvent(kCGEventKeyDown, key, flags, expected);
          checkKeyEvent(kCGEventKeyUp, key, flags, 0);
          CGEventFlags shortcuts[] = { kCGEventFlagMaskCommand, kCGEventFlagMaskControl,
                                      kCGEventFlagMaskAlternate, kCGEventFlagMaskSecondaryFn };
          for (unsigned i = 0; i < sizeof shortcuts / sizeof *shortcuts; i++) {
            checkKeyEvent(kCGEventKeyDown, key, flags | shortcuts[i], 0);
            checkKeyEvent(kCGEventKeyUp, key, flags | shortcuts[i], 0);
          }
        }
      }
      /* 普通翻页键无论重复、抬键或组合修饰都不允许被替换。 */
      const CGKeyCode navigation[] = { kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket,
                                      kVK_ANSI_Minus, kVK_ANSI_Equal };
      for (unsigned i = 0; i < sizeof navigation / sizeof *navigation; i++) {
        checkKeyEvent(kCGEventKeyDown, navigation[i], 0, 0);
        checkKeyEvent(kCGEventKeyDown, navigation[i], 0, 0);
        checkKeyEvent(kCGEventKeyUp, navigation[i], kCGEventFlagMaskCommand, 0);
      }
      assert(handleKeyboardEvent(NULL, kCGEventTapDisabledByTimeout, NULL, NULL) == NULL);
      assert(handleKeyboardEvent(NULL, kCGEventTapDisabledByUserInput, NULL, NULL) == NULL);
      puts("PASS: 11 supplemental symbols, raw navigation, native symbols, shortcuts, key-up and private events");
      return 0;
    }
    #endif

    #ifndef TEST
    /* 等待用户授权后启动；失权或端口失效时清理，恢复后重新连接。
       不替用户授予权限，仅记录服务启动状态，不记录按键。 */
    static void updateEventTap(CFRunLoopTimerRef timer, void *context) {
      (void)timer;
      (void)context;
      bool trusted = AXIsProcessTrusted();
      if (eventTap && (!trusted || !CFMachPortIsValid(eventTap))) {
        CGEventTapEnable(eventTap, false);
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = NULL;
      }
      if (eventTap) {
        if (!CGEventTapIsEnabled(eventTap)) CGEventTapEnable(eventTap, true);
        return;
      }
      if (!trusted) return;
      eventTap = CGEventTapCreate(
        kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
        CGEventMaskBit(kCGEventKeyDown), handleKeyboardEvent, NULL);
      if (!eventTap) return;
      CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, eventTap, 0);
      if (!source) {
        CFRelease(eventTap);
        eventTap = NULL;
        return;
      }
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
      CFRelease(source);
      fputs("PinyinASCII active; input text is never logged.\n", stderr);
    }

    int main(void) {
      if (!AXIsProcessTrusted()) {
        fputs("Grant Accessibility to PinyinASCII.app to enable punctuation conversion.\n", stderr);
      }
      updateEventTap(NULL, NULL);
      // 每两秒检查权限和端口，授予权限后不必重新启动程序。
      CFRunLoopTimerRef retry = CFRunLoopTimerCreate(
        NULL, CFAbsoluteTimeGetCurrent() + 2, 2, 0, 0, updateEventTap, NULL);
      CFRunLoopAddTimer(CFRunLoopGetCurrent(), retry, kCFRunLoopCommonModes);
      CFRelease(retry);
      CFRunLoopRun();
      return 0;
    }
    #endif
  '';
  # 原创矢量图标使用路径和几何，不依赖系统字体或外部素材，保持模块可独立复制。
  iconSvg = pkgs.writeText "pinyin-ascii.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <defs>
        <linearGradient id="blue" x1="0" y1="0" x2="0.8" y2="1">
          <stop stop-color="#398FFF"/>
          <stop offset="1" stop-color="#1454CD"/>
        </linearGradient>
        <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
          <feDropShadow dx="0" dy="18" stdDeviation="18" flood-color="#092B63" flood-opacity="0.22"/>
        </filter>
      </defs>
      <rect x="64" y="64" width="896" height="896" rx="200" fill="url(#blue)" filter="url(#shadow)"/>
      <rect x="66" y="66" width="892" height="892" rx="198" fill="none" stroke="#FFF" stroke-opacity="0.18" stroke-width="2"/>
      <path fill="#FFF" fill-rule="evenodd" d="M258 744 433 284H533L708 744H601L565 639H400L364 744ZM430 552H535L483 400Z"/>
      <rect x="697" y="284" width="66" height="150" rx="17" fill="#FFF"/>
    </svg>
  '';
  helper = pkgs.stdenv.mkDerivation {
    pname = "pinyin-ascii";
    version = "1.0.0";
    src = source;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.resvg ];
    buildPhase = ''
      runHook preBuild
      $CC -O2 -Wall -Wextra -Werror -framework ApplicationServices -framework Carbon "$src" -o pinyin-ascii
      $CC -O2 -Wall -Wextra -Werror -DTEST -framework ApplicationServices -framework Carbon "$src" -o policy-test
      runHook postBuild
    '';
    doCheck = true;
    checkPhase = "./policy-test";
    installPhase = ''
      runHook preInstall
      app="$out/Applications/PinyinASCII.app/Contents"
      install -Dm755 pinyin-ascii "$app/MacOS/pinyin-ascii"
      install -Dm644 ${pkgs.writeText "PinyinASCII-LICENSE" licenseText} "$app/Resources/LICENSE"
      # 标准 1x/2x 图标覆盖 16–1024 像素；渲染器只在构建期使用。
      mkdir PinyinASCII.iconset
      for size in 16 32 128 256 512; do
        name="PinyinASCII.iconset/icon_''${size}x$size"
        resvg --width "$size" ${iconSvg} "$name.png"
        resvg --width "$((size * 2))" ${iconSvg} "$name@2x.png"
      done
      /usr/bin/iconutil --convert icns --output "$app/Resources/PinyinASCII.icns" PinyinASCII.iconset
      cp ${
        pkgs.writeText "Info.plist" (
          lib.generators.toPlist { escape = true; } {
            CFBundleIdentifier = "org.nixconfig.pinyin-ascii";
            CFBundleName = "PinyinASCII";
            CFBundleExecutable = "pinyin-ascii";
            CFBundleIconFile = "PinyinASCII.icns";
            CFBundlePackageType = "APPL";
            CFBundleVersion = "1";
            CFBundleShortVersionString = "1.0.0";
            LSUIElement = true;
          }
        )
      } "$app/Info.plist"
      mkdir -p "$out/bin"
      ln -s "$app/MacOS/pinyin-ascii" "$out/bin/pinyin-ascii"
      runHook postInstall
    '';
    # 最后签名 App，确保 fixup/strip 已完成。ad-hoc 身份不保证跨版本保留 TCC 授权。
    postFixup = ''
      /usr/bin/codesign --force --sign - "$out/Applications/PinyinASCII.app"
    '';
    meta = {
      description = "Native Apple Pinyin halfwidth punctuation with global ASCII supplements";
      license = lib.licenses.mit;
      platforms = lib.platforms.darwin;
      mainProgram = "pinyin-ascii";
    };
  };
in
{
  # 仅导入模块没有运行副作用；调用方显式 enable。package 可单独构建或 overrideAttrs。
  options.services.apple-pinyin-ascii-punctuation = {
    enable = lib.mkEnableOption "Apple 拼音原生半角标点与全局 ASCII 补充转换";
    package = lib.mkOption {
      type = lib.types.package;
      default = helper;
      defaultText = "本模块内嵌源码构建的 PinyinASCII";
      description = ''
        后台原生程序包；替换时须保留
        Applications/PinyinASCII.app/Contents/MacOS/pinyin-ascii 路径。
        默认包不查询输入源或组词状态，只补 ANSI 美式键位的原生半角缺漏。
        构建时测试补充字符、原事件透传与私有事件；真实输入法仍需交互验证。
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    assertions = [
      (lib.hm.assertions.assertPlatform "services.apple-pinyin-ascii-punctuation" pkgs
        lib.platforms.darwin
      )
    ];
    home.packages = [ cfg.package ];
    # 使用当前 Home Manager 的原生选项，只合并这一项，不接管其他拼音偏好。
    targets.darwin.defaults."com.apple.inputmethod.CoreChineseEngineFramework".usesHalfwidthPunctuation =
      true;
    # 固定运行身份独立于模块文件名；不接管调用方其他 App 的 copyApps 配置。
    launchd.agents.pinyin-ascii = {
      enable = true;
      config = {
        ProgramArguments = [
          "${cfg.package}/Applications/PinyinASCII.app/Contents/MacOS/pinyin-ascii"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/pinyin-ascii.log";
      };
    };
  };
}
