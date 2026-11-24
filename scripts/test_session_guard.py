#!/usr/bin/env python3
"""Check session-loss recovery and preserve the site's login decisions."""
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parent.parent
sources = {file.name: file.read_text(encoding="utf-8") for file in (root / "DouDuo").glob("*.swift")}
all_source = "\n".join(sources.values())
login = sources["DYAppLogin.swift"]
failures = 0


def check(ok, name):
    global failures
    print(("PASS " if ok else "FAIL ") + name, flush=True)
    if not ok:
        failures += 1


check("DYLogoutBlock" not in all_source and "dd-block-web-logout-v1" not in all_source,
      "site logout requests are not intercepted")
check("DYTrustLogin" not in all_source and "__ddTrustAuto" not in all_source,
      "trust decisions are not automated")
trust_prompt = login.split("private func waitForTrustPrompt()", 1)[-1].split("private func hasNewSession()", 1)[0]
check(".trust-login-dialog-button-confirm" in trust_prompt and ".click(" not in trust_prompt
      and "page.needsWeb || page.showsTrustPrompt" in login,
      "native login reveals the website's trust prompt for the user")
check("DYSessionWatch.shared.start()" in sources["DouDuoApp.swift"], "watch starts at launch")
check("DYSessionWatch.shared.suppressed += 1" in sources["DYAccounts.swift"], "account changes suppress loss alerts")
check("loginScreenOpen = true" in login, "login screen suppresses loss alerts")
check("DYSessionLostAlert" in sources["DouyinFeedView.swift"], "root shows a session-loss alert")
check("sessionGone" in sources["DYRelogin.swift"] and 'Button("重新登录")' in sources["DYRelogin.swift"],
      "comment recovery offers relogin when the session is gone")

swift = shutil.which("swift")
if swift:
    function = re.search(r"(    nonisolated static func isLoss.*?\n    \})",
                         sources["DYSessionGuard.swift"], re.S)[1].replace("nonisolated ", "")
    with tempfile.TemporaryDirectory() as directory:
        source = Path(directory) / "SessionGuard.swift"
        source.write_text("enum SessionWatch {\n" + function + "\n}\n" + """
precondition(SessionWatch.isLoss(before: "a", now: nil, suppressed: false))
precondition(!SessionWatch.isLoss(before: "a", now: nil, suppressed: true))
precondition(!SessionWatch.isLoss(before: nil, now: nil, suppressed: false))
precondition(!SessionWatch.isLoss(before: "a", now: "b", suppressed: false))
precondition(!SessionWatch.isLoss(before: nil, now: "b", suppressed: false))
""", encoding="utf-8")
        check(subprocess.run([swift, str(source)], check=False).returncode == 0, "session-loss classification")
else:
    print("SKIP session-loss classification (Swift is unavailable)")

raise SystemExit(bool(failures))
