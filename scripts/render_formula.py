#!/usr/bin/env python3

from __future__ import annotations

import argparse


def build_formula(version: str, sha256: str) -> str:
    repo = "https://github.com/kingsmen732/mac-fan-system"
    return f"""class MacFanSystem < Formula
  desc "Apple Silicon Mac fan RPM CLI backed by AppleSMC"
  homepage "{repo}"
  url "{repo}/archive/refs/tags/{version}.tar.gz"
  sha256 "{sha256}"
  license "MIT"
  head "{repo}.git", branch: "main"

  depends_on "python@3.12"

  def install
    python3 = Formula["python@3.12"].opt_bin/"python3"

    libexec.install "main.py"
    libexec.install "native"

    system ENV.cc, "-dynamiclib", "-fPIC", "-O2", "-Wall", "-Wextra",
           "-framework", "Foundation",
           "-framework", "IOKit",
           "-framework", "CoreFoundation",
           "-L/usr/lib",
           libexec/"native/smc_bridge.c",
           libexec/"native/fan_bridge.m",
           "-lIOReport",
           "-o", libexec/"libfanbridge.dylib"

    (bin/"mac-fan-system").write <<~SH
      #!/bin/bash
      export MAC_FAN_SYSTEM_NATIVE_LIB="#{{libexec}}/libfanbridge.dylib"
      exec "#{{python3}}" "#{{libexec}}/main.py" "$@"
    SH
  end

  test do
    output = shell_output("#{{bin}}/mac-fan-system --json 2>&1")
    assert_match "\\"fans\\"", output
  end
end
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Render a Homebrew formula for a tagged release.")
    parser.add_argument("--version", required=True, help="Git tag version, for example v0.1.0")
    parser.add_argument("--sha256", required=True, help="SHA256 for the release tarball")
    args = parser.parse_args()

    print(build_formula(args.version, args.sha256))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
