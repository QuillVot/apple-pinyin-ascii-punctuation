<p align="center">
  <img src="assets/pinyin-ascii.png" alt="PinyinASCII app icon" width="128" height="128">
</p>

[English](README.md) | [简体中文](README.zh-CN.md)

# apple-pinyin-ascii-punctuation

Home Manager module for PinyinASCII (`PinyinASCII.app`, command `pinyin-ascii`).

Combines Apple Pinyin's native halfwidth punctuation setting with a small ANSI US punctuation supplement on macOS. The complete Home Manager module, including its C source, build and tests, lives in [`apple-pinyin-ascii-punctuation.nix`](apple-pinyin-ascii-punctuation.nix).

Nix compiles the C program with the SDK supplied by the pinned nixpkgs toolchain; no personal SDK path is needed. PinyinASCII runs as a native background program with a macOS event tap and no menu bar item by default.

The app icon pairs a white A and straight quote on a blue rounded square. Its SVG source is embedded in the module and converted to an `.icns` file at build time with resvg and macOS `iconutil`; neither adds a runtime dependency.

## Behavior and requirements

- When enabled, the module declares Apple Pinyin's **Use Halfwidth Punctuation** setting (`usesHalfwidthPunctuation = true`) through Home Manager's `targets.darwin.defaults`. Native handling remains responsible for the other punctuation and for Pinyin composition.
- The converter supplements eleven punctuation characters. It uses physical ANSI US key positions across input sources, without looking up the selected input source or reading composition ranges or text contents.
- Unshifted `[`, `]`, `-` and `=` always keep their original events, preserving Apple Pinyin's candidate navigation. Native input handling supplies their text when appropriate. Shifted `{`, `}` and `_` are supplemented; `+` uses native handling.
- Command, Option, Control and Fn combinations, unshifted number keys and every key-up event pass through unchanged.
- For a converted key down, the program creates a fresh keyboard event from a private event source, retains the physical key code, timestamp and repeat value, supplies the ASCII Unicode character and clears modifier flags.
- Disable the target application's smart quotes and other punctuation replacements when literal ASCII output is required; they can change text after input processing.

