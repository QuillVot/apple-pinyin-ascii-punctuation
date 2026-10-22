# SPDX-License-Identifier: MIT
# Copyright (c) 2026 PinyinASCII contributors
#
# Home Manager 模块：Apple 简体拼音下的 ANSI / ASCII 标点转换。
# 用法：imports = [ ./apple-pinyin-ascii-punctuation.nix ];
#       services.apple-pinyin-ascii-punctuation.enable = true;
# 需要 macOS 的辅助功能授权；不支持的组词状态不会被猜成“没有组词”。
# 字体、其他输入法、系统键位和应用自己的文字替换规则均不由此模块管理。
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
  # Apple 公布的 ANSI 物理键名，而非当前输入法产生的字符或魔术数字。
  # 每项依次为普通、Shift 字符；空格表示不转换，避免干预数字选词。
  keyMap = {
    ANSI_1 = " !";
    ANSI_2 = " @";
    ANSI_3 = " #";
    ANSI_4 = " $";
    ANSI_5 = " %";
    ANSI_6 = " ^";
    ANSI_7 = " &";
    ANSI_8 = " *";
    ANSI_9 = " (";
    ANSI_0 = " )";
    ANSI_Minus = "-_";
    ANSI_Equal = "=+";
    ANSI_LeftBracket = "[{";
    ANSI_RightBracket = "]}";
    ANSI_Backslash = "\\|";
    ANSI_Semicolon = ";:";
    ANSI_Quote = "'\"";
    ANSI_Comma = ",<";
    ANSI_Period = ".>";
    ANSI_Slash = "/?";
    ANSI_Grave = "`~";
  };
  source = pkgs.writeText "pinyin-ascii.c" ''
    /*
    ${licenseText}
    */
    #include <ApplicationServices/ApplicationServices.h>
    #include <Carbon/Carbon.h>
    #include <assert.h>
    #include <stdio.h>
    #include <string.h>

    /* 按 Apple ANSI 虚拟键位定义映射，未适配其他符号布局；未列出的键不转换。 */
    enum { KEYCODE_COUNT = 128 };
    enum { COMPOSITION_UNKNOWN = -1, COMPOSITION_CLEAR = 0, COMPOSITION_MARKED = 1 };

    static const char symbolsByKeyCode[KEYCODE_COUNT][3] = {
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (key: value: "[kVK_${key}] = ${builtins.toJSON value},") keyMap
      )}
    };

    /* 无 Shift 的单引号用于 xi'an 分音，-= 和 [] 用于候选导航。 */
    static bool hasPinyinMeaning(unsigned key) {
      return key == kVK_ANSI_Quote || key == kVK_ANSI_Minus || key == kVK_ANSI_Equal ||
             key == kVK_ANSI_LeftBracket || key == kVK_ANSI_RightBracket;
    }

    /* 纯策略函数：返回 ASCII 或 0（保留原事件），不访问输入法和 AX。 */
    static UniChar asciiSymbol(unsigned key, CGEventFlags flags, bool pinyin, int marked) {
      CGEventFlags shortcuts = kCGEventFlagMaskCommand | kCGEventFlagMaskControl |
                               kCGEventFlagMaskAlternate | kCGEventFlagMaskSecondaryFn;
      bool shift = (flags & kCGEventFlagMaskShift) != 0;
      if (!pinyin || key >= KEYCODE_COUNT || (flags & shortcuts) ||
          (!shift && hasPinyinMeaning(key) && marked != COMPOSITION_CLEAR))
        return 0;
      return symbolsByKeyCode[key][shift] == ' ' ? 0 : (unsigned char)symbolsByKeyCode[key][shift];
    }

    /* 复制完整事件，保留目标路由、键码、修饰键、时间和重复状态，仅替换 Unicode。
       重新创建事件会丢失定向投递的内部元数据。 */
    static CGEventRef copyWithSymbol(CGEventRef original, UniChar value) {
      CGEventRef result = CGEventCreateCopy(original);
      if (result) CGEventKeyboardSetUnicodeString(result, 1, &value);
      return result;
    }

    /* 构建期测试不启动监听。真实组词、AX 查询和权限生命周期仍须交互验证。 */
    #ifdef TEST
    int main(void) {
      const char *all = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
      bool seen[KEYCODE_COUNT] = {0};
      unsigned count = 0;
      for (unsigned key = 0; key < KEYCODE_COUNT; key++) {
        for (unsigned shift = 0; shift < 2; shift++) {
          CGEventFlags flags = shift ? kCGEventFlagMaskShift : 0;
          UniChar value = asciiSymbol(key, flags, true, COMPOSITION_CLEAR);
          if (!value) continue;
          assert(value < KEYCODE_COUNT && strchr(all, value) && !seen[value]);
          seen[value] = true;
          count++;
          assert(asciiSymbol(key, flags, false, COMPOSITION_CLEAR) == 0);
          CGEventFlags shortcuts[] = { kCGEventFlagMaskCommand, kCGEventFlagMaskControl,
                                      kCGEventFlagMaskAlternate, kCGEventFlagMaskSecondaryFn };
          for (unsigned i = 0; i < 4; i++)
            assert(asciiSymbol(key, flags | shortcuts[i], true, COMPOSITION_CLEAR) == 0);
          // 测试预期独立于生产 hasPinyinMeaning()，避免两者一起出错仍通过。
          assert(asciiSymbol(key, flags, true, COMPOSITION_MARKED) ==
                 (!shift && strchr("'-=[]", value) != NULL ? 0 : value));
          assert(asciiSymbol(key, flags, true, COMPOSITION_UNKNOWN) ==
                 (!shift && strchr("'-=[]", value) != NULL ? 0 : value));
        }
      }
      assert(count == 32);
      for (const char *p = all; *p; p++) assert(seen[(unsigned char)*p]);
      assert(asciiSymbol(KEYCODE_COUNT, 0, true, COMPOSITION_CLEAR) == 0);
      assert(asciiSymbol(kVK_ANSI_A, 0, true, COMPOSITION_CLEAR) == 0);  // a，仍由拼音处理。
      // 独立检查数字选词和具体键位；字符集合齐全并不能发现左右括号互换。
      const CGKeyCode digits[] = { kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                                  kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9 };
      for (unsigned i = 0; i < sizeof digits / sizeof *digits; i++)
        assert(asciiSymbol(digits[i], 0, true, COMPOSITION_MARKED) == 0);
      assert(asciiSymbol(kVK_ANSI_4, kCGEventFlagMaskShift, true, COMPOSITION_CLEAR) == '$');
      assert(asciiSymbol(kVK_ANSI_5, kCGEventFlagMaskShift, true, COMPOSITION_CLEAR) == '%');
      assert(asciiSymbol(kVK_ANSI_LeftBracket, 0, true, COMPOSITION_CLEAR) == '[');
      assert(asciiSymbol(kVK_ANSI_RightBracket, 0, true, COMPOSITION_CLEAR) == ']');
      assert(asciiSymbol(kVK_ANSI_Backslash, 0, true, COMPOSITION_CLEAR) == "\\"[0]);
      assert(asciiSymbol(kVK_ANSI_Grave, 0, true, COMPOSITION_CLEAR) == 0x60); // 反引号。
      for (unsigned down = 0; down < 2; down++) {
        CGEventRef original = CGEventCreateKeyboardEvent(NULL, kVK_ANSI_4, down);
        CGEventSetFlags(original, kCGEventFlagMaskShift);
        CGEventSetIntegerValueField(original, kCGKeyboardEventAutorepeat, 1);
        CGEventSetIntegerValueField(original, kCGEventSourceUserData, 0x4e4958);
        CGEventRef result = copyWithSymbol(original, 36);
        UniChar text = 0;
        UniCharCount length = 0;
        assert(result && CGEventGetType(result) == CGEventGetType(original));
        CGEventKeyboardGetUnicodeString(result, 1, &length, &text);
        assert(length == 1 && text == 36);
        assert(CGEventGetIntegerValueField(result, kCGKeyboardEventKeycode) == kVK_ANSI_4);
        assert(CGEventGetFlags(result) == kCGEventFlagMaskShift);
        assert(CGEventGetTimestamp(result) == CGEventGetTimestamp(original));
        assert(CGEventGetIntegerValueField(result, kCGKeyboardEventAutorepeat) == 1);
        assert(CGEventGetIntegerValueField(result, kCGEventSourceUserData) == 0x4e4958);
        CFRelease(result);
        CFRelease(original);
      }
      puts("PASS: punctuation policy and event-copy checks");
    }
    #else
    static CFMachPortRef eventTap;
    /* 保存最近一次按下的替换字符，供抬键配对；自动重复会重新判断策略。 */
    static UniChar keyDownSymbols[KEYCODE_COUNT];

    /* TIS 只能判断输入源，不能判断是否正在组词。 */
    static bool isApplePinyinSelected(void) {
      TISInputSourceRef source = TISCopyCurrentKeyboardInputSource();
      if (!source) return false;
      CFStringRef identifier = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
      bool result = identifier && CFEqual(identifier, CFSTR("com.apple.inputmethod.SCIM.ITABC"));
      CFRelease(source);
      return result;
    }

    /* 读取事件目标应用的焦点输入框，不能假定系统当前焦点就是事件目标。
       只查组词范围，不读正文；原生范围不支持时再尝试 WebKit 范围。
       未知状态只保护五个无 Shift 的敏感键，其他标点仍可转换。 */
    static int compositionStateForProcess(pid_t pid) {
      if (pid <= 0) return COMPOSITION_UNKNOWN;
      AXUIElementRef application = AXUIElementCreateApplication(pid);
      CFTypeRef focused = NULL, value = NULL;
      int result = COMPOSITION_UNKNOWN;
      if (AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute,
                                       &focused) == kAXErrorSuccess &&
          focused && CFGetTypeID(focused) == AXUIElementGetTypeID()) {
        AXError error = AXUIElementCopyAttributeValue(focused, CFSTR("AXTextInputMarkedRange"), &value);
        CFRange range;
        // 属性支持但没有值，与属性不受支持是不同状态。
        if (error == kAXErrorNoValue) result = COMPOSITION_CLEAR;
        else if (error == kAXErrorSuccess && value && CFGetTypeID(value) == AXValueGetTypeID() &&
                 AXValueGetType(value) == kAXValueCFRangeType &&
                 AXValueGetValue(value, kAXValueCFRangeType, &range)) {
          // 无组词时 location 可以为 NSNotFound，length=0 仍表示没有组词。
          result = range.length > 0 ? COMPOSITION_MARKED
                 : range.length == 0 ? COMPOSITION_CLEAR
                                     : COMPOSITION_UNKNOWN;
        } else if (error == kAXErrorAttributeUnsupported) {
          if (value) {
            CFRelease(value);
            value = NULL;
          }
          error = AXUIElementCopyAttributeValue(focused,
                                               CFSTR("AXTextInputMarkedTextMarkerRange"), &value);
          if (error == kAXErrorNoValue) result = COMPOSITION_CLEAR;
          else if (error == kAXErrorSuccess)
            result = value && CFGetTypeID(value) != CFNullGetTypeID()
                     ? COMPOSITION_MARKED : COMPOSITION_CLEAR;
        }
      }
      if (value) CFRelease(value);
      if (focused) CFRelease(focused);
      CFRelease(application);
      return result;
    }

    /* 标注后的位置兼顾实体键盘与定向投递；返回副本而非额外 post，避免递归。 */
    static CGEventRef handleKeyboardEvent(CGEventTapProxy proxy, CGEventType type,
                                          CGEventRef event, void *context) {
      (void)proxy;
      (void)context;
      if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        memset(keyDownSymbols, 0, sizeof keyDownSymbols);
        if (eventTap && CFMachPortIsValid(eventTap) && AXIsProcessTrusted())
          CGEventTapEnable(eventTap, true);
        return event;
      }
      unsigned key = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
      if (key >= KEYCODE_COUNT) return event;
      UniChar value = keyDownSymbols[key];
      // 抬键沿用按下结果，不因松开 Shift 或切换输入源而改变这次配对。
      if (type == kCGEventKeyUp) keyDownSymbols[key] = 0;
      else {
        CGEventFlags flags = CGEventGetFlags(event);
        value = asciiSymbol(key, flags, isApplePinyinSelected(), COMPOSITION_CLEAR);
        if (value && !(flags & kCGEventFlagMaskShift) && hasPinyinMeaning(key))
          value = asciiSymbol(key, flags, true, compositionStateForProcess(
            (pid_t)CGEventGetIntegerValueField(event, kCGEventTargetUnixProcessID)));
        keyDownSymbols[key] = value;
      }
      // Quartz 接管并释放回调返回的副本；分配失败则保留原事件。
      CGEventRef result = value ? copyWithSymbol(event, value) : NULL;
      return result ? result : event;
    }

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
        memset(keyDownSymbols, 0, sizeof keyDownSymbols);
      }
      if (eventTap) {
        if (!CGEventTapIsEnabled(eventTap)) CGEventTapEnable(eventTap, true);
        return;
      }
      if (!trusted) return;
      eventTap = CGEventTapCreate(
        kCGAnnotatedSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
        CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp), handleKeyboardEvent, NULL);
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
      // system-wide 对象上的 50ms 超时对本进程全局生效，限制随后所有 AX 调用。
      // 超时不猜测组词状态，敏感键交回输入法。
      AXUIElementRef system = AXUIElementCreateSystemWide();
      AXUIElementSetMessagingTimeout(system, 0.05);
      CFRelease(system);
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
  helper = pkgs.stdenv.mkDerivation {
    pname = "pinyin-ascii";
    version = "1.0.0";
    src = source;
    dontUnpack = true;
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
      cp ${
        pkgs.writeText "Info.plist" (
          lib.generators.toPlist { escape = true; } {
            CFBundleIdentifier = "org.nixconfig.pinyin-ascii";
            CFBundleName = "PinyinASCII";
            CFBundleExecutable = "pinyin-ascii";
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
      description = "ASCII punctuation for Apple Simplified Pinyin on macOS";
      license = lib.licenses.mit;
      platforms = lib.platforms.darwin;
      mainProgram = "pinyin-ascii";
    };
  };
in
{
  # 仅导入模块没有运行副作用；调用方显式 enable。package 可单独构建或 overrideAttrs。
  options.services.apple-pinyin-ascii-punctuation = {
    enable = lib.mkEnableOption "Apple 简体拼音的 ASCII 标点转换";
    package = lib.mkOption {
      type = lib.types.package;
      default = helper;
      defaultText = "本模块内嵌源码构建的 PinyinASCII";
      description = ''
        后台原生程序包；替换时须保留
        Applications/PinyinASCII.app/Contents/MacOS/pinyin-ascii 路径。
        默认包在构建时运行转换策略和事件副本测试。
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
