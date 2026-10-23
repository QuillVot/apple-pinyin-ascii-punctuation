[English](README.md) | [简体中文](README.zh-CN.md)

# apple-pinyin-ascii-punctuation

PinyinASCII 的 Home Manager 模块，App 名为 `PinyinASCII.app`，命令为 `pinyin-ascii`。

在 macOS 上组合使用 Apple 拼音原生半角标点设置和少量 ANSI 美式键位补充转换。完整 Home Manager 模块、C 源码、构建与测试均包含在单个文件 [`apple-pinyin-ascii-punctuation.nix`](apple-pinyin-ascii-punctuation.nix) 中。

Nix 使用锁定的 nixpkgs 工具链及其 SDK 编译 C 程序，无需个人 SDK 路径。PinyinASCII 通过 macOS 事件监听端口常驻运行，默认没有菜单栏图标。

## 转换规则与前提

- 模块启用时，通过 Home Manager 的 `targets.darwin.defaults` 声明 Apple 拼音“使用半角标点”（`usesHalfwidthPunctuation = true`）。原生输入法负责其余标点和拼音组词。
- 程序只补充 11 个标点，跨输入源按 ANSI 美式物理键位处理，不查询当前输入源，不读取组词范围或输入正文。
- 无 Shift 的 `[`、`]`、`-`、`=` 始终保留原事件，保护 Apple 拼音候选翻页，需要作为文本输入时沿用原生处理。带 Shift 的 `{`、`}`、`_` 由程序补充，`+` 沿用原生处理。
- Command、Option、Control、Fn 组合键、无 Shift 的数字键及所有抬键均原样通过。
- 转换按下事件时，程序使用私有事件源新建键盘事件，保留物理键码、时间戳和重复值，写入 ASCII Unicode 字符并清除修饰键标志。
- 需要字面 ASCII 输出时，请关闭目标应用的智能引号及其他标点替换；这些功能可能在输入处理之后再次修改文本。

私有事件源的构造参考 [Tail Input](https://github.com/framecy/Tail-Input/blob/0a690ef8c88b79e7e49b745bdad37566e4dc0c80/Sources/TailInput/PunctuationService.swift#L150)。

补充转换的字符为：

```text
$ ^ _ { } \ ' " < > `
```

以下完整 ASCII 标点集用于逐键验证；原生半角设置与补充转换共同覆盖目标符号，程序不会重写其中每个字符：

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

`enable` 默认为 `false`，仅导入模块不会安装或启动 PinyinASCII。应用 Home Manager 配置后才启用服务并声明原生半角设置；所用 Home Manager 版本须支持 `targets.darwin.defaults`。

## 构建与检查

在支持的 Darwin 系统上执行：

```sh
nix build --no-write-lock-file
# App: ./result/Applications/PinyinASCII.app

nix flake check --no-write-lock-file
nix flake check --all-systems --no-build --no-write-lock-file
```

第一条检查命令构建本机的 package、module 和 tools 检查。主程序构建测试 11 个补充映射、快捷键与翻页键放行、抬键放行及替换事件属性。工具检查编译工具并测试帮助参数，不打开输入探针界面或启动键盘监听。第二条命令仅求值声明的全部 Darwin 平台，不要求跨平台构建。两条检查命令都不会安装或激活 Home Manager 配置。

这些检查不能证明真实应用接受替换事件、原生半角设置已生效，也不能代替候选导航和权限生命周期的交互验证。

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
- **ax-range** 根据进程 ID 查询焦点元素的组词范围属性，是独立的只读范围诊断工具，不读取正文；转换程序不调用它。
- **event-tap-info** 通过 `CGGetEventTapList` 枚举事件监听端口元数据，不创建监听端口，也不读取按键。

仓库只收录源码，构建输出、本地探针日志及其他生成产物不应进入 Git。

## 手动验证与局限

安装后的版本仍需实体按键验证；下列清单不代表已经通过的结果。

1. 开启原生半角标点、关闭应用智能引号。分别选择 ABC 和 Apple 简体拼音，在没有组词时使用实体 ANSI 键逐个输入上述完整符号集，同时核对 Command/Option/Control/Fn 组合键、无 Shift 数字选词、按键重复及先松开 Shift 再抬键。粘贴符号不能验证输入处理。
2. 分别组词 `xi'an` 和 `chang'an`，确认单引号能正常分音，并产生正常拼音候选；另在没有组词时检查字面单引号和双引号。
3. 展开候选窗口，分别单独检查 `]`、`[`、`-`、`=`。每次核对翻页前后同一编号位置的候选字是否变化；只看到发送日志或一组前进／返回，不能证明每个单键都翻页。使用实体 ANSI `=`（虚拟键码 24），不使用数字小键盘 `=`（键码 81）或意外附带 Shift 的自动化按键。
4. 逐个检查带 Shift 的 `{`、`}`、`_`、`+`，并核对两种引号及其余补充符号。

应用可能忽略事件中的 Unicode、按物理键码重新翻译字符，或继续应用自己的文字替换。定向合成按键与实体键的行为也可能不同；各目标应用中的分音、引号和候选导航仍应使用实体键验证，尤其是 Electron 应用。

转换跨输入源按 ANSI 美式物理键位执行；其他布局原本的字符可能被替换，其他输入法的特殊按键尚未逐一验证。无 Shift 的 `[`、`]`、`-`、`=` 在任何输入源下都保持原生行为，其输出取决于输入源和应用。原生半角设置与补充转换分别承担不同部分，构建检查不能代替应用层验证。

## 许可与参考

[MIT](LICENSE)。单文件模块同时内嵌完整许可，便于独立复制和分发。

参考：[Apple 标点设置](https://support.apple.com/en-mo/guide/chinese-input-method/cim21aa5fa50/mac)、[Apple 候选窗口按键](https://support.apple.com/zh-hans/guide/chinese-input-method/cim12992/104/mac/27)、[CGEvent Unicode 行为](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:))、[Nix 官方手册](https://nix.dev/manual/nix/latest/)。
