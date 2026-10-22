# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "pinyin-ascii-tools";
  version = "1.0.0";
  src = ./.;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -Wextra -Werror -fobjc-arc -framework AppKit input-probe.m -o pinyin-ascii-input-probe
    $CC -O2 -Wall -Wextra -Werror -framework ApplicationServices ax-range.c -o pinyin-ascii-ax-range
    $CC -O2 -Wall -Wextra -Werror -framework ApplicationServices event-tap-info.c -o pinyin-ascii-event-tap-info
    runHook postBuild
  '';

  doCheck = true;
  # Exercise argument handling without opening windows, requesting access or installing taps.
  checkPhase = ''
    runHook preCheck
    ./pinyin-ascii-input-probe --help
    ./pinyin-ascii-ax-range --help
    ./pinyin-ascii-event-tap-info --help
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    app="$out/Applications/PinyinASCIIInputProbe.app/Contents"
    install -Dm755 pinyin-ascii-input-probe "$app/MacOS/pinyin-ascii-input-probe"
    install -Dm644 ${../LICENSE} "$app/Resources/LICENSE"
    cp ${
      pkgs.writeText "PinyinASCIIInputProbe-Info.plist" (
        pkgs.lib.generators.toPlist { escape = true; } {
          CFBundleIdentifier = "org.nixconfig.pinyin-ascii.input-probe";
          CFBundleName = "PinyinASCII Input Probe";
          CFBundleExecutable = "pinyin-ascii-input-probe";
          CFBundlePackageType = "APPL";
          CFBundleVersion = "1";
          CFBundleShortVersionString = "1.0.0";
          NSHighResolutionCapable = true;
        }
      )
    } "$app/Info.plist"
    mkdir -p "$out/bin"
    ln -s "$app/MacOS/pinyin-ascii-input-probe" "$out/bin/pinyin-ascii-input-probe"
    install -m755 pinyin-ascii-ax-range pinyin-ascii-event-tap-info "$out/bin/"
    runHook postInstall
  '';

  postFixup = ''
    /usr/bin/codesign --force --sign - "$out/Applications/PinyinASCIIInputProbe.app"
    /usr/bin/codesign --force --sign - "$out/bin/pinyin-ascii-ax-range" "$out/bin/pinyin-ascii-event-tap-info"
  '';

  meta = {
    description = "Opt-in diagnostic tools for PinyinASCII";
    license = pkgs.lib.licenses.mit;
    platforms = pkgs.lib.platforms.darwin;
    mainProgram = "pinyin-ascii-input-probe";
  };
}
