# ENS/AA Change Audit (2026-02-07)

## Scope
- Reviewed staged changes across ENS package, iOS ENS service/profile flow, AA constants, RPC defaults, and package metadata.
- Focus: behavioral regressions, runtime risk, and correctness for the new commit/reveal path.

## Findings

1. **[P1] Commit-reveal timing may trigger registration too early**
   - `apps/ios/src/Views/ProfileView.swift:530`
   - `apps/ios/src/Services/AAExecutionService.swift:63`
   - `packages/aa/Sources/AA/AACore.swift:112`
   - The delay starts after user-op submission, not on confirmed commit inclusion. If the commit is mined late, `register` can revert with `CommitmentTooNew`.

2. **[P1] Sepolia AA config now allows zero addresses instead of failing fast**
   - `packages/aa/Sources/AA/Constants.swift:7`
   - `packages/aa/Sources/AA/Constants.swift:22`
   - `packages/aa/Sources/AA/SmartAccount.swift:205`
   - `packages/aa/Sources/AA/SmartAccount.swift:223`
   - Sepolia keys were added with `0x000...000` values. Lookups succeed and execution proceeds with invalid endpoints/contracts, where previous behavior would have thrown missing config.

3. **[P2] Commit step is not recoverable across app interruptions**
   - `apps/ios/src/Views/ProfileView.swift:530`
   - `apps/ios/src/Views/ProfileView.swift:542`
   - Reveal continuation is in-memory only. If app suspends/terminates during wait, there is no persisted pending job to resume registration.

4. **[P3] New progress text is not localized**
   - `apps/ios/src/Views/ProfileView.swift:537`
   - `"Commit submitted. Finalizing ENS registration..."` is hardcoded while surrounding profile strings are localized.

## Notes
- Build/tests passed during audit pass:
  - `swift test --package-path packages/ens`
  - `xcodebuild -project apps/ios/metu.xcodeproj -scheme metu -configuration Debug -sdk iphonesimulator build`
