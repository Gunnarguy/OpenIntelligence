#!/bin/sh
#
# Can Apple's model answer on an Xcode Cloud Mac? (2026-11-25, the owner: "yes add the cloud mac and probe it".)
# Every Xcode Cloud action runs on a cloud Mac, so this asks the model on that Mac directly: the machine facts, Apple's
# `fm` tool, and a small Swift program that records SystemLanguageModel's availability, retries respond() every 15 s
# for up to 5 minutes whatever the flag says (logging each error whole), and reads the Private Cloud Compute model's
# availability. It only reports; it never fails a run. ci_post_xcodebuild.sh calls it in the "Tests (manual)"
# workflow only, once per Mac. Read its lines ("[ModelProbe-Mac]") in the action's logs.

marker="${TMPDIR:-/tmp}/oi-cloud-mac-model-probe-done"
[ -f "$marker" ] && exit 0
touch "$marker"
say() { echo "[ModelProbe-Mac] $*"; }
say "macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)) model $(sysctl -n hw.model 2>/dev/null) vm=$(sysctl -n kern.hv_vmm_present 2>/dev/null) chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
if [ -x /usr/bin/fm ]; then
    /usr/bin/fm available 2>&1 | sed 's/^/[ModelProbe-Mac] fm available: /'
else
    say "no /usr/bin/fm"
fi
probe="${TMPDIR:-/tmp}/oi_model_probe.swift"
cat > "$probe" <<'SWIFT'
import Foundation
import FoundationModels

let started = Date()
func elapsed() -> Int { Int(Date().timeIntervalSince(started)) }
func describe(_ error: Error) -> String {
    var parts: [String] = []
    var current: NSError? = error as NSError
    var depth = 0
    while let ns = current, depth < 5 {
        let info = ns.userInfo.filter { $0.key != NSUnderlyingErrorKey }.map { "\($0.key)=\($0.value)" }.sorted()
        parts.append("[\(depth)] domain=\(ns.domain) code=\(ns.code) info={\(info.joined(separator: "; "))}")
        current = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        depth += 1
    }
    return "\(String(reflecting: error)) | " + parts.joined(separator: " <- ")
}
print("[ModelProbe-Mac] availability=\(SystemLanguageModel.default.availability)")
var attempt = 0
var answered = false
while !answered && elapsed() < 300 {
    attempt += 1
    let session = LanguageModelSession()
    session.prewarm()
    do {
        let reply = try await session.respond(to: "Reply with the single word OK.")
        answered = true
        print("[ModelProbe-Mac] attempt=\(attempt) elapsed=\(elapsed())s respond=ok text=\(reply.content.prefix(20))")
    } catch {
        print("[ModelProbe-Mac] attempt=\(attempt) elapsed=\(elapsed())s respond=error availability=\(SystemLanguageModel.default.availability) error=\(describe(error))")
        try? await Task.sleep(for: .seconds(15))
    }
}
print("[ModelProbe-Mac] summary attempts=\(attempt) answered=\(answered) seconds=\(elapsed())")
let pcc = PrivateCloudComputeLanguageModel()
print("[ModelProbe-Mac] pcc isAvailable=\(pcc.isAvailable) quotaLimitReached=\(pcc.quotaUsage.isLimitReached) (a command-line process, without the app's entitlement)")
SWIFT
xcrun swift "$probe" 2>&1 | sed 's/^\([^[]\)/[ModelProbe-Mac] swift: \1/' || say "the Swift probe did not run (exit $?)"
exit 0
