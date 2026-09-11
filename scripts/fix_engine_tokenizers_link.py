#!/usr/bin/env python3
"""Add the transitive `Tokenizers` product to the OpenIntelligenceEngine target's link line.

WHY THIS EXISTS
---------------
`xcodebuild test` cannot link `OpenIntelligenceEngine.framework`. Every `Tokenizers.*` symbol
comes back undefined:

    Undefined symbol: static Tokenizers.AutoTokenizer.from(directory:) ...
    Undefined symbol: type metadata for Tokenizers.TokenizerError

The cause is one level deeper than a missing dependency, and the target's existing declaration is
correct, so reading the target block does not reveal it:

  * `OpenIntelligence/swift-transformers` is a **shim** package. Its only source file is
    `@_exported import Tokenizers`. It contains no code of its own.
  * The real module, `Tokenizers`, comes from a **separate remote package**,
    `https://github.com/DePasqualeOrg/swift-tokenizers.git`, pinned at 0.7.1.
  * Four Engine sources (`CoreAISentenceEmbeddingProvider`, `CoreMLSentenceEmbeddingProvider`,
    `RAGEngine`, `DocumentProcessor`) `import Tokenizers` directly, not the shim.
  * The Engine target declares only `TransformersTokenizers`, so Xcode puts only
    `TransformersTokenizers_<hash>_PackageProduct.framework` on the link line.
    `Tokenizers_<hash>_PackageProduct.framework` is built, and sits unused in the same
    `PackageFrameworks` directory.

Xcode links a product's transitive package dependencies into an **application** target but not
into a **framework** target. That is why the app, `scripts/build_simulator_smoke.sh` and Xcode
Cloud are all fine, and only the test action fails: the test bundle is the one thing that links
the Engine as a standalone unit.

Verified 2026-09-10 by forcing the missing framework onto the Engine's link line with a
command-line `OTHER_LDFLAGS`; the Engine framework then linked, and the only remaining failure
was the Tokenizers product linking against itself, which is an artefact of a command-line
override applying to every target and is exactly what this script avoids.

WHAT IT CHANGES
---------------
`OpenIntelligence.xcodeproj/project.pbxproj`, which is a hard-boundary file under CLAUDE.md.
Run this only after deciding to make that edit. It writes a `.bak` first and refuses to run twice.

  1. a `PBXBuildFile` for the `Tokenizers` product
  2. an `XCSwiftPackageProductDependency` named `Tokenizers`, with no `package` key, which is how
     Xcode records a product resolved from the package graph rather than a direct reference
  3. that build file appended to the Engine target's existing Frameworks build phase
  4. that product appended to the Engine target's `packageProductDependencies`

Nothing else is touched. The app target is left exactly as it is.

USAGE
-----
    python3 scripts/fix_engine_tokenizers_link.py --check    # report, change nothing
    python3 scripts/fix_engine_tokenizers_link.py --apply    # write the change

Then:

    xcodebuild test -scheme OpenIntelligence \
      -destination "platform=iOS Simulator,id=25E29FA1-6A22-4A86-AE9F-A6F48411E6D0" \
      -derivedDataPath /private/tmp/oi-build

To undo, restore the `.bak` this script writes beside the file.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PBXPROJ = ROOT / "OpenIntelligence.xcodeproj/project.pbxproj"


def set_target_project(path: Path) -> None:
    """Point the script at a different .xcodeproj.

    Exists so the change can be proved against a throwaway copy of the project before anyone
    edits the real one. A copy placed beside the original resolves the same relative source
    paths, so it builds and tests identically.
    """
    global PBXPROJ
    PBXPROJ = path / "project.pbxproj" if path.suffix == ".xcodeproj" else path

ENGINE_TARGET = "E0A100072F0F5F5F00AABA0C"
ENGINE_FRAMEWORKS_PHASE = "E0A100062F0F5F5F00AABA0C"

# Stable ids chosen to be absent from the file; verified before use rather than assumed.
BUILD_FILE_ID = "E0A100302F0F5F5F00AABA0C"
PRODUCT_DEP_ID = "E0A100312F0F5F5F00AABA0C"

PRODUCT = "Tokenizers"


def read() -> str:
    if not PBXPROJ.exists():
        sys.exit(f"not found: {PBXPROJ}")
    return PBXPROJ.read_text()


def already_applied(src: str) -> bool:
    """True when the Engine target already declares the Tokenizers product.

    Matches the target's own `packageProductDependencies` block rather than the whole file,
    because `TransformersTokenizers` contains the string `Tokenizers` and a naive search finds
    it everywhere.
    """
    block = engine_target_block(src)
    deps = re.search(r"packageProductDependencies = \((.*?)\);", block, re.S)
    if not deps:
        return False
    return bool(re.search(r"/\* Tokenizers \*/", deps.group(1)))


def engine_target_block(src: str) -> str:
    """The whole PBXNativeTarget block for the Engine. No character cap, deliberately.

    A capped regex over this file is what produced a confidently wrong diagnosis on 2026-09-10:
    the window ended before `packageProductDependencies` and its absence was reported as the
    target not declaring the dependency.
    """
    start = src.find(f"{ENGINE_TARGET} /* OpenIntelligenceEngine */ = {{")
    if start < 0:
        sys.exit(f"Engine target {ENGINE_TARGET} not found; the project layout has changed")
    end = src.find("\n\t\t};", start)
    if end < 0:
        sys.exit("could not find the end of the Engine target block")
    return src[start:end]


def preflight(src: str) -> None:
    for ident in (BUILD_FILE_ID, PRODUCT_DEP_ID):
        if ident in src:
            sys.exit(f"id {ident} is already used in the project; pick another before applying")
    if f"{ENGINE_FRAMEWORKS_PHASE} /* Frameworks */" not in src:
        sys.exit(f"Engine Frameworks phase {ENGINE_FRAMEWORKS_PHASE} not found")
    block = engine_target_block(src)
    if "packageProductDependencies = (" not in block:
        sys.exit(
            "the Engine target has no packageProductDependencies block. That is NOT the defect "
            "this script fixes, so it refuses rather than guessing at the right edit."
        )


def apply(src: str) -> str:
    # 1. PBXBuildFile entry, placed beside the existing TransformersTokenizers ones.
    anchor = "/* End PBXBuildFile section */"
    entry = (
        f"\t\t{BUILD_FILE_ID} /* {PRODUCT} in Frameworks */ = {{isa = PBXBuildFile; "
        f"productRef = {PRODUCT_DEP_ID} /* {PRODUCT} */; }};\n"
    )
    src = src.replace(anchor, entry + anchor, 1)

    # 2. The product dependency itself. No `package` key: the product is resolved from the
    #    package graph via the local swift-transformers reference, which depends on it.
    anchor = "/* End XCSwiftPackageProductDependency section */"
    entry = (
        f"\t\t{PRODUCT_DEP_ID} /* {PRODUCT} */ = {{\n"
        f"\t\t\tisa = XCSwiftPackageProductDependency;\n"
        f"\t\t\tproductName = {PRODUCT};\n"
        f"\t\t}};\n"
    )
    src = src.replace(anchor, entry + anchor, 1)

    # 3. Into the Engine's Frameworks build phase.
    phase = re.search(
        rf"({re.escape(ENGINE_FRAMEWORKS_PHASE)} /\* Frameworks \*/ = \{{.*?files = \()(.*?)(\);)",
        src,
        re.S,
    )
    if not phase:
        sys.exit("could not parse the Engine Frameworks build phase")
    src = (
        src[: phase.start(2)]
        + phase.group(2).rstrip("\t\n ")
        + f"\n\t\t\t\t{BUILD_FILE_ID} /* {PRODUCT} in Frameworks */,\n\t\t\t"
        + src[phase.end(2) :]
    )

    # 4. Into the Engine target's packageProductDependencies.
    start = src.find(f"{ENGINE_TARGET} /* OpenIntelligenceEngine */ = {{")
    deps = re.compile(r"(packageProductDependencies = \()(.*?)(\);)", re.S).search(src, start)
    if not deps:
        sys.exit("could not parse the Engine target's packageProductDependencies")
    src = (
        src[: deps.start(2)]
        + deps.group(2).rstrip("\t\n ")
        + f"\n\t\t\t\t{PRODUCT_DEP_ID} /* {PRODUCT} */,\n\t\t\t"
        + src[deps.end(2) :]
    )
    return src


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true", help="report state, change nothing")
    mode.add_argument("--apply", action="store_true", help="write the change, after a .bak")
    ap.add_argument(
        "--project",
        type=Path,
        help="operate on this .xcodeproj instead of the repository's own, for verifying the "
        "change against a throwaway copy before editing the real one",
    )
    args = ap.parse_args()

    if args.project:
        set_target_project(args.project.resolve())
        print(f"Operating on {PBXPROJ}")

    src = read()

    if already_applied(src):
        print("Already applied: the OpenIntelligenceEngine target declares the Tokenizers product.")
        return 0

    preflight(src)

    if args.check:
        print("NOT applied. The Engine target declares TransformersTokenizers (the shim) only.")
        print("Run with --apply to add the transitive Tokenizers product to its link line.")
        return 1

    backup = PBXPROJ.with_suffix(".pbxproj.bak")
    shutil.copy2(PBXPROJ, backup)
    out = apply(src)
    PBXPROJ.write_text(out)

    if not already_applied(PBXPROJ.read_text()):
        shutil.copy2(backup, PBXPROJ)
        sys.exit("the edit did not verify after writing; the original has been restored")

    print(f"Applied. Backup at {backup.relative_to(ROOT)}")
    print("Now run the test action; it should reach ** TEST SUCCEEDED **:")
    print(
        '  xcodebuild test -scheme OpenIntelligence -destination '
        '"platform=iOS Simulator,id=25E29FA1-6A22-4A86-AE9F-A6F48411E6D0" '
        "-derivedDataPath /private/tmp/oi-build"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
