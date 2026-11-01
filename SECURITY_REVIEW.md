# Security review

Review date: 2026-11-01. Starting source: `718dad23849fb9adcd41adcbf46f20e0548d9da4`. This delivery includes the additional fixes and tests described below.

This is a maintainer review of this bundle and its vendored source. It records confirmed findings, verification, and limits. Independent security approval remains pending; marketplace listing is a separate maintainer decision.

## Scope and method

The starting snapshot contains 115 tracked files. The inventory and searches included the bundle, both vendored components, and their diagnostic and development scripts. Manual inspection concentrated on process arguments, shell construction, filesystem permissions, IPC inputs, privilege requests, and native window callbacks. Inventory and automated searches cover more files than the manual boundary review; this is not a claim that every line or UI branch was manually verified.

| Area | Boundaries examined |
| --- | --- |
| `install.py`, `bin/`, manifests and configuration | Version checks, staging, private backups, restore paths, package holds, window addresses and geometry |
| Root `Service.qml` | IPC address validation, numeric geometry, fixed helper commands |
| `vendor/startbar/` JavaScript and QML | Window metadata, process construction, launcher inputs, clipboard reads, icon lookup, settings and IPC |
| StartBar diagnostic and development scripts | Log files, quoting, temporary state, process cleanup, nested-session guards, explicit screenshot exports |
| `vendor/hyprbars/` | Plugin compatibility check, configured commands, window activation and native callbacks; targeted static analysis of all three C++ translation units |
| Tests and documentation | Synthetic regression fixtures, documented installation scope and remaining limits |

The threat model includes another local account that can read process command lines or shared files, and untrusted text reaching a shell boundary. Installed desktop entries, user-owned configuration and explicitly sourced development tours are trusted executable inputs. The bundle runs in the desktop user's session; it does not isolate applications from that same user.

## Confirmed findings and fixes

### Window metadata in taskbar process arguments: fixed in the starting snapshot

HANCORE-linux reported that the recovery code in [DockHyprland.js](vendor/startbar/DockHyprland.js) passed complete client JSON to `jq --argjson`. Another local account with readable process command lines could observe browser or document titles during normal taskbar operations.

Recovery now reads client and monitor snapshots through anonymous pipes. Three executable regressions exercise focus, focus with pointer warp, and preview recovery using synthetic private titles and monitor descriptions. They inspect actual jq arguments and require an off-screen window to be recovered. All three failed before that fix and pass with it. This protects those argument paths; it does not hide activity from the compositor, the desktop user, or privileged processes.

### Diagnostic event logs readable by other accounts: medium, fixed in this delivery

[hypr-events.sh](vendor/startbar/scripts/hypr-events.sh) previously defaulted to `/tmp/startbar-events.log` and inherited the caller's umask. With umask `022`, it created a `0644` file containing events such as `openwindow`, which can include window titles. Other local accounts could read that file. Recording requires explicitly starting this optional diagnostic tool; normal taskbar operation does not start it.

The default log now lives in the current user's private runtime directory. The script requires an absolute, user-owned runtime directory with mode `0700`, sets umask `077`, and applies mode `0600` before recording to a new or existing log. PID state also stays in that private directory. The runtime requirements follow the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir/latest/).

### Diagnostic filename interpreted as shell code: medium, fixed in this delivery

The same script interpolated a caller-supplied log filename into the source passed to `bash -c`. A filename containing a single quote could inject a command. Exploitation required the operator or another caller to supply that crafted filename; ordinary window titles did not trigger it.

The child shell now receives a static script and separate positional arguments for the socket and log paths. A quote-containing filename is treated literally. The regression uses a harmless canary in a disposable directory and a fake event source; it does not record the real desktop or execute an attacker payload.

Four new tests cover new and existing log permissions, literal filenames, private default log and PID placement, and rejection of missing, relative or shared runtime directories. The two original reproductions failed before the patch: a log had mode `0644`, and the filename created the canary. All four tests pass after the patch.

## Capability and trust observations

- The installer requires the pinned package versions and running Hyprland commit before staging. It builds local vendored source and keeps private backups for restoration. Root execution is restricted to the documented package-hold operations; the desktop installation runs as the user.
- Start menu session actions and commands from user configuration are intentional capabilities. Desktop application entries can execute programs as that user. These inputs must not be treated as untrusted application metadata.
- No direct network-client call was found by the source searches in the reviewed runtime and helper implementation. Launched applications and platform dependencies can use the network and were not audited here.
- The nested development session shares the user's account and filesystem. Its PATH wrappers help prevent accidental power or lock actions during tests; they are not a security sandbox for hostile code. Development tours are trusted shell programs.
- Event recording and screenshot export are explicit diagnostic actions. Their output can contain private activity. Previously exported files are not removed or made private by updating the script.

## Verification

The checks below ran against this delivery; no real window titles were used in the security fixtures.

| Check | Result |
| --- | --- |
| `npm --prefix vendor/startbar test` | 367 passed, 0 failed, 0 skipped |
| `python3 -m unittest discover -s tests -v` | 14 passed |
| Bash syntax checks | 26 scripts passed |
| `omarchy plugin validate .` | Passed |
| StartBar `scripts/lint-rules.sh` | Passed |
| `python3 install.py doctor` | Passed, including 11 geometry checks and 12 package holds |
| Gitleaks scan of the working source | No findings; detection is limited to its configured patterns |
| Targeted clang-tidy analysis | No emitted diagnostics in the enabled security, Unix analyzer and unsafe-function checks across three C++ translation units |

Native analysis used the installed pinned-stack headers, C++2b, and the existing build's `-Wno-c++11-narrowing` flag. An initial invocation without that flag failed on the existing narrowing conversions; the corrected invocation completed. Diagnostics outside the selected checks were suppressed. This was not a native memory-safety test.

## Failed checks and remaining limits

- The pinned QML check still reports six existing warnings and exits unsuccessfully. No QML was changed in this delivery. The aggregate `npm run check` must not be described as passing.
- StartBar's `scripts/lint-sh.sh` cannot run because the vendored copy lacks `.githooks/pre-commit`. Direct Bash syntax checks passed; ShellCheck was not installed or run.
- Graphical checks documented in [TESTING.md](TESTING.md) passed previously and were not repeated for these diagnostic changes. No reboot or second-machine installation was tested.
- This review did not include native fuzzing, sanitizers, hostile Wayland clients, a real second-account exploit, a fresh visual audit of published screenshots, or a vulnerability audit of the operating system and transitive dependencies.
- Holding the 12 desktop packages postpones their fixes and can block dependent upgrades. Compatibility pins do not establish that a package version is free of vulnerabilities.
- Independent security review and marketplace approval remain pending. The absence of additional confirmed findings within this scope is not a security certification.
