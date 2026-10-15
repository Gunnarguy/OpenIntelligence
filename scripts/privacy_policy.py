# One source for OpenIntelligence's privacy policy. Writes three files from the text below:
#   - the gunzino.me page, src/content/pages/openintelligence.privacy.md in the Gunzino repo;
#   - the hand-written page in the Gunzino repo, openintelligence/privacy/index.html, which is not served but which
#     Gunzino's deploy compares the built page with (scripts/verify_content.py; its README says a paragraph is changed
#     in both, or the deploy stops with LOST, which it did for 631e537);
#   - the app's PrivacyPolicyView text, starting from the committed view so the script can run again.
# Usage: python3 scripts/privacy_policy.py "$PWD" ~/Documents/GitHub/Gunzino
# The procedure around it (checking each statement against the code, Gunzino's deploy check, which version a
# statement is true of) is in Docs/ai/RUNBOOK.md, "Changing the privacy policy". Added 2026-10-15.
import html, os, re, subprocess, sys
OI, GZ = sys.argv[1], sys.argv[2]
DATE = "October 15, 2026"

INTRO = ("This policy describes how OpenIntelligence handles information. OpenIntelligence is an on-device RAG app built "
         "on Apple Intelligence: your documents are read, indexed, searched and answered from on your device unless you "
         "allow Apple's Private Cloud Compute.")

# (title, paragraphs). A paragraph starting with "- " is a list item; "**Label:** text" makes a labelled paragraph.
# Each statement was checked against the app's code on 2026-10-15; the checks are listed in the OpenIntelligence
# commit that brings this text into the app.
SECTIONS = [
    ("Overview", [
        "OpenIntelligence reads, indexes, searches and answers from your documents on your device. It sends passages from "
        "your documents to Apple's Private Cloud Compute only when you allow it, under the setting you chose. Libraries you "
        "set to iCloud Sync copy their files, passages, embeddings and conversations to your own iCloud. The app has no "
        "server of its own, and no third-party AI service, analytics, advertising or tracking code. This policy "
        "describes version 5.7, and says where earlier versions differ.",
    ]),
    ("What stays on your device", [
        "- Importing a document: reading its text, recognizing text in scans and pictures, transcribing audio, cutting "
        "it into passages, and the embeddings used to search it.",
        "- Searching, ranking, checking an answer against your documents, and answers written by Apple's on-device model.",
        "- Dictation in the chat field, from 5.7 (Apple's on-device speech recognition).",
        "- The Spotlight entries the app adds (a document's name and a short preview), notifications, Live Activities and "
        "widgets. From 5.7, turning off Spotlight Indexing in Settings removes the entries.",
        "- The app's own diagnostics and timings.",
    ]),
    ("What can leave your device, and when", [
        "**Apple Private Cloud Compute (iOS, iPadOS and macOS 27):** your question with recent conversation context, the "
        "passages chosen as evidence with their document names and page numbers, and the app's instructions to the model. "
        "Only when you allow it, under Settings, Private Cloud Compute, \"When to allow it\" (Never use, Ask when needed, "
        "or Allow without asking, which versions before 5.7 call \"Allow for Deep Think and Maximum\"). When it asks, Show Details on the prompt says why and how much would be sent. With Private Cloud Compute "
        "chosen in the model picker, answers are written there whenever it can be reached, and Deep Think's and Maximum's "
        "reasoning steps can go there too, each behind the same permission. With Hybrid (Automatic), an answer goes there "
        "when its passages don't fit in the on-device model's window, and a Deep Think or Maximum answer also goes there "
        "when it draws on more than one document. With On-Device, nothing goes there. A question asked through Siri or "
        "Shortcuts follows the same rule; when it would need your permission first, the app opens to ask (from 5.7; "
        "earlier versions write that answer on your device). The answer shows "
        "which route it used. On iOS and macOS 26, answers are always written on your device. Apple states that Private "
        "Cloud Compute deletes your data once the answer is returned, keeps none of it, and that no one but you can access "
        "it, not even Apple.",
        "**iCloud Sync (Pro and Lifetime, per library):** a library's files, passages, embeddings and conversations, "
        "copied to your own iCloud so your other devices signed in to the same Apple Account see the same library. Only "
        "for libraries you set to iCloud Sync; libraries are Local Only unless you change them.",
        "**A web page you add (from 5.7):** when you give the app a web address (Save a Web Page, the Link field of Add to Library, "
        "or a web address pasted on the Documents screen), it downloads that page from its site. The site sees an "
        "ordinary request from your device, which carries nothing from your library. No cookies are sent or kept.",
        "**Handoff:** what you have open in Chat or Documents (which library, which document, and the document's name) "
        "can be picked up on your other devices through Apple's Handoff.",
        "**The App Store rating:** about once a day the app asks Apple's public App Store lookup for its own rating. The "
        "request names the app and carries nothing about you or your documents.",
        "**Crash reports (from 5.7, on iOS and macOS 27):** when the app closes unexpectedly it keeps a report on your device and can "
        "offer to email it to the developer, and Settings, About can share the whole report. The report holds the app and "
        "system versions, the device model and the part of the app's code that was running, and none of your documents, "
        "questions or answers. It leaves your device only if you send or share it. Apple may also share crash data with "
        "developers if you allow that in your device's settings.",
        "**Purchases:** subscriptions and purchases go through Apple's App Store. The app never sees payment details.",
        "Apple's own privacy policy covers Private Cloud Compute, iCloud, Handoff and the App Store.",
    ]),
    ("Storage and retention", [
        "- **Documents and their passages:** on your device, and in your iCloud for libraries set to iCloud Sync, until "
        "you delete them. Deleting a library removes its embeddings and keyword index.",
        "- **Search cache:** past questions and the passages found for them are kept in the app's database on your "
        "device, so a question asked again is answered faster. From version 5.7 they're deleted whenever a document "
        "is added or deleted and when the app is updated. In earlier versions they stay until the app is removed.",
        "- **Backups:** your device's iCloud backup may include the app's data if backups are on.",
    ]),
    ("Your controls", [
        "- Settings, Private Cloud Compute: Never use, Ask when needed, or Allow without asking.",
        "- Each library: Local Only or iCloud Sync, in the library's settings.",
        "- Settings: Spotlight Indexing on or off.",
        "- Delete documents, libraries and conversations in the app, or remove the app.",
    ]),
    ("Children", [
        "OpenIntelligence is not directed to children under 13 and does not knowingly collect information from them.",
    ]),
    ("Contact", [
        "For privacy questions: [gunnarguy@me.com](mailto:gunnarguy@me.com)",
    ]),
]


