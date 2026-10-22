[English](README.md) | [简体中文](README.zh-CN.md)

# apple-pinyin-ascii-punctuation

Home Manager module for PinyinASCII (`PinyinASCII.app`, command `pinyin-ascii`).

ASCII punctuation for Apple's Simplified Pinyin input method on macOS with an ANSI keyboard layout. The complete Home Manager module, including its C source, build and tests, lives in [`apple-pinyin-ascii-punctuation.nix`](apple-pinyin-ascii-punctuation.nix).

Nix compiles the C program with the SDK supplied by the pinned nixpkgs toolchain; no personal SDK path is needed. At runtime, PinyinASCII is a native background program using a macOS event tap and Accessibility APIs. It has no menu bar item by default.

## Behavior

- Converts the 32 ASCII punctuation symbols while Apple Simplified Pinyin is selected. Other input sources pass through.
- Preserves events with Command, Option, Control or Fn held. Unshifted number keys remain available for candidate selection.
- Preserves the five unshifted keys `'`, `-`, `=`, `[` and `]` while composition is active or its state is unknown, protecting `xi'an` and candidate navigation. Shifted punctuation still converts.
- Copies the original keyboard event and changes its Unicode text, preserving its routing, key code, modifiers and repeat state.

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

`enable` defaults to `false`; importing the module alone does not install or start PinyinASCII. Apply your Home Manager configuration to enable the service.

## Build and checks

On a supported Darwin system:

```sh
nix build --no-write-lock-file
# App: ./result/Applications/PinyinASCII.app

nix flake check --no-write-lock-file
nix flake check --all-systems --no-build --no-write-lock-file
```

The first check command builds the current system's package, module and tools checks. The package build tests all 32 mappings, modifier handling, composition policy and event-copy metadata. The tools check builds the tools and tests their help arguments; it does not open the probe UI or start keyboard monitoring. The second command evaluates all declared Darwin systems without cross-building them. Neither command installs or activates a Home Manager configuration.

These checks do not establish that real applications expose useful composition ranges or that input-method navigation and permissions work interactively.

## Permissions and service

Grant PinyinASCII permission in System Settings → Privacy & Security → Accessibility, or the corresponding **Device Control and Data Access** page on macOS 27. Select the App from your Home Manager applications directory or the build output. The process waits for permission and reconnects after permission is granted. Builds use an ad-hoc signature; changing the code may require authorization again.

The Home Manager launchd label is `org.nix-community.home.pinyin-ascii`. Its log is `~/Library/Logs/pinyin-ascii.log` and contains lifecycle messages, not typed text.

```sh
launchctl print "gui/$(id -u)/org.nix-community.home.pinyin-ascii"
tail -n 10 ~/Library/Logs/pinyin-ascii.log
```

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
- **ax-range** queries the focused element's composition-range attributes for the supplied process ID. It is a read-only range diagnostic, not a text-content reader.
- **event-tap-info** enumerates tap metadata through `CGGetEventTapList`. It does not create event taps or read keystrokes.

The repository contains source only. Build outputs, local probe logs and other generated artifacts do not belong in Git.

## Interactive verification and limits

1. Select Apple Simplified Pinyin and type all 32 symbols above using their physical ANSI keys. Check Command/Option/Control/Fn combinations and unshifted number selection too. Pasting the symbols does not test the conversion.
2. Compose `xi'an` and confirm that the unshifted apostrophe remains a Pinyin separator.
3. Expand the candidate window, press `]` to advance and `[` to return, and compare the candidate at the same numbered position before and after. A key-dispatch log alone does not prove that a page changed.
4. Test `-` and ordinary ANSI `=` separately. ANSI `=` is virtual key 24; keypad `=` is key 81 and is outside this mapping. Validation observed macOS automation sending `equal` with an unexpected Shift modifier, so confirm ambiguous results with a physical key. A `=`/`-` round trip in a log is insufficient evidence that each individual key paged correctly.

Applications may ignore event Unicode text or apply their own smart punctuation and text replacements. AX support varies: an unknown composition state protects only the five unshifted sensitive keys above; other mapped punctuation still converts. Non-ANSI layouts and other input methods are outside the supported scope. Build checks cannot replace these application-level checks.

## License and references

[MIT](LICENSE). The single module also embeds the full license for copying and redistribution.

References: [Apple punctuation settings](https://support.apple.com/en-mo/guide/chinese-input-method/cim21aa5fa50/mac), [Apple candidate-window keys](https://support.apple.com/zh-hans/guide/chinese-input-method/cim12992/104/mac/27), [CGEvent Unicode behavior](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring(stringlength:unicodestring:)), [Nix manual](https://nix.dev/manual/nix/latest/).
