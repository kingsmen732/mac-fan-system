class MacFanSystem < Formula
  desc "Apple Silicon Mac fan RPM CLI backed by AppleSMC"
  homepage "https://github.com/kingsmen732/mac-fan-system"
  head "https://github.com/kingsmen732/mac-fan-system.git", branch: "main"

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
      export MAC_FAN_SYSTEM_NATIVE_LIB="#{libexec}/libfanbridge.dylib"
      exec "#{python3}" "#{libexec}/main.py" "$@"
    SH
  end

  test do
    output = shell_output("#{bin}/mac-fan-system --json 2>&1")
    assert_match "\"fans\"", output
  end
end