def site_title(number, title):
    return f"{number}. {title[0].upper() + title[1:]}"


# The app's headings are in title case, as its other screens are: "What Can Leave Your Device, and When".
SMALL_WORDS = {"a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to"}


def app_title(title):
    return " ".join(w if i and w.lower() in SMALL_WORDS else w[0].upper() + w[1:]
                    for i, w in enumerate(title.split(" ")))


# 1. The website page.
page = ["---", 'title: "Privacy Policy"', f'intro: "{INTRO}"', "---", "", "## Last Updated", "", DATE, ""]
for number, (title, paragraphs) in enumerate(SECTIONS, start=1):
    page += [f"## {site_title(number, title)}", ""]
    previous_was_item = False
    for paragraph in paragraphs:
        is_item = paragraph.startswith("- ")
        if previous_was_item and not is_item:
            page.append("")
        page.append(paragraph)
        if not is_item:
            page.append("")
        previous_was_item = is_item
    if previous_was_item:
        page.append("")
open(os.path.join(GZ, "src/content/pages/openintelligence.privacy.md"), "w", encoding="utf-8").write(
    "\n".join(page).rstrip("\n") + "\n")
print("wrote the gunzino.me page")


# 2. The hand-written page the deploy compares with: the same text in the shapes that page already used.
def inline_html(text):
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)


main = ["    <main>", '    <section class="support-hero">', "        <h1>Privacy Policy</h1>",
        f"        <p>{inline_html(INTRO)}</p>", "    </section>", "",
        '    <section class="support-section">', "        <h2>Last Updated</h2>", f"        <p>{DATE}</p>"]
