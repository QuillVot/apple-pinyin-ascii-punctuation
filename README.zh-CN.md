[English](README.md) | [简体中文](README.zh-CN.md)

# apple-pinyin-ascii-punctuation

PinyinASCII 的 Home Manager 模块，App 名为 `PinyinASCII.app`，命令为 `pinyin-ascii`。

在 macOS 上按 ANSI 美式物理键位转换 ASCII 标点，不限制当前输入源。完整 Home Manager 模块、C 源码、构建与测试均包含在单个文件 [`apple-pinyin-ascii-punctuation.nix`](apple-pinyin-ascii-punctuation.nix) 中。

Nix 使用锁定的 nixpkgs 工具链及其 SDK 编译 C 程序，无需个人 SDK 路径。运行时仍是使用 macOS 事件监听端口与辅助功能 API 的原生常驻程序，默认没有菜单栏图标。

## 转换规则

- 不查询或限制输入源，按同一组 ANSI 键位映射 32 个 ASCII 标点。
- 按住 Command、Option、Control 或 Fn 时保留原事件；无 Shift 的数字键继续用于选词。
- 正在组词或无法确定组词状态时，保留无 Shift 的 `'`、`-`、`=`、`[`、`]` 五个键，保护 `xi'an` 分音及候选导航。带 Shift 的标点仍转换。
- 只有这五个无 Shift 敏感键在按下时查询组词状态；其他按键、快捷键和所有抬键均不查询 AX。
- 复制原键盘事件，仅修改 Unicode 文本，保留目标路由、键码、修饰键和自动重复状态。

```text
!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
```

## Home Manager 接入

将单个模块复制到 Home Manager 配置旁并导入：

```nix
{
  imports = [ ./apple-pinyin-ascii-punctuation.nix ];
  services.apple-pinyin-ascii-punctuation.enable = true;
}
```

也可将本仓库作为本地 flake 输入，将示例路径替换为实际项目路径：

```nix
inputs.apple-pinyin-ascii-punctuation.url = "path:/absolute/path/to/apple-pinyin-ascii-punctuation";
```

在 flake outputs 参数中可访问 `apple-pinyin-ascii-punctuation` 的位置，将模块加入 Home Manager 的 `modules` 列表：

```nix
modules = [
  apple-pinyin-ascii-punctuation.homeManagerModules.default
  { services.apple-pinyin-ascii-punctuation.enable = true; }
];
```

`enable` 默认为 `false`，仅导入模块不会安装或启动 PinyinASCII。应用 Home Manager 配置后才启用服务。

## 构建与检查

在支持的 Darwin 系统上执行：

```sh
nix build --no-write-lock-file
# App: ./result/Applications/PinyinASCII.app

nix flake check --no-write-lock-file
nix flake check --all-systems --no-build --no-write-lock-file
```

第一条检查命令构建本机的 package、module 和 tools 检查。主程序构建测试全部 32 个标点映射、修饰键放行、组词策略及事件副本元数据；另用组词查询替身测试真实事件回调，核对查询范围、按下与抬键配对、重复按下和状态重置。工具检查编译工具并测试帮助参数，不打开输入探针界面或启动键盘监听。第二条命令仅求值声明的全部 Darwin 平台，不要求跨平台构建。两条检查命令都不会安装或激活 Home Manager 配置。

这些检查不能证明真实应用提供了有效组词范围，也不能代替输入法候选导航和权限生命周期的交互验证。

## 权限与服务

在“系统设置 → 隐私与安全性 → 辅助功能”，或 macOS 27 对应的“设备控制和数据访问”页面中，为 PinyinASCII 授权。可从 Home Manager 应用目录或构建输出中选择 App。程序等待授权，授权后自动重新连接。构建使用 ad-hoc 签名，代码变化后可能需要重新授权。

Home Manager 的 launchd label 为 `org.nix-community.home.pinyin-ascii`。日志位于 `~/Library/Logs/pinyin-ascii.log`，仅包含生命周期消息，不记录输入正文。

```sh
launchctl print "gui/$(id -u)/org.nix-community.home.pinyin-ascii"
tail -n 10 ~/Library/Logs/pinyin-ascii.log
```