The private-source event construction follows the approach in [Tail Input](https://github.com/framecy/Tail-Input/blob/0a690ef8c88b79e7e49b745bdad37566e4dc0c80/Sources/TailInput/PunctuationService.swift#L150).

The supplemental characters are:

```text
$ ^ _ { } \ ' " < > `
```

Use this full ASCII punctuation set as an interactive checklist. Native halfwidth punctuation and the supplement together target the full set; the converter does not rewrite every character:

```text
!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
```

## Home Manager

Copy the single module next to your Home Manager configuration:

```nix
{
  imports = [ ./apple-pinyin-ascii-punctuation.nix ];
  services.apple-pinyin-ascii-punctuation.enable = true;
}
```

Alternatively, add your checkout as a local flake input, replacing the example path:

```nix
inputs.apple-pinyin-ascii-punctuation.url = "path:/absolute/path/to/apple-pinyin-ascii-punctuation";
```

Where `apple-pinyin-ascii-punctuation` is available in your flake outputs arguments, add its module to the Home Manager `modules` list:

```nix
modules = [
  apple-pinyin-ascii-punctuation.homeManagerModules.default
  { services.apple-pinyin-ascii-punctuation.enable = true; }
];
```

`enable` defaults to `false`; importing the module alone does not install or start PinyinASCII. Apply your Home Manager configuration to enable the service and declare native halfwidth punctuation. Your Home Manager version must provide `targets.darwin.defaults`.

## Build and checks

On a supported Darwin system:

```sh
nix build --no-write-lock-file
# App: ./result/Applications/PinyinASCII.app

nix flake check --no-write-lock-file
nix flake check --all-systems --no-build --no-write-lock-file
```

The first check command builds the current system's package, module and tools checks. The package build tests the eleven supplemental mappings, shortcut and navigation-key passthrough, key-up passthrough and replacement-event properties. The tools check builds the tools and tests their help arguments; it does not open the probe UI or start keyboard monitoring. The second command evaluates all declared Darwin systems without cross-building them. Neither command installs or activates a Home Manager configuration.

These checks do not establish that real applications accept the replacement events, that native halfwidth punctuation is effective, or that candidate navigation and permissions work interactively.

## Permissions and service

Grant PinyinASCII permission in System Settings → Privacy & Security → Accessibility, or the corresponding **Device Control and Data Access** page on macOS 27. Select the App from your Home Manager applications directory or the build output. The process waits for permission and reconnects after permission is granted. Builds use an ad-hoc signature; changing the code may require authorization again.

The Home Manager launchd label is `org.nix-community.home.pinyin-ascii`. Its log is `~/Library/Logs/pinyin-ascii.log` and contains lifecycle messages, not typed text.

```sh
launchctl print "gui/$(id -u)/org.nix-community.home.pinyin-ascii"
tail -n 10 ~/Library/Logs/pinyin-ascii.log
```

After an update, if the permission toggle is on but the current service never logs a new `PinyinASCII active` entry, check the macOS TCC logs. Use the recovery below only if they report `Failed to match existing code requirement` for `org.nixconfig.pinyin-ascii`: the saved grant may still refer to an older ad-hoc signature. Apple explains how code requirements identify an app in [TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

```sh
tccutil reset Accessibility org.nixconfig.pinyin-ascii
```

Confirm that the reset succeeds, then add and allow the **current installed** `PinyinASCII.app` again on the permission page. This resets only this app's Accessibility decision; it does not grant access. The service retries automatically. Confirm a new `PinyinASCII active` log entry and an enabled event tap for its PID before resuming tests. This recovery is for a confirmed signature mismatch, not a routine update step.

Set `services.apple-pinyin-ascii-punctuation.enable = false;` and apply Home Manager to disable it.

## Diagnostic tools

```sh
nix build .#tools --no-write-lock-file
# Start without logging:
open ./result/Applications/PinyinASCIIInputProbe.app
# Or start with an explicit local test log:
./result/bin/pinyin-ascii-input-probe --log ./probe.jsonl
./result/bin/pinyin-ascii-ax-range PID
./result/bin/pinyin-ascii-event-tap-info
```

- **input-probe** provides a native input field for interactive checks. It writes no event log by default; `--log ./probe.jsonl` explicitly enables JSONL logging. The App is `./result/Applications/PinyinASCIIInputProbe.app`; its CLI is `bin/pinyin-ascii-input-probe`.
- **ax-range** queries the focused element's composition-range attributes for the supplied process ID. It is a separate read-only range diagnostic, not a text-content reader; the converter does not use it.
- **event-tap-info** enumerates tap metadata through `CGGetEventTapList`. It does not create event taps or read keystrokes.

The repository contains source and documentation images. App build outputs, local probe logs and other generated artifacts do not belong in Git.

## Interactive verification and limits

Physical validation of the installed revision is required; the checklist below is not a record of passing results.

1. Enable native halfwidth punctuation and disable application smart quotes. In both ABC and Apple Simplified Pinyin, type the full symbol set above with physical ANSI keys while no composition is active. Also check Command/Option/Control/Fn combinations, unshifted number selection, repeats and releasing Shift before key up. Pasting the symbols does not test input processing.
2. Compose `xi'an` and `chang'an`. Confirm that the apostrophe separates syllables and both words still produce normal Pinyin candidates. Also check literal single and double quotes outside composition.
3. Expand a candidate window and test each of `]`, `[`, `-` and `=` individually. For each key, compare the candidate at the same numbered position before and after; a dispatch log or a forward/back round trip alone does not prove that each key paged. Use the physical ANSI `=` key (virtual key 24), not keypad `=` (key 81) or automation that adds Shift.
4. Check shifted `{`, `}`, `_` and `+` individually, together with both quotes and the remaining supplemental symbols.

Applications may ignore event Unicode text, translate from the physical key code, or apply their own text replacements. Directed synthetic events can also behave differently from physical input. Verify separators, quotes and candidate navigation in each target application, especially Electron applications.

The converter uses ANSI US physical key positions across input sources. Other layouts may have their characters replaced, and other input methods' special keys have not been individually verified. Unshifted `[`, `]`, `-` and `=` remain native in every input source; their output depends on that input source and application. Native halfwidth punctuation and the supplement are separate parts of the behavior, and build checks cannot replace application-level checks.

## License and references

[MIT](LICENSE). The single module also embeds the full license for copying and redistribution.

References: [Apple punctuation settings](https://support.apple.com/en-mo/guide/chinese-input-method/cim21aa5fa50/mac), [Apple candidate-window keys](https://support.apple.com/zh-hans/guide/chinese-input-method/cim12992/104/mac/27), [CGEvent Unicode behavior](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)), [Nix manual](https://nix.dev/manual/nix/latest/).