for number, (title, paragraphs) in enumerate(SECTIONS, start=1):
    main += ["", f"        <h2>{html.escape(site_title(number, title), quote=False)}</h2>"]
    in_list = False
    for paragraph in paragraphs:
        if paragraph.startswith("- "):
            if not in_list:
                main.append("        <ul>")
                in_list = True
            main.append(f"        <li>{inline_html(paragraph[2:])}</li>")
        else:
            if in_list:
                main.append("        </ul>")
                in_list = False
            main.append(f"        <p>{inline_html(paragraph)}</p>")
    if in_list:
        main.append("        </ul>")
main += ["    </section>", "    </main>"]
legacy = os.path.join(GZ, "openintelligence/privacy/index.html")
s = open(legacy, encoding="utf-8").read()
start, end = s.index("    <main>"), s.index("    </main>") + len("    </main>")
assert s.count("    <main>") == 1 and s.count("    </main>") == 1
open(legacy, "w", encoding="utf-8").write(s[:start] + "\n".join(main) + s[end:])
print("wrote the hand-written page")


# 3. The app's view: one `section` per section, the paragraphs joined with blank lines, list items with bullets.
def swift_text(paragraphs):
    parts = []
    for paragraph in paragraphs:
        text = paragraph.replace("[gunnarguy@me.com](mailto:gunnarguy@me.com)", "Gunnarguy@me.com")
        if text.startswith("- "):
            text = "• " + text[2:]
        parts.append(text)
    joined = ""
    for i, text in enumerate(parts):
        if i:
            joined += "\n" if (text.startswith("• ") and parts[i - 1].startswith("• ")) else "\n\n"
        joined += text
    assert '"""' not in joined and "\\(" not in joined
    return joined.replace("\\", "\\\\")


swift_sections = [
    f'                        section(title: "{app_title(title)}", content: """\n{swift_text(paragraphs)}\n""")\n'
    for title, paragraphs in SECTIONS]

rel = "OpenIntelligence/Features/Billing/PrivacyPolicyView.swift"
s = subprocess.check_output(["git", "show", f"HEAD:{rel}"], cwd=OI, text=True)
start = s.index('                    Text("Last updated:')
end_marker = "                    }\n                }\n                .padding(24)"
assert s.count(end_marker) == 1
end = s.index(end_marker)
new_block = (f'                    Text("Last updated: {DATE}")\n'
             '                        .font(.caption)\n'
             '                        .foregroundStyle(.secondary)\n\n'
             '                    Divider()\n\n'
             '                    // The same text as gunzino.me/openintelligence/privacy, from one source (5.7). Through\n'
             '                    // 5.6 this view had its own text: dated May 2026, naming third-party providers the app\n'
             '                    // does not have and a Settings → Privacy that does not exist, with one sentence cut off.\n'
             '                    Group {\n' + "".join(swift_sections) + "                    }\n")
s = s[:start] + new_block + s[end + len("                    }\n"):]
a = """            Text(content)
                .font(.body)"""
b = """            // `LocalizedStringKey` renders the **bold** labels; `Text(String)` showed the asterisks (5.7).
            Text(LocalizedStringKey(content))
                .font(.body)"""
if b not in s:  # applied from a9b682b on, where the script starts from a view that has it
    assert s.count(a) == 1
    s = s.replace(a, b)
c = """        .accessibilityElement(children: .contain)
    }

    private func section("""
d = """        .accessibilityElement(children: .contain)
        #if os(macOS)
            // A Mac sheet takes its size from its content, and a ScrollView has almost none of its own
            // (`ContainerSettingsSheet` has the same note). Settings, About opens this as a sheet (5.7).
            .frame(minWidth: 520, idealWidth: 640, maxWidth: 800, minHeight: 560, idealHeight: 720, maxHeight: .infinity)
        #endif
    }

    private func section("""
if d not in s:
    assert s.count(c) == 1
    s = s.replace(c, d)
open(os.path.join(OI, rel), "w", encoding="utf-8").write(s)
print("wrote PrivacyPolicyView.swift")
