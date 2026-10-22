# SPDX-License-Identifier: MIT
{
  pkgs,
  homeManagerConfiguration,
  module,
}:
let
  evaluate =
    modules:
    homeManagerConfiguration {
      inherit pkgs;
      modules = [
        {
          home.username = "fixture";
          home.homeDirectory = "/Users/fixture";
          home.stateVersion = "26.05";
        }
      ]
      ++ modules;
    };
  baseline = evaluate [ ];
  disabled = evaluate [ module ];
  enabled = evaluate [
    module
    { services.apple-pinyin-ascii-punctuation.enable = true; }
  ];
  agent = enabled.config.launchd.agents.pinyin-ascii;
  package = enabled.config.services.apple-pinyin-ascii-punctuation.package;
in
# Importing the module alone must not install or start the converter.
assert !disabled.config.services.apple-pinyin-ascii-punctuation.enable;
assert map toString disabled.config.home.packages == map toString baseline.config.home.packages;
assert disabled.config.launchd.agents == baseline.config.launchd.agents;
assert agent.enable;
assert builtins.elem package enabled.config.home.packages;
assert agent.config.Label == "org.nix-community.home.pinyin-ascii";
assert
  agent.config.ProgramArguments == [
    "${package}/Applications/PinyinASCII.app/Contents/MacOS/pinyin-ascii"
  ];
assert agent.config.StandardErrorPath == "/Users/fixture/Library/Logs/pinyin-ascii.log";
assert agent.config.RunAtLoad && agent.config.KeepAlive;
assert agent.config.ThrottleInterval == 10;
pkgs.runCommand "pinyin-ascii-module-check" { } ''
  touch "$out"
''
