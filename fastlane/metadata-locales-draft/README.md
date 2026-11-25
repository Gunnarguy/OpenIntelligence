# Store listing translations for 5.9 (drafts)

Drafted 2026-11-24 for the roadmap row "The App Store listing is in US English only, while 61% of first-time downloads
come from outside the US" (v5.9), at the owner's word ("Yes, send it"; "for 5.9 ... once all the benchmarking tests are
done"). de-DE, fr-FR, es-ES, pt-BR, ja, zh-Hans, zh-Hant. `mac/<locale>/` holds name, subtitle, keywords, promotional
text and description; `ios/<locale>/` holds the iPhone and iPad promotional text, which differs, as in `metadata-ios/`.

They sit outside `fastlane/metadata/` on purpose: `deliver` uploads every locale folder it finds there, and a language
can only be added to a version that is still editable. They move into `metadata/` and `metadata-ios/` when the 5.9
record exists, at the owner's yes.

Before they move: the description's "MEASURED IN 5.8" section is replaced with the 5.9 numbers in en-US and then in
each language; every figure is checked against `Docs/ai/CLAIMS.json`; a reviewer per language reads them against the
English for any change of meaning; and Apple's 4,000 limit is confirmed as characters (es-ES and pt-BR are 3,994
characters but over 4,000 bytes). Every locale keeps the offline claim at full strength and says the app's interface is
in English. `apple` and `intelligence` are left out of the new keyword lists as a trademark precaution.