更新后，如果权限开关已打开，但当前服务始终没有新的 `PinyinASCII active` 日志，先检查 macOS TCC 日志。只有其中针对 `org.nixconfig.pinyin-ascii` 报告 `Failed to match existing code requirement` 时，才使用下方恢复步骤：保存的授权可能仍绑定旧版 ad-hoc 签名。Apple 的 [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) 说明了代码要求如何识别应用身份。

```sh
tccutil reset Accessibility org.nixconfig.pinyin-ascii
```

确认重置成功后，在权限页重新添加并允许**当前安装版本**的 `PinyinASCII.app`。此命令只重置该 App 的辅助功能授权决定，不会授予权限。服务会自动重试；继续测试前，确认出现新的 `PinyinASCII active` 日志，且该进程 PID 的事件监听端口已启用。此流程仅用于已确认的签名失配，不是每次更新的例行步骤。

停用时设置 `services.apple-pinyin-ascii-punctuation.enable = false;`，再应用 Home Manager 配置。

## 诊断工具

```sh
nix build .#tools --no-write-lock-file
# 不记录日志启动：
open ./result/Applications/PinyinASCIIInputProbe.app
# 或显式记录本地测试日志：
./result/bin/pinyin-ascii-input-probe --log ./probe.jsonl
./result/bin/pinyin-ascii-ax-range PID
./result/bin/pinyin-ascii-event-tap-info
```

- **input-probe** 提供原生输入框，供交互验证。默认不写事件日志；显式传入 `--log ./probe.jsonl` 才启用 JSONL 记录。App 路径为 `./result/Applications/PinyinASCIIInputProbe.app`，命令行为 `bin/pinyin-ascii-input-probe`。
- **ax-range** 根据进程 ID 查询焦点元素的组词范围属性，只读查询范围，不读取正文内容。
- **event-tap-info** 通过 `CGGetEventTapList` 枚举事件监听端口元数据，不创建监听端口，也不读取按键。

仓库只收录源码，构建输出、本地探针日志及其他生成产物不应进入 Git。

## 手动验证与局限

1. 分别选择 ABC 和 Apple 简体拼音，在没有组词时使用实体 ANSI 键逐个输入上述 32 个符号，同时核对 Command/Option/Control/Fn 组合键、无 Shift 数字选词、按键重复及先松开 Shift 再抬键。粘贴符号不能验证转换。
2. 输入并组词 `xi'an`，确认无 Shift 单引号仍用于拼音分音。
3. 展开候选窗口，用 `]` 前进、`[` 返回，并核对翻页前后同一编号位置的候选字是否变化。只看到按键发送日志不能证明已经翻页。
4. 分别检查 `-` 与普通 ANSI `=`。ANSI `=` 的虚拟键码为 24，数字小键盘 `=` 为 81，后者不在本映射内。验证中观察到 macOS 自动化发送 `equal` 时意外附带 Shift，结果不明确时应使用实体键补验。日志中的 `=`/`-` 往返不足以严格证明每个单键都成功翻页。

应用可能忽略事件中的 Unicode 文本，或继续应用自己的智能标点和文字替换。AX 支持因应用而异：组词状态未知时，即使在 ABC 下也保留上述五个无 Shift 敏感键，其余已映射标点仍转换。

部分框架在组词时也可能返回空的 AX 属性，空值不能作为跨框架的“没有组词”证明。定向合成按键与实体键的行为也可能不同；各应用中的分音和候选导航仍应使用实体键补验，尤其是 Electron 应用。

转换按 ANSI 美式物理键位执行，不跟随当前输入源的字符布局；其他符号布局原本的字符可能被替换。其他输入法同样受转换影响，但其组词和导航按键尚未逐一验证；五键保护并未覆盖所有输入法的特殊按键。构建检查不能替代这些应用层验证。

## 许可与参考

[MIT](LICENSE)。单文件模块同时内嵌完整许可，便于独立复制和分发。

参考：[Apple 标点设置](https://support.apple.com/en-mo/guide/chinese-input-method/cim21aa5fa50/mac)、[Apple 候选窗口按键](https://support.apple.com/zh-hans/guide/chinese-input-method/cim12992/104/mac/27)、[CGEvent Unicode 行为](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:))、[Nix 官方手册](https://nix.dev/manual/nix/latest/)。
