# Localization Practices (Project Rule)

## Scope
Applies to all UI and user-facing text in `apps/ios`.

## Required Rules
1. Never ship hardcoded user-facing English in SwiftUI views.
2. Every localization key used in code must exist in `en.lproj/Localizable.strings`.
3. Every non-English locale file must have the exact same key set as `en.lproj/Localizable.strings`.
4. Prefer reusing existing keys over creating new duplicate keys with the same meaning.
5. New keys must be added to all locale files in the same change.
6. Avoid leaving non-English locales with English fallback text, except explicit allowlisted placeholders/technical labels.

## Enforcement
Run before finalizing localization-related changes:

```bash
python3 /Users/peter/Developer/knot/apps/ios/scripts/localization_audit.py --root /Users/peter/Developer/knot
```

For release-hard checks (fail if any untranslated non-EN value remains):

```bash
python3 /Users/peter/Developer/knot/apps/ios/scripts/localization_audit.py --root /Users/peter/Developer/knot --strict-untranslated
```

## Notes
- Keep placeholder keys (`0x...`, URLs, protocol names, etc.) intentionally stable.
- If a string is intentionally not translated, document and allowlist it in the audit script.
