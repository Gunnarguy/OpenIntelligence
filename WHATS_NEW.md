> **Documentation status:** Current through OpenIntelligence v5.6, live on both platforms since October 8, 2026; the 5.7 section is the release in preparation. Entries are drawn from `Docs/USER_CHANGELOG.md`, which is the source this file follows.

# What's New

Public release highlights for OpenIntelligence.

## 5.7
This one's about getting things in and out of the app.  JSON and JSONL files import as records, Siri and Shortcuts can ask, search and add to your libraries, Spotlight and Visual Intelligence find your documents, and an answer you share takes its sources with it.

### Your Documents
- **A new library filled by one very large file doesn't ask to be rebuilt.**  When the first thing in a library was a PDF over 10 MB or a big text or JSONL file, the library asked to rebuild its search index the first time you asked it something, right after it had been built.  It doesn't now.
- **JSON and JSONL files import as records.** A .json, .jsonl or .ndjson file used to come in as one long run of raw text, and a .jsonl file couldn't even be chosen in the file picker.  Now each record is its own passage, with its field names and its numbers kept exactly as the file has them, so a chat export, a log or a dataset can be searched and cited one record at a time.  A line that isn't valid JSON is kept the way it was written.
- **OpenIntelligence shows up under "Open in".** A PDF, a text or Markdown file, a CSV, a JSON file, a Word, Excel or PowerPoint file or an image can be sent to the app from Files, Mail or a share sheet, and on the Mac by dropping it on the app's icon.  It shows you the file first: tap it to look through it, choose the library it goes to, then Add, or Don't Add and nothing is kept.  A file you add goes through the same import check as a file you pick in the app.
- **Long passages are stored the way your document wrote them.** When a passage was too long to index in one piece, the app split it and re-typed it on the way, so "$75.50" could be stored as "$75. 50" and a question mark could become a period.  Now it's cut at line and sentence ends and nothing is re-typed.  A document you already imported keeps the old text until it's imported again.
- **A long passage isn't cut short before it's indexed.** In a large PDF or text file, a passage a little too long for the search model was cut to its first 1,500 characters before it was indexed, which is about two thirds of what the model can read.  The text itself was always stored whole.  Now it's only cut where the model's limit really is.
- **Paste into a library.** The Documents screen has a Paste button.  A file you copied is copied in, a web address is downloaded the same way "Save a Web Page" does it, and text is saved as a note.  A copied PDF or picture works too.  Whatever you paste goes through the same import check as a file you pick.  On iPhone and iPad, iOS may ask you to allow the paste when what you copied came from another app.
- **Share to OpenIntelligence.**  On iPhone and iPad, OpenIntelligence is in the share sheet for a web page or text you've selected.  Tap Add, and the next time you open the app it's added to the library you have open: the page is downloaded and saved the way "Save a Web Page" does it, and text is saved as a note.  A file still goes in with Open in.
- **Big text files don't freeze the app anymore.** A big text file used to freeze the app while it imported, sometimes for minutes, and iOS could close the app while it was stuck.  The step that cuts a file into passages was re-reading the rest of the file for every passage, and it ran on the same thread as the screen.  Now it reads each part once and runs in the background, the import shows how far along it is, and Cancel works while it runs.
- **Very large text and JSONL files import a piece at a time.** A text or JSONL file used to be read, cleaned up and cut into passages all at once.  An 88 MB JSONL file with 189,579 records took 2.8 GB of memory that way on an iPhone, and iOS closed the app before it was a fifth done.  Now a file over 8 MB is read a few megabytes at a time, and each piece is indexed and saved before the next one starts, so the whole file is never held in memory at once.  A JSONL file keeps its record numbers across the whole file, and its short records share a passage instead of each taking one.
- **An interrupted import picks up where it was.** Each saved piece of a large text or JSONL file is a checkpoint.  If the phone locks or you leave the app, the import continues from the last saved piece when you come back, and it doesn't ask.  If iOS closed the app, Resume does the same.  The screen also stays on while an import is running, so the phone doesn't lock itself in the middle of one.
- **iCloud sync waits for an import to finish.** While a large file was importing, iCloud sync went back and read the whole library again after every piece, at least 135 times in one import of mine, and that slowed the import down.  In a library that already had other documents, it could also have saved the library without the file that was still coming in.  Now sync leaves a library alone until its import is done.
- **A file that's too long says so.** A text or JSONL file of any length now comes in a piece at a time (above).  For other kinds of files, one document can hold 50,000 passages, and a longer one used to be cut off there without telling you.  Now the import stops with a message that says to split the file into smaller ones.
- **The Atlas opens on a very large library.** The Atlas used to read every passage in a library before it drew anything, and on a library with tens of thousands of passages iOS could close the app while it was working.  Now a library with more than 6,000 passages is mapped from 6,000 of them, taken evenly from across the whole library, and the Atlas tells you when it's showing a sample.  Sorting those passages and laying out the 3D map, which took seconds on a large library, run in the background now instead of holding up the screen, and the Content Breakdown reads whole words, so "capital" no longer counts as technical writing because it has "api" in it.
- **The Atlas map finishes on a very large file.** With one very large file in a library, the map stayed on "Mapping semantic space…" and never drew.  Two of the things it shows were being worked out from every character of the file, 88 million of them in mine.  Now they're worked out from an even sample of the text, and the map draws.
- **The Atlas names things from your own documents.** Cluster names used to come from a built-in list of subjects.  One library of mine got three clusters that were all called "API Reference", the names changed from one launch to the next, and the axes were labelled "Return", "Document" and "Text".  Now a cluster is named by the words that set it apart from the rest of the library, no two clusters share a name, each axis is labelled at both ends, and the same library gives the same map every time.  There's no list of subjects behind it anymore and nothing in it is tied to English, so it works from whatever your files say.  On another library of mine every name still came out as two words starting with A ("Agent & Alert", "Annual & App"), because a word in three passages counted the same as one in all of them and ties went alphabetically.  Now the words most of a cluster's passages share come first.  On my library of instructions for use, one end of an axis still had no words at all, and another read "Blade & Gently".  Now an end is named by words that set its passages apart even when only two of them share one, an end with none is marked "Component" instead of being left blank, an adverb like "gently" doesn't name an end, and no word names two ends.  For a library in French, German, Italian, Portuguese, Spanish, Turkish or Chinese, the app asks your device to load that language's word classes when it doesn't have them yet, so the same goes there.
- **The Atlas's 3D map keeps all three axes on screen.**  When you turned the map, an axis could slide off the edge of the screen and take its labels with it, and every change on the page put the map back where it started.  Now the map starts far enough out that each axis stays in view as you turn it, though a long name at its end can still run past the edge of a narrow screen, and it stays at the angle you leave it until you change what it shows or a setting.  Each end of each axis and each cluster is still named right in the map.  If you'd rather have a plain cube with the axis names in a key under it, pick Chart under Map in the Atlas's settings.  The full screen view has an All Libraries choice that shows your libraries in one map, each in its own color and named in the map, so you can see how they sit next to each other.  A library made with a different embedding model can't share that map, and the view says which ones it leaves out.  The Atlas also missed anything imported while it was open until you left the tab and came back.  It updates when the import finishes now, and the 3D Semantic Map tile, which didn't open anything, opens the full screen map.
- **A very large library doesn't hold the app up.** With 144,247 passages in one library on my iPhone, the app read the whole library twice every time it opened, iCloud sync compared both copies of it passage by passage, opening Chat scored every passage to come up with suggested questions, and the first question ran a grammar step over every passage before it started.  Now the library is read once, sync skips the comparison when nothing has changed, and those steps work from an even sample of a large library.  The app was also measuring the whole library again every time it opened (its languages, its vocabulary, how long its sentences are), for the analysis it shows in Library Settings.  Now it measures a sample of a large library, keeps the result, and only measures again when the library changes.  The grammar step before the first question is kept the same way.  Opening a library that size still takes a few seconds.
- **Numbers in tables are kept.** A table cell that held only a small number, a year or a part code, like "34", "2024" or "SKU10293", was dropped when the file was imported, so a question about it had nothing to find.  That happened in CSV files, spreadsheets and tables in PDFs.  Those cells are kept now.  A table you imported before needs importing again to get them back.
- **A deleted document or library stays deleted.** With two windows open on the Mac, a document or a library you deleted in one could show up again later, and a library could also come back on its own right after you deleted it.  Both stay deleted now.
- **Two switches in Developer & Diagnostics stay as you set them.**  Pipeline Trace and Force Reasoning Chain went back to what they were the next time the app opened, because changing one of them wasn't saved.  Both are saved as soon as you change them now.
- **You can undo a delete.**  A document you delete leaves the library right away, and an Undo button shows at the bottom of the screen for a few seconds.  Tap it and the document's back where it was.  Otherwise it's deleted when the seconds are up, or as soon as you leave the app.
- **Swipe a document to delete it.**  On iOS 27 and macOS 27 a document in the library can be swiped away.  Like any delete it can be undone for a few seconds, and a document in an iCloud library still asks first.
- **Pause an import.**  The import queue has a Pause button now.  A large file that's saved in pieces goes on from where it stopped when you continue, and any other file starts over, and the queue says which.  Waiting files wait too, until you continue or discard them.
- **Leftover text from an unfinished import is cleaned up.**  When the app closed in the middle of an import, the document's text stayed in the search index with no document to go with it.  Now it's removed the next time the app opens.  And when you stop an import, the app's copy of the file goes too, so choosing the same file again keeps its name instead of getting a "-2".
- **Text printed sideways along a page's edge stays out.**  A journal's "Downloaded from" line runs down the edge of every page of some papers, and it was read into the page's text, where it could start a passage or become a heading.  It's left out now.
- **Addresses, phone numbers and amounts are found everywhere in a document.**  Since 5.3 the app has used Apple's own detector to recognise addresses, phone numbers, dates and amounts of money, but it only ever looked in tables.  Now it reads the whole document, so an address in a paragraph of a lease or a phone number in a manual's text counts too.
- **A code in a picture is read, not guessed.**  When the app describes a picture in a document, or a photo you import, it now reads any QR code or barcode in it with Apple's Vision and writes down what it holds.  Before, Apple's model was left to read the code from the picture, and in a test on my Mac it made up a link the code didn't hold.
- **Keyword search covers every page of a large PDF.** A PDF over 10 MB is read fifteen pages at a time, and each batch numbered its passages from zero.  The keyword index files a passage under its document and that number, so a passage from a later batch that reused a number wasn't stored.  Search by meaning still had it, but an exact word or a part number on a later page could be missed.  The numbering carries on through the whole file now.  Search by page had the same kind of gap: each batch cleared the pages before it, so only the last fifteen pages of a large PDF could be found that way.  Every page is kept now.  A large PDF you imported before needs importing again to get those passages back into keyword search.
- **Pages in Greek, Chinese, Arabic and other scripts keep their text.** The step that clears junk lines out of a PDF page only counted unaccented Latin letters and Cyrillic letters as letters, so a line in another script looked like symbols and was removed.  It counts letters in every script now.  And a PDF in Greek, Hebrew or another script that Apple's text recognition doesn't read is read from its own text, where a check that compares the page with a scan of it used to throw that text away.
- **Text files that aren't UTF-8 come in readable.** A text file saved as Shift-JIS, GB 18030, Windows-1251 or UTF-16 used to come in as rows of accented letters and symbols, because anything that wasn't UTF-8 was read as Latin-1.  Now the app uses Apple's own detection to work out how the file was saved and reads it that way.
- **A recording's name doesn't pick the wrong language.** The app took the language of a recording from two letters in its file name, so "notes_friday.m4a" was transcribed as French and "plans_december.m4a" as German.  Now the two letters have to be the last word of the name, like "lecture_fr.m4a", or the language has to be spelled out.
- **Recordings use Apple's newer transcriber.** The app had code for Apple's long-form speech transcriber that was never actually built into it, so every audio or video file went through the older recognizer.  Now a recording goes to the newer one first, and to the older one if the newer one can't take it.  On iOS 27 and macOS 27 the newer one also reads audio the app couldn't open before, and when a video has more than one sound track, it tries each one until it finds speech.  Both run on your device.
- **Import progress counts each document once.** The progress your iPhone shows for an import that keeps going in the background could read 100% the moment one document finished, with more still to go, and then drop back.  Now each document counts once, the Live Activity's count goes up as documents finish instead of starting over, and Check Import Status says how far along the import is.
- **Pictures are described from the picture.** When you import a document with figures, or a photo, the app asks Apple's model for a sentence or two about each picture so search can find it.  It turns out the picture itself was never sent, only the labels another tool had guessed for it.  On iOS 27 and macOS 27 the model is shown the image now, on your device.
- **New libraries on iPhone and iPad use the faster copy of the search model.** The app carries two copies of the model that turns passages into something it can search by meaning.  I timed both on an iPhone 16 Pro Max, the model alone.  The one new libraries had been using did about 88 passages a second, and the other did about 100 to 120 depending on the setting.  On the processor alone the first one managed 5 a second and the second one 84.  New libraries on iPhone and iPad use the second one now.  A library you already have keeps the one it was built with, because changing it would mean indexing the whole library again.  Library Settings and the sample documents used to say the model ran on the Neural Engine either way.  They say which copy runs where now, and the Default badge sits on the copy your device uses for a new library.
- **An import stops if the search model comes back empty.**  If the model that turns passages into something the app can search by meaning handed back empty results, the app stored them anyway, and the library looked fine but could only be searched by its words.  Now the import stops and says so, and a library that was already built that way is rebuilt when you open it.
- **A document that went missing from search comes back.**  A document could stay listed in a library with nothing of it left in search, so no question could find it.  One of mine had 455 passages and none of them were searchable.  Opening the library now finds a document like that and rebuilds it.
- **Import a whole folder.**  Drop a folder on the Documents screen, or choose one when you add documents on the Mac, and the files inside it that the app can read come in, from the folders inside it too.  A folder used to be refused.
- **Word counts are right.**  A document's word count split words at spaces only, so a line break joined two words into one, and it added up the document's passages, which counted the words two passages share twice.  Both are fixed.
- **A file goes to the library you added it to.**  A file waiting in the import queue went into whichever library was open when its turn came, so switching libraries while files were waiting moved them.  Each file now remembers its library.
- **An import in the background finishes.**  After your file was searchable, an import kept calling Apple's model for an overview, tags and suggested questions, and saved the document partway through.  In the background iOS could end it during that work: the Lock Screen said "Task failed", and ended early enough, the document wasn't saved.  The document is saved first now, and in the background the extra work waits until you open the app.
- **No "Error Processing Document" without Apple Intelligence.**  On a device where Apple Intelligence isn't available, the Documents screen opened on "Error Processing Document: Apple Intelligence is required but unavailable."  Your documents import and search without it, and the chat already says what still works, so that alert is gone.

### Shortcuts and Siri
- **Asking an empty library from Siri or Shortcuts says it's empty.**  An Ask action pointed at a library with no documents used to get an answer from Apple's model on its own, with nothing from your documents in it, and it came back looking like an answer about that library.  Now it says the library has no documents yet.
- **Actions hand back what they found.** Asking a question from Shortcuts used to show a card and give the shortcut nothing to work with.  Now the ask actions return the answer with its sources, List Documents returns the documents, and List Conversations returns the conversations, so the next step of a shortcut can use them.  When an action can't do its job it stops the shortcut and says why, where it used to report success with an apology inside.  "Ask About an Image" and "Search with a Photo" hand back their text as well.
- **You can pick the mode.** "Ask My Documents" and "Ask a Library" have a Mode menu: Standard, Deep Think or Maximum.  On the free plan, Maximum from Shortcuts counts against the same daily allowance as Maximum in the app.
- **"Ask About a Document" only reads that document.** It used to put the file's name in the question and search the whole library, so the answer could come from a different document.  Now it's searched inside the one you picked and nowhere else, and so are Summarize a Document and Compare Two Documents.  These three answer in Standard.
- **Plainer names.** "Query Documents" is "Ask My Documents", "Search Library" is "Ask a Library", "Ingest Document" is "Add a File" and "Ingest Webpage" is "Save a Web Page".
- **"Save a Web Page" downloads the page.** It used to say it was extracting the page, and nothing was ever downloaded.  Now it fetches the page, saves its text and imports that.  A link straight to a PDF saves the PDF.  A page that only shows its text after running scripts can't be read this way, and the action says so.
- **One action adds a file, a link or text.** "Add to Library" takes any of the three, and you can pick which library it goes into.
- **Find Passages.** A new action that returns the passages matching a search without writing an answer, so the next step of a shortcut can read them.
- **Create a library and switch libraries.** Two new actions, "Create Library" and "Set Active Library".
- **Set the answer mode from a shortcut.** A new action, "Set Answer Mode", switches the chat to Standard, Deep Think or Maximum, so a shortcut or a Focus automation can pick the mode before you ask.  On the free plan, Maximum follows the same daily allowance as in the app.
- **Read the settings from a shortcut.**  A new action, "Get Settings", hands a shortcut the answer mode and the active library, so it can change them for a task and put them back afterwards.
- **Open a library or a document.** Two new actions, "Open Library" and "Open Document".  Open Document takes you to the document's own page.
- **Siri's answer card opens its sources.** When Siri or Shortcuts shows an answer, the card has a button for each document it comes from, up to three, and tapping one opens that document.  An answer from a whole library also has Ask a Follow-up, which opens the app in a new conversation that starts with that question and answer, so your next question picks up from it, and a Standard answer has Think Deeper, which asks the question again in Deep Think.  Both open the library you asked about, and the chat stays in Deep Think until you switch it back.
- **Check a claim.** A new action, "Check a Claim", takes a sentence and tells you whether the words and figures in your documents hold it up, partly hold it up or don't, and which passage it checked against.  It's the same check an answer gets, without writing an answer, and when one of them says no where the other says yes, it tells you to read the passage.
- **Delete documents from a shortcut.** "Delete Documents" asks before it deletes anything, and each document's passages and Spotlight entries go with it.
- **"Add a Document" and "Scan a Document" do what they say.** They used to open the app and stop there.  Now one opens the file picker and the other, on iPhone and iPad, opens Apple's document scanner, the same one Notes uses, and adds what you scan to your library as a PDF.
- **Documents and libraries carry their details.** A shortcut can read a document's name, type, date added, page count and library, and a library's document count and dates.  Before, it got a title and nothing else.
- **A button into Shortcuts.** Settings, under Shortcuts, has a button that opens the Shortcuts app on OpenIntelligence's actions, and the list there names every action as Shortcuts shows it.
- **"Add a File" keeps its file.** It queued the temporary copy that Shortcuts hands over, which the system can remove when the action ends.  Now the file is copied into the app first.
- **Siri phrases are things you'd say.** "Ask OpenIntelligence a question", "Save this page to OpenIntelligence", "Find passages in OpenIntelligence".
- **Long questions from Shortcuts keep going.** On iOS 27 and macOS 27, a question asked from a shortcut or Siri can keep running in the background past the usual 30 seconds, and the system shows its progress while it works.  On iOS 26 and macOS 26 the progress shows in Shortcuts too.  If it's stopped, by the system or by you, it stops writing and says which it was.
- **Siri asks before using Private Cloud Compute.** When a question you ask with Siri or Shortcuts needs Private Cloud Compute and you haven't said yes or no to it yet, the app comes up and shows the same consent screen the chat does.  Before, a question like that stayed on your device, and with the app already open it could wait on a screen that never showed.  If the app can't come up, the question stays on your device.
- **Search from Siri.** On iOS 27 and macOS 27, "Search OpenIntelligence for" and what you're looking for opens the library's search with it and runs it.
- **Visual Intelligence finds your documents.** Point the camera at a device's label or a printed page, or take a screenshot, and Visual Intelligence lists the documents in your libraries that mention what's in it.  Tap one to open it.  The text in the picture is read on your device.
- **Siri knows what's on your screen.** When a document's page, a library or a conversation is open, the app tells Siri and Apple Intelligence which one it is.  Before, nothing on screen was named to them.
- **Siri suggestions.** The app tells your device which library you open and ask in, and when, so Siri and Spotlight can suggest it at that time of day, as "Open" and the library's name.  It takes some days of use before anything shows up.
- **Focus filters.** In Settings, Focus, a Focus can have an OpenIntelligence filter that picks which libraries the app shows while it's on, and the first of them opens.  A Work Focus can keep your work library in front.
- **The Siri phrase shows up where you'd use it.** On iPhone and iPad, the empty Chat screen shows Apple's tip with the phrase for asking a question.  Close it and it stays closed.
- **Add to Library from Shortcuts and Siri uses your plan.**  With the app closed, it used the free plan's limit of five documents, so a Pro or Lifetime library of five or more refused it.  It uses your plan and any document packs now.

### Spotlight
- **A Spotlight result opens what you tapped.** Tapping a document or a library in Spotlight used to open the Documents tab of whatever library was active.  Now a library opens that library and a document opens its own page.
- **Spotlight keeps your documents.** A document's Spotlight entry used to disappear after 30 days.  Now it stays until you delete the document, a passage you find in Spotlight opens its document, and when you delete a document its passages leave Spotlight too.  A document you delete on another device leaves this one's Spotlight the next time the app opens here.  A passage's entry is titled with its document and its page, where it said "Page 3 [Chunk 13]" before, and a text file's passages no longer say "Page 1".
- **Turning Spotlight off clears it.** Turning off Spotlight Indexing in Settings used to only stop new entries, and what the app had already put in Spotlight stayed until it expired.  Now turning it off takes out everything the app put there, along with the libraries it suggested to Siri, and turning it back on lists your libraries and documents again.

### Getting around
- **Handoff.** What you have open in Chat or Documents on one device can be picked up on your other devices.  For a library that syncs through iCloud it opens in that library, and a document's page goes across too.  The app offered Handoff before, but the other device had nothing it could open.
- **Your conversations go with your library.** In a library set to iCloud Drive, conversations were saved in a folder iCloud sync never looked in, so they stayed on the device you had them on.  Now they're saved where sync looks, and the ones you already have move there the first time you open the app.  Deleting one deletes it on your other devices too.
- **iCloud only sends what changed.**  Every sync sent each library's chat history, transcript and memory up to iCloud again whether they'd changed or not, and when two devices did that at the same time, iCloud kept both versions as "name 2".  My iCloud folder had 500 of those.  Now a file goes up only when it changed, and a library's search files go up together.
- **Services on the Mac.** Select text in any app, then choose Ask OpenIntelligence from the Services menu to put it in the chat, ready to send, or Add Text to OpenIntelligence to save it to your library as a note.  Select files in Finder and choose Add to OpenIntelligence to import them.
- **The menu bar on the Mac.** OpenIntelligence has a menu bar icon now.  Click it to ask a question, add documents or search, and the app comes forward with it.  Settings, Appearance turns it off.
- **Long answers on the Lock Screen.** On iPhone and iPad, a question that's still being answered after about ten seconds, like most Deep Think and Maximum questions, shows a Live Activity with the step it's on, and it ends when the answer does.  Its Stop button stops the answer and keeps what's written so far.
- **Put your libraries in your own order.** On iOS 27 and macOS 27, drag a library in the row of libraries on the Documents screen to move it.  The order stays on that device.
- **Touch and hold the app icon.** Ask, Add Document and Scan Document are on the Home Screen, under the icon.
- **A widget.**  Add OpenIntelligence to the Home Screen or the Lock Screen.  The small one asks a question, and the medium one has Ask, Add and Scan.
- **Your Library widget.**  It shows the library you have open and how many documents are in it, and the medium size also shows the last question you asked there with the start of its answer.  If you've chosen to hide private widget data, the answer stays hidden while the phone is locked.
- **Scan into Library from the Lock Screen.**  Add the Scan into Library control to the Lock Screen, Control Center or the Action button, and it opens OpenIntelligence's camera without unlocking.  Take the page, tap Use Photo and unlock, and it's added to the library you have open.
- **Copy Link.**  Touch and hold a document or a library and tap Copy Link.  The link opens it in OpenIntelligence on your iPhone, iPad or Mac, and the App Store page anywhere the app isn't installed.
- **Keyboard shortcuts.** On the Mac, and on an iPad with a keyboard: Shift-Command-N starts a new conversation, Command-O adds documents, Command-1 and Command-2 switch between Chat and Documents, Command-3 opens the Import Queue, Command-F opens the library's search, Command-] and Command-[ go to the next and previous library, and Command-comma opens Settings.
- **Sheets on the Mac open as one page.**  Seven screens, the citation sheet among them, opened on the Mac as a two-column split with an empty side.  They open as one page now.
- **The hardware X-Ray steps aside for sheets.**  It floated above everything, a sheet's buttons included, and a tap there went to it.  It hides while a sheet or an alert is up.
- **The tab bar gets out of the way on iPhone.**  It shrinks while you scroll a conversation or a library, the way it does in Apple's own apps on iOS 26, and comes back when you scroll up.
- **The sample guides' questions.**  A library of the sample guides is meant to show a set of questions written to walk you through the app, and an older list usually showed in its place, which the refresh button didn't change.  If you'd deleted one of the guides, the library could lose the written questions altogether, and if you'd added your own documents to it, it kept asking about the guides.  Now a library with any of the guides gets the questions written for the ones it has, each with the guide and section it comes from, and refresh shuffles them.  Once you add a document of your own, the questions come from what's in the library.
- **A Siri tip on the Documents screen.**  On iPhone and iPad, under your list of documents there's a tip with the phrase for Find Passages, which finds the passages in the open library that match what you say.  Close it and it stays closed.

### Accessibility
- **VoiceOver reads a library as a button.**  Each library in the row of libraries is one button now, read with its name, how many documents it holds and whether it's the one you're in.  Before, VoiceOver read its icon as "Move" and its name as plain text, and never said it could be tapped.  The Document Quota reads as one line too, like "Document Quota, 2 of 5 documents".
- **VoiceOver names every switch and slider.**  Several switches in Settings, the hardware X-Ray's among them, and the sliders for a library's passage size and overlap and for the clusters in Visualizations had no name, so VoiceOver read each one as a switch or a slider with nothing to say which.  Each one is read with the name shown beside it now, and a slider says the number shown next to it.
- **Easier to tap.**  The microphone and the paperclip in the chat field are 44 points square, Apple's default size for a control on iPhone and iPad and the size of the send button beside them, and "I'll add my own documents" on the first screen is 44 points tall.
- **The hardware X-Ray reads clearly.**  Its numbers were faint text on a see-through box.  Now they're white and in color on a solid dark backing, they grow with your text size, and the "Drag me" hint wraps instead of running off the screen.  On a new install it starts off, so it doesn't cover the chat the first time you open it.  Turn it on in Settings, Appearance, with the Telemetry HUD switch.
- **Gray text is easier to read.**  The small gray text on Chat, Documents and Settings was lighter than Apple's accessibility guidelines ask for.  It now uses the darker gray iOS itself switches to when Increase Contrast is on, and the text on the Documents screen grows with your text size.  VoiceOver also stops finding a hidden "Upload complete" panel when nothing is uploading.
- **Colored labels are easier to read.**  The mode, model and count pills at the top of Chat keep their color in the icon and the background, and their words are in black or white now, because colored words on a tinted pill were hard to read.  In light mode the app's blue is a little deeper too, so white text on blue buttons reads more clearly.  When they don't fit side by side, the pills at the top of Chat and in Settings stack instead of getting cut off, and at the largest text sizes the top of the Documents screen scrolls with your documents instead of running up under the title bar.  The question box's text grows with your text size now too.
- **Answers and imports work at the largest text sizes.**  On iPhone and iPad at the biggest text sizes, the import panel broke words in half, cut its Continue and Discard buttons short, and left files you couldn't scroll to, and the Fact Check line under an answer split "SUPPORTED" into pieces.  Now they wrap or stack instead, and everything in the import panel scrolls.  Its buttons are bigger to tap there, the names and details in your document list grow with your text size and read more clearly, and the first screen's "See It in Action" button wraps instead of getting cut off.  The colored scores in an answer's sources, the badges on a document's page and the privacy line on the plans screen use black or white words now, like the pills at the top of Chat, and VoiceOver reads the import totals as what they count instead of the names of their symbols.

### Sharing
- **A shared answer takes its sources with it.** Share used to send the answer's text and nothing else, so the [S1] and [S2] in it pointed at nothing.  Now the documents and pages it cites are listed under it, with the app's name and its App Store link at the end.
- **Share an answer as a picture.** Under an answer, Image makes a card with the answer, its sources and a QR code for the app's App Store page, ready to post or send.
- **The share sheet shows what you're sharing.** It used to show the first line of an answer, or a bare link when you shared the app.  Now it shows the app's name and icon.
- **Export a conversation.** The chat menu has Export Conversation, as Markdown to read, as JSON Lines for other tools, or as a PDF to print or send.  Each answer keeps its source list.  A new Export Conversation action hands a saved conversation to a shortcut as a file, in any of the three.
- **Copy works on the Mac.** The Copy button under an answer showed "Copied" on the Mac and copied nothing.  It copies now, and so do the three other copy buttons that had the same problem.

### Answers
- **A lookup answer keeps its own words when they match the page.**  For a question about one value, like a code or a capacity, the app could swap a finished answer for a piece of the page around that value, and the piece could start in the middle of a word and leave out half of what you asked.  Now an answer that already gives the value from your document stays as it was written, and when a piece of the page does stand in, it's the whole sentence.
- **Answers read the rows of a table.**  When the passage that answers a question was part of a table, a list or a page of labelled values, the model was given only the heading above it, so it could tell you your document didn't mention something that was right there.  Now it gets the rows themselves, and so do the checks under the answer.  Your libraries don't need to be imported again.
- **Deep Think and Maximum answers are checked.**  Settings said every mode checks its answer against your documents, and Deep Think and Maximum skipped the checks, so their answers said Not Checked.  Now they run the same checks a Standard answer does, and the badge says Verified or Unverified.  The answer stays as it was written either way.
- **Deep Think keeps its full answer.**  When Deep Think's answer hedged on one point, a second search could swap the whole answer for one short line, and that line could be wrong.  On a question about file types, a full answer was swapped for a line about "notes, warnings and exceptions".  Now a short line takes the answer's place only when it agrees with what the full answer said.
- **A number pulled straight from your document has to be about your question.**  For a question about a single value, the app can take the value straight from a passage instead of writing an answer.  It could take the wrong line's value, like the engine oil's 4.5 L for a question about the fuel tank.  Now the line the value is on has to name what you asked about, or the model answers instead.
- **Ask out loud.** On iPhone, iPad and Mac, the chat field has a microphone button.  Tap it and talk, and your words show up in the field as you speak.  Tap it again to stop, then send when it looks right.  Dictation runs on your device.
- **A simpler chat.**  New installs start with a plainer chat: while an answer is on its way it says what it's doing in words ("Searching your documents…", "Writing the answer…"), and the stats bar, the step-by-step console, the technical badges and the token count when an answer finishes stay out of the way.  Fact Check says where each point was found instead of a confidence score.  Turn the technical view on with Technical Details in the chat's ⋯ menu or in Settings, Appearance.  If you've used the app before, your chat stays as it was until you switch.
- **See the page a source came from.**  Tap a citation in an answer, or the page under a Fact Check claim, and a PDF opens at that page with the passage highlighted, so you can check the answer against the page itself.  In an answer's details, a source from a PDF on this device has a Page button that does the same.  Other kinds of documents open their details page, where a Preview button shows the whole file in Quick Look.
- **Finished imports and answers tidy up after themselves.**  The notification that an import or an answer had finished, and its card on the Lock Screen, stayed for up to ten minutes or until you swiped them away, even after you'd opened the app.  Now they go as soon as you're back in the app.
- **Fact Check quotes the right sentence.** The quote under a claim in Fact Check was the first few lines of the passage, wherever the claim came from.  Now it's the sentence in that passage that matches the claim best.
- **Without Apple Intelligence, an answer says why it's excerpts.** An answer made of excerpts used to end by saying the model might be rate-limited.  On a device that can't run Apple Intelligence, or with it turned off, that isn't the reason, and now it says the real one.
- **Settings describes Deep Think as it is.** The list of what Deep Think and Maximum do named four tool functions for the model.  Neither mode hands the model a tool, so the line is gone.
- **Page numbers after a blank page are right.** When a PDF had a blank page, every page after it was filed under the number of the page before it, so an answer that quoted one of those pages could name the wrong page.  Each page keeps its own number now.  A PDF you imported before this keeps the old numbers until you import it again.
- **Sentences from your documents aren't cut in half.** Before the model writes, the app picks the sentences that match your question, and it was cutting them at every line break and after things like "p.m."  So an answer could be built from "on the 5th" without the first half of the sentence.  They stay whole now.
- **Numbers are checked as numbers.** The check that compares the numbers in an answer with your documents used to pass a number if its digits showed up anywhere on the page.  An answer said a model had "2.5 billion" parameters, and it passed because another model in a table was named "Qwen-2.5-3B".  Now a number is compared as a number: "2.5 billion" isn't backed up by a "2.5" that's part of a name, and "2.5" doesn't pass because the page says "12.5".  A sentence with a figure your documents don't state shows as Partial in Fact Check, and the answer isn't marked Verified.
- **Amounts, dates and units are checked too.**  The check now reads amounts of money, dates and measurements with Apple's own detector, the one that already finds them in your documents when you import.  An answer that gives an amount in another currency than your documents do, another day of the same month, or a number with other units, like 35 kPa where the manual says 35 psi, isn't marked Verified.
- **Right answers aren't marked Unverified by a lab check anymore.**  One of the checks behind the Verified badge is meant for questions about lab research, to keep results from cell, animal and human studies apart.  It was reading pieces of everyday words as lab terms, like the "um" in "number", the "ip" in "trip" and the "cell" in "cancellation", so right answers about travel and hotel documents were marked Unverified, and a question about travel insurance was refused.  Now it reads whole words, and it only steps in when your question is about lab research.  When a check does fail, the answer's details now say which one.
- **An answer's title isn't checked as a claim.**  Fact Check scored an answer's own heading, like "Hotel Address in Lisbon", as if it were something the answer claimed, so a right answer could read "1 of 2 Verified".  An answer's title is left out of Fact Check and its count now.  A point also no longer shows a gap where its citation was taken out.
- **Fact Check reads the way the answer does.**  When a claim was cut out of the middle of bold text, Fact Check showed the bold's asterisks with it, a time in bold read "9:00 a.m..", and a claim that pointed at a range of sources read "are present in through."  Now those read the way the answer has them, and a long claim quoted under Information Gaps stops at a whole word.
- **The Verified badge agrees with Fact Check.**  An answer could show a green Verified badge while its own Fact Check said "0 of 2 Verified", because the badge only looked at the checks on the whole answer.  Now when Fact Check can't back any of an answer's claims, the badge says Partially Verified or Unverified instead.
- **A blank response gets one more try.** Sometimes Apple's model returns nothing the app can read.  When that happens while an answer is being written, Standard now waits two seconds and asks once more before it gives up.  Deep Think and Maximum already retried one of the ways that failure shows up, and now they retry all of them.
- **A question asked again looks at your library as it is now.** The app kept the search behind every question you asked, and asking the same thing again reused it, even after you'd added or deleted documents.  So a new document was left out, and a deleted one could still end up in the answer.  Now any change to your libraries, or an update to the app, means a fresh search.
- **Old searches are deleted.**  The app keeps the search behind each question you ask, with the passages it found, and it never deleted them, so a library you'd deleted still had its text in there.  Now they're deleted whenever you add or delete a document, and after an update.
- **Answers draw on more of your documents.**  Before the model writes, the app is supposed to pass over passages that say the same thing as one it already picked, so the model sees more than one part of your documents.  That step never did anything, because the passages reached it without the data it compares, so near-copies got through.  It works now.
- **Error codes count.**  When the app picks the sentences that match your question, it skipped every two-letter word, so in "What does E1 mean?" the E1 never counted.  A short code with a letter and a number in it counts now.
- **Fact Check catches a passage that says the opposite.**  A claim that shared enough words with a passage saying the opposite, like "Pets are allowed" against a lease that says they aren't, read as supported.  Now it reads partly supported.  And a passage that says "without" something only says the opposite when the claim names that thing: a right claim about keeping a sick child home was marked as contradicted because the school's handbook says "without fever-reducing medicine".
- **The best passage the search finds always reaches the answer.**  "What happened on September 30" found the September 30 section of a monthly log and then answered from September 24 and 25, because the step that fits passages into Apple's model kept only sentences repeating the question's words, and that day's lines didn't repeat them.  The passage the search ranks first now goes in whole, and the rest of the room is filled as before.
- **A date written "30th" finds its day.**  Asking "What happened on September 30th" still missed that day in my notes, which call it "September 30", because "30th" isn't a word anywhere in them and the search ranked a different day first.  A day next to a month is now searched as its number, so "September 30th", "Sept. 30th" and "the 30th of September" all look for September 30.
- **Asking for a summary gets one.**  "Summarize" and "summary" were read as a request to add numbers up.
- **Excerpts say they weren't checked.**  When the app couldn't write an answer and showed excerpts instead, the badge read Partially Verified, though nothing had checked them.  It reads Not Checked now.
- **An answer no longer cites a document that isn't there.**  Passages left behind by a deleted document, or by an import that didn't finish, could turn up in an answer credited to "Unknown".  Searches leave them out now, and in a library kept on this device they're removed when the app opens.
- **An answer's details show Apple's token count.**  On iOS and macOS 27, the details under an answer list what Apple's model spent on the whole answer: tokens in, how many of those it had cached, tokens out, and reasoning tokens when Private Cloud Compute reasoned.
- **Fact Check catches three more slips.**  A sentence of an answer now reads Partly Supported when it leaves out a "not" your document has ("Pets are allowed without written permission" against a lease that says they aren't), when its day doesn't match ("the 16th day" where the lease says the 6th), or when its words are all in your documents but no one sentence of them says it.  Each one says why under the sentence.

### Settings
- **A setting you change stays changed.** The app saved the setting you'd just changed with the value it had before, so the last change you made could come undone the next time the app opened.  It saves the new value now.
- **Send me a crash report.** On iOS 27 and macOS 27, if the app closes unexpectedly, it offers afterwards to email me a report of where it stopped.  It has the app and system versions, your device model and the part of the app's code that was running, and none of your documents, questions or answers.  It only goes anywhere if you send it, and Settings, About can email or share the last one later.
- **On iOS 26, Settings says what Private Cloud Compute needs.**  On a device that isn't on iOS 27 or macOS 27 yet, Settings said this copy of the app was built without Private Cloud Compute.  It says Private Cloud Compute needs 27 now.
- **The privacy policy is in the app.**  Settings, About has a Privacy Policy row.  It opens the same policy as the website, and it reads without a connection.
- **Settings says when an answer goes to Private Cloud Compute.**  It said only an answer too large for your device went there.  With Hybrid, a Deep Think or Maximum answer drawn from more than one document does too, with your permission, and Settings, How It Works and the privacy policy say so now.  The choice that allows it without asking is called Allow without asking.  It was called Allow for Deep Think and Maximum, though it never stopped at those modes.
- **Settings shows the model's real window.**  It said 4K everywhere.  Settings and an answer's details show the number your device's model reports now, and the Context Window card no longer says Standard switches to three sessions on a hard question, which it doesn't.  The Glossary, the sample documents and the suggested questions said 4,096 too, and now use what your device reports, 8,192 on a Mac with macOS 27.
- **Intelligence Mode in plain words.**  Each mode says what it does in plain words: Maximum, for one, can make up to 50 passes over your documents and stops when its findings stop changing.  The techniques behind each mode are listed with Technical Details on, in Appearance, and that list no longer shows two that Standard doesn't use.  Siri & Shortcuts shows how many shortcuts the app offers instead of "10 of 10 Registered".
- **The GPU setting says what each choice does.**  Each choice in Settings, Device & Performance lists what it changes, taken from what the app runs: which chips searching and importing can use, where scanned pages are cleaned up, and where large searches run.  A line under it says, for your device, whether an import that keeps going in the background can still use the GPU.  It used to say things the app didn't do, like answers staying on the Neural Engine, and it made Maximum sound like more than Performance, when the two work the same way while the app is open.  Its entry in Plain English said a higher setting imports faster and uses more battery, which nothing had measured, and on my Mac a higher setting made large searches slower.  It says what the setting decides now.
- **The GPU button on the import panel works.**  It changed its own label and nothing else.  It switches the same setting as Settings now, through all four choices.
- **Deep Think's numbers are the real ones.**  Settings showed 5 sessions on an iPhone 15 Pro and 13 on some Macs.  Its reasoning chain stops at 8 sessions on every device, and Settings and its badge now show how sure it aims to be on yours, from 85% to 95%.
- **Your library's model is named right on a Mac.**  Library Settings called a library built on a Mac with macOS 27 "Apple Natural Language", and other screens said every library was 512-dimensional and ran on the Neural Engine.  Each one now shows your library's own model, its size and where it runs.

### Notifications
- **A notification when it's done.** Settings has a new Notifications page with one switch.  With it on, you get a notification when an import finishes, or when an answer that took more than 20 seconds is ready, if OpenIntelligence isn't in front.  It's off until you turn it on, and it never shows your question or a file name.

### Plans
- **Redeem a code.** The plans screen has a Redeem a Code button.  It opens Apple's sheet for offer codes.
- **New Chat at your conversation limit keeps the conversation you had.** When a plan's limit on saved conversations was reached, New Chat emptied the screen but kept saving to the old conversation, so your next question replaced everything in it.  Now the conversation stays on screen with a note about the limit, and your next question is added to it.

### When your device is busy
- **The app eases off when iOS asks.** iOS 27 can tell apps to use less when the device is under pressure.  When it does, an import leaves a short gap between batches and Deep Think and Maximum leave a second between steps.  The answer isn't cut short.  It takes a little longer.

## 5.6
This one's about your first few answers.  The citations in an answer open now, numbers and times come through the way your document wrote them, and the Verified badge only shows when a check actually ran and passed.

### Answers
- **Citations open.** An answer cites its sources as [S1], [S2] and so on, and tapping one did nothing, because the app only made a link out of a bare [3].  Now each one opens the passage it came from.
- **Numbers and times stay the way your document wrote them.** After the model wrote an answer, a cleanup step that's there to remove repeated sentences rebuilt every answer, repeats or not, and it split the text at every period, so "$300.00" came out with a space in the middle and "10:00 p.m." lost its "m."  Now it leaves an answer alone unless it finds a real repeat.
- **Two facts don't get merged into one.** That same cleanup could treat "E1 is an open circuit" and "E2 is a short circuit" as one sentence said twice and drop one of them.  Sentences with different numbers or codes are never treated as repeats now.
- **Answers stop ending with my own prompt.** When the app wasn't confident in what it found, some answers ended with a line like "What sources show, What's missing, Confidence note", which was part of my own prompt.  That line's gone, and the app asks for one plain sentence about what your documents don't cover instead.
- **No more asterisks.** The Fact Check rows showed bold text with its asterisks, and an answer showed "###" and "**" while it was being written.  Both are cleaned up.

### The Verified badge
- **Verified means a check ran and passed.** The badge showed Verified for any answer that wasn't on a short list of failures, so an answer whose checks failed, or never ran, still said Verified.  Now it says Verified, Unverified or Not Checked, and Fact Check counts the claims it actually supported.
- **A right answer doesn't get "Verification failed" under it.** One check compares the whole answer against a single passage, and it was failing answers whose every sentence the claim check had already supported.  When that's the only check that fails, the claim check decides.

### Private Cloud Compute
- **"Just Once" means once.** In Deep Think and Maximum, choosing Just Once on the consent sheet carried over, so the next Deep Think or Maximum question could go to Private Cloud Compute without asking.  Now Just Once covers one question.

### Getting started
- **It tells you when your device can't run Apple Intelligence.** Chat used to say "Enable it in Settings" even on a device that can't turn Apple Intelligence on, and Settings said "Preparing AI Models..." forever.  Now the app tells you which (not supported on this device, turned off, or still downloading) and what still works without it.
- **An empty library doesn't suggest questions it can't answer.** With no documents in a library, the chat suggested four prompts and every one of them came back "No documents yet."  An empty library doesn't suggest anything now.
- **The hardware readout waits for the welcome screen.** On a first launch it sat on top of the welcome screen.  Now it shows up once you're in the app.

## 5.5
One fix and lower prices this time.  A "how much" question could get answered with a number from a totally different
document, with a Verified badge on it.

### Answers
- **"How much" questions stop grabbing numbers from the wrong document.** Any "how much" made the app treat every measurement it found as a possible answer, so on my Mac "How much notice do I have to give before I move out?" came back "1 lb." from an air fryer manual.  Now it only looks for a volume when you ask about fuel, gas, oil, coolant or a tank, or what something holds.  The model still got that question wrong afterward (it said at least 30 days, the lease says 60), so I'm not done with it.
- **"4.5L" counts as liters** when you ask how much something holds, same as "4.5 L".

### Plans
- **Pro costs less from October 1.** $4.99 a month or $24.99 a year in the US, down from $5.99 and $29.99, and lower in most other countries too.  Subscribers renew at the lower price automatically.  Lifetime is $49.99, down from its $59.99 regular price, and it's just called Lifetime.
- **Each plan does the math.** The plans screen shows what Annual saves over twelve months of Monthly, what it works out to per month, and when Lifetime costs less than a year of Monthly, all from your own App Store's prices.

## 5.4
This one's all about answers.  They're done when the last word shows up, most Deep Think and Maximum
answers write out in front of you now, and on iPhone the app tells you when one finishes while
you're off doing something else.

### Answers
- **Finished answers don't sit there anymore.** If you asked Standard for one specific fact, it ran a second check after the answer was written, with the text box locked for 19 seconds to almost three minutes on my Mac.  Now it only runs when the app's own verification flags something.
- **You can type while an answer gets checked.** Send your next question or hit Stop and the answer stays, sources and all.
- **Deep Think and Maximum write in front of you** for most questions, with "Refining…" while a later step might still improve it.  Short Standard answers stream too.

### Background
- **You'll know when an answer's done.** On iPhone, a light tap, plus a badge on the Chat tab if you were somewhere else.  An answer iOS cuts off in the background keeps what it wrote, with a note saying why.

## 5.3
The app reads documents with Apple's own detector, the welcome screens follow your light or dark
setting, and there is a new setting for how answers are written that you turn on yourself if you
want it.

### Plans
- **The upgrade screen says what you get, in the order that matters.** Every plan runs the same model: Apple Intelligence on your device, Deep Think, and Private Cloud Compute after you approve what is sent. Pro and Lifetime lift the daily cap on Maximum mode and raise the limits on documents and libraries, and now the screen leads with that instead of storage numbers.
- **When Lifetime is on sale, the app says so.** One line at the top of Chat and Documents, with the real discount and the last day, computed from the store's own price. Dismiss it and it stays away until the next sale.
- **A thumbs-up now offers to write a review.** Apple's rating sheet gives stars and never a written review, and a written review is what someone reads on the store page. So when you thumb-up an answer, the app asks once per version whether you'd rate it, write a review, or send feedback. And the Lifetime card now says how many months of Pro Annual its price buys, from the store's own prices.
- **One look at the plans, once.** After the fourth answer the app has verified against your files, it shows you the plans screen. It will not ask again.
- **Pro Annual no longer has a free trial.** It is one payment a year, and the screen says so.

### Getting Started
- **The sample library's suggested questions are back.** They are hand-written, and a leftover duplicate of one sample document ("RAG Technical Architecture 2") was enough to switch them off and replace them with questions built from templates, which is where "What is nothing?" came from. Duplicates are cleaned up on the next visit to Documents, the hand-written set shows even when a duplicate is present, and a library whose questions were built before Apple Intelligence was ready gets them rebuilt by the model the next time it can. When the model has nothing good to say about a document, the app now shows no suggestion rather than a bad one.
- **The welcome screens follow your light or dark setting.** They were always dark whatever the rest of the app did, so in light mode you got a white app with one navy screen in front of it — and the clock and battery vanished, because iOS draws them in dark ink on a light screen and that screen was nearly black. Light is its own design rather than the dark one flipped: warm off-white settling into a faint blue-grey, with the glow behind it eased back.

### Reading your documents
- **Apple's own detector now finds the real things inside a page**, instead of the app's own pattern matching. Addresses, phone numbers, dates, amounts, measurements, flight numbers and tracking numbers are recognised as what they are. The old patterns understood US phone numbers and three currencies only, so a European invoice produced no amounts and a postal address was never found. An amount is recorded with the currency it is in, and a date in a standard form, rather than as whatever characters sat on the page, which is what makes them findable later. This applies to text inside tables today; prose on the same page does not yet contribute.

### Answering
- **Three sliders in Model Parameters were claiming to do something Apple's API cannot do.** Frequency, Presence and Repetition Penalty sat under a line saying they affect how the model picks words. Apple's generation API has no penalty setting at all, so Apple Intelligence ignores all three. They now say so, and they stay put because they belong to a local model host on Mac that is not built yet.
- **Adapt to the question, in Model Parameters. Off unless you turn it on.** The app picks how careful or how expansive to be from what you asked: looking up a value becomes near-repeatable, so the same question gives the same number twice, while comparing or investigating gets more room. It works in Standard, Deep Think and Maximum; the agentic modes use the temperature and keep their own per-step lengths. You can also write your own reasoning profile in plain words, replacing Apple's three fixed settings. That controls how hard Apple's model works inside a single answer, which Apple only allows on Private Cloud Compute; the app's own step-by-step reasoning in Deep Think and Maximum runs on your device and is separate from it. Your saved settings are untouched and turning it off restores them at once. It is off by default because nobody has shown it gives better answers yet; it is yours to judge.

## 5.2
The release that turns on Private Cloud Compute. Nothing about how the app reads, searches or checks
your files changes; what changes is that one step, the writing of the answer, can now leave the
device when it needs to, and only after you say so. Requires iOS, iPadOS or macOS 27.

### Plans
- **When a launch discount is running, the plans screen now shows what the price normally is, how much is off, and the day it ends.** The App Store does not mark a reduced in-app purchase as reduced, so without this the price simply looks lower and there is no way to tell it is temporary. The app only says a discount is on when the price it is being charged is genuinely below the normal one, so it cannot advertise a sale that is not running.

### Private Cloud Compute
- **When a question needs more room than the model on your device can hold, the writing step can now go to Apple's Private Cloud Compute.** Reading your files, searching them, choosing what to cite and checking the finished answer against the passages still happen on your device, exactly as before. Every release since 4.6 has carried this support compiled out, waiting on iOS and macOS 27. This is the first build made with the toolchain that compiles it in.
- **Nothing leaves without asking.** Before anything is sent, a sheet shows what would go: how many passages, how large, and why. Allow it once, allow it always, or keep everything on the device. You can also pin routing to On-Device in Settings and the question never comes up.
- **Every answer says where it was written.** Expand the metrics bar under an answer to see On-Device or Private Cloud Compute.
- **Apple's servers keep nothing after the answer.** The connection is end-to-end encrypted and the request is not accessible to Apple or to the developer; these are Apple's stated properties of Private Cloud Compute, and the app adds nothing to the request beyond the passages you approved.
- **Measured on an iPhone with the A18 Pro:** roughly 86 tokens per second from Private Cloud Compute, against 27 on the device. Those figures were taken on a local build with the iOS 27 toolchain and are the same figures the earlier release notes cited.

### Honesty
- **How It Works and the About screen said the app asks before sending to Private Cloud Compute, on builds that could not send anything.** The check they read answered a different question, whether the operating system has Apple Intelligence, which is true of every iPhone that can run the app. It now answers the real one: whether this build can route to Private Cloud Compute. On a system older than 27 those screens say so plainly.
- **The built-in guides, the Glossary and the Settings capability list now describe the build you are running.** Each of them picks its wording on the same condition the code uses, so a build with Private Cloud Compute says it is on and a build without it says it is not.

### Ratings
- **The app now asks for an App Store rating, once, after your third verified answer.** It never asks on launch, never after an answer it could not verify or declined to give, and never twice within four months; Apple's own sheet decides whether to show at all and caps it at three times a year. If you would rather not be asked, dismiss it once and it stays away.

## 5.1
Most of this release is about the Mac, where importing a large document had become slow enough to be
unusable. The text recognition changes apply to iPhone and iPad as well.

### Built-in Guides
- **The three sample documents now describe the app you are running.** They said complex questions were sent to Private Cloud Compute, which nothing in this build does; they listed fewer formats than the app reads; they described the quality modes by where they run rather than by what they change; and they said nothing about importing, which is where most of the recent work went. All three are rewritten from the code: every format, what happens during an import and after a quit, what each quality mode actually changes, the plan limits, the measured speeds, and what Private Cloud Compute will add when it arrives with iOS and macOS 27. If you already imported them, they update in place.
- **The What's New screen has entries for 5.0.2 and 5.1.** Updating to either used to show nothing, because neither release had been written for it.

### Appearance
- **The Mac app icon was a square, and its dark version had a blue rim.** Every Mac icon slot was a solid square filling the whole tile, with no transparency at the corners. Mac icons are supposed to sit inside a rounded shape with a margin around it, which is why yours looked like a hard tile in the Dock next to everything else. The dark version had a second problem: it had been made by repainting the background behind the bulb without redrawing the edges, so a thin line of the original blue was still there along every outline. Both are redrawn. The iPhone and iPad icons were already correct and are unchanged.

### Speed
- **Every PDF page was drawn at four times the resolution it asked for, then copied through an uncompressed image format and back.** The Mac used a drawing method Apple deprecated for exactly this reason: it sizes its canvas from the display rather than from the request, so on a Retina screen a page asked for at 3060x3960 was actually drawn at 6120x7920. That result was then encoded to an uncompressed image in memory and decoded straight back, once per page. Measured on this hardware, roughly 370 MB written and read per page, for nothing. The iPhone never did this; its half of the code was already correct. Each page is now drawn once, at the size requested. The wall-clock effect on a full document has not been measured and no speed multiple is claimed here.
- **With the app open and doing nothing, it was re-reading every library's search index about seventeen times a second.** A background timer kept finding one library in a state it could not resolve, and each pass reloaded every index whether or not anything had changed. Over a measured 164 idle seconds that was 2,848 index reads, the same index re-read 288 times. Left running for about three hours it accumulated a backlog of queued work it could never finish and the app stopped responding. Indexes are now re-read only when they have actually changed on disk.

### Reliability
- **A large import paused by quitting the app looked like it had lost everything.** Reopening showed the document sitting at zero. The work was never lost: the app has always resumed from the last page it committed. But the screen said otherwise, and removing the item *is* the one action that discards that progress, so the display was steering people toward the only destructive choice available. A resumed import now reports how many pages it already finished.

### Text Recognition
- **The app asked the system to guess each page's language while also handing it a list of thirteen to choose from.** Those two instructions contradict each other. Apple's own guidance is to state the languages when you know them, because the automatic guess is not guaranteed correct, and a wrong guess means text is corrected against the wrong dictionary, which damages it rather than merely slowing it down. The language is now determined once per document from the text the file already contains, and only that language is used.
- **Page images went to text recognition at the highest possible resolution with no downscaling.** That is the slowest and most memory-hungry setting the system offers, and it was set deliberately with a comment saying it caught all text sizes. Recognition now scales down to what is needed to read roughly three-point type, which is smaller than the fine print in any real document.

---

## 5.0.1

macOS 5.0 reached the App Store as an earlier build and is missing everything below; this brings it level.
On iPhone and iPad this is the first 5.x release, so the 5.0 notes below are part of it too.

### Speed
- **The Documents tab stopped waiting on a number it never showed you.** Opening the tab counted your cached documents before it would appear. That count feeds one row that stays hidden unless the count is above zero, and on the device this was traced on it was zero, so the row was never drawn. The count now loads quietly in the background and the tab opens straight away. It was costing between 29 and 393 milliseconds on every open, and it was the slowest single thing in a log of nearly six thousand lines.

### Your Hardware
- **Rotating the device left black rectangles around the floating hardware readout.** The readout lives in its own small window that positions itself, and nothing was repositioning it after a rotation. It was also being held inside a portrait-shaped area even in landscape. Both fixed. Dragging it is unchanged, and the chip outlines still stay pinned to where the hardware physically is, because the hardware does not move when you turn the device.
- **The Temperature slider did nothing on one of the three sampling settings, and did not say so.** Predictable always takes the most likely next word, so temperature cannot change its output. The slider stayed adjustable anyway. It is now dimmed on that setting, with a note about where it does apply.
- **The Atlas was labelling a medical paper "API Reference".** Cluster names were matched on fragments rather than whole words, so "api" was found inside "therapies" and "term" inside "determined". A paper about dopamine and serotonin was filed under categories written for software documentation. The same list existed in three places and all three were wrong.
- **"Analyzing corpus…" was never analyzing anything.** Every library that was not the one you had open showed a spinner that could not finish, because nothing had been asked to run. Reading a library's settings means opening it and loading every passage, so doing it for all of them at once would make that screen slow instead. It now tells you it has not run yet, and gives you a button.
- **The library selector on the Database screen is a row, not a menu.** With eight libraries, a menu meant a tap to see the options and a second tap to choose one.
- **A tag that appears once in a document no longer describes it.** Running headers and page furniture were being turned into tags, which is where "pychatry" came from — a mangled journal masthead read off the top of a page. A word that genuinely describes a document appears in it more than once.
- **Turning performance up was making the app slower at the thing it does most.** The four execution profiles set which parts of the chip do the work. Choosing Maximum switched the Neural Engine **off** and left it doing less than Performance, and when building your search index both Performance and Maximum switched it off, so the middle setting was the only one using the whole chip. Every setting now uses everything the one below it used, and more.
- **The performance selector shows you what it is doing.** It was a dropdown that displayed one option and hid the other three. It is now four cards side by side, each showing which parts of the chip it uses, with a plain description of exactly what changes when you pick one.
- **Deep Think never ran a minimum number of passes, and the screen said it did.** It said "6 to 8 reasoning sessions". There is no minimum; it stops as soon as your documents have nothing new to add, or once it is confident enough. One recorded run stopped at five. It now says "up to 8" and explains both reasons it stops early.
- **Macs were being given iPhone-sized limits.** The app sorts devices into performance tiers, and the tier below the top one is tuned for phones. Every Mac except the Pro, Max and Ultra models had been placed in it, so a MacBook with 32 GB of memory was processing 1,024 items at a time when it can handle 6,144, and was not scaling with its memory at all. Every Apple chip now sits in the tier its actual capability warrants. Heat is still managed by measuring the machine's real temperature while it works, which is what was protecting it all along.
- **The hardware panel now shows free memory, and one of its numbers was nonsense.** The small floating readout in the corner listed processor, Neural Engine and graphics activity but never how much memory was left, which is the number that decides whether a large import will finish. It does now. Separately, the Hardware Envelope card claimed a limit of 1,073,741,824 simultaneous threads; the real figure is 1,024, and the wrong one came from multiplying three separate limits together instead of reading one.
- **The app understands Apple chips that do not exist yet.** Chip support was written out by hand and stopped at the M5, so a Mac newer than that was labelled generically and given settings tuned for an M3. It now works out the generation from the chip itself and scales to match. Four other cases where an unrecognised device quietly switched off four parts of search have been closed as well; the only devices still treated as unsupported are ones that genuinely cannot run Apple Intelligence.

## 5.0

Documents were quietly losing parts of themselves, answers were built from a fraction of what was found, and the app was rewriting your library on every launch. This release is the search for all three.

### Speed
- **Deep Think answers roughly three times faster:** the same question went from four and a half minutes to eighty seconds, with a slightly longer answer. It was re-reading the same passages.
- **The app starts faster:** a 43 MB model loaded on every launch before anything appeared, even if you never asked a question. It now loads when it is first needed.
- **Deep Think stops when it runs out of new material:** on smaller libraries it repeated its first three reasoning passes word for word, about a third of the total time, learning nothing. It still reads everything it retrieved.
- **A document you import no longer loses its searchability to the app's own housekeeping:** the searchable index is written as soon as processing finishes and the record saying the document belongs to the library a little later. In between, the background sync saw a library that appeared empty, concluded its index was junk, and deleted it. It now refuses to delete an index that still holds content, and says why whenever it does delete one.
- **Switching libraries during an import no longer splits the document from its index:** the file was filed in one library and the part that makes it searchable in another, so it appeared in the list and answered nothing.
- **A library that has lost its ability to answer now tells you, and can repair itself:** detection now runs the moment a question comes back with nothing, not only when you switch libraries, and the repair is confirmed working on a real device, rebuilding and answering again in about four seconds. Two related cases, where the repair is blocked because files are still importing, are fixed in code but not yet reproduced on a device.
- **The app stopped re-reading your entire library to decide it had nothing to do:** the check that keeps devices in sync read every passage out of both this device and iCloud before deciding — 43,000 records in one session, half before the app drew a screen, for zero writes. It now checks whether anything changed first.
- **iCloud sync stopped re-uploading libraries that had not changed:** it rewrote every index on every pass, and each rewrite looked like a change and started another pass. It now compares before writing. Less battery, less data, same sync.
- **The source chips under an answer scroll properly:** swiping across them sometimes registered as a tap. Same look, no longer fights the scroll.
- **Leaving the chat tab no longer kills the answer you were waiting for:** it used to cancel and discard the partial answer with no explanation.
- **The chat no longer loses your place:** switching tabs used to slam you back to the newest message.
- **Atlas keeps showing what it already worked out** instead of replacing the page with a spinner while it recalculates.
- **Answers stream more smoothly:** the app was re-formatting the whole answer up to fifty times a second while it arrived. It now formats once, at the end, and looks identical.
- **Opening Atlas did its work twice:** two triggers were starting the same analysis. Now one does.

### Libraries
- **Every action above your documents is now one tap:** five icons on a single row instead of two buttons and a three-dot menu. Nothing hidden, nothing removed, and both delete actions still confirm first.
- **Press and hold on a library now behaves like the rest of iOS:** the old custom gesture competed with sideways scrolling, so holding a library sometimes scrolled the row instead.
- **Creating a library no longer suggests a name you already have:** the suggestion counted your libraries instead of reading their names, so after a deletion it could propose one already in use.
- **Importing certain documents could freeze the whole import queue:** one file-path lookup could deadlock, and everything queued behind it waited forever. Fixed at the root.
- **Switching between libraries no longer resets your place or flashes the screen:** the library picker was rebuilding itself from scratch on certain switches, which reset its scroll position and made the screen visibly redraw.

### Your Documents
- **A document's auto-generated tags no longer come from its bibliography:** the app samples the start, middle and end of a document, and on a research paper the end is the reference list — so a third of what it read was author surnames. The same paper produced "dopamine, motivation, serotonin" on one import and "cho, merten, pychatry, zeng" on another. The bibliography half of this is fixed and confirmed on August 26, with 137 reference passages excluded on that same paper. The mangled "pychatry" is a separate problem that is still there: the journal prints its name sideways down the page edge, that strip scans badly, and the result gets treated as a heading. It is recorded and is not claimed as fixed.
- **Tables in Word documents were being thrown away:** each one was read into rows and then dropped, so a document could import looking fine with all of its numbers missing.
- **Images keep their layout:** every image became one unbroken line of text before anything downstream could read it.
- **Photographing a page now matches importing it:** camera captures came out as flat text where the same page imported as table cells.
- **Text from a PDF page is no longer shuffled into the wrong order:** lines were sequenced by a comparison that treated any two lines closer than a fixed distance as level, then ordered those by left edge — and that distance was wider than the line spacing of a typical journal article, so neighbouring lines came out swapped. Every word was read correctly; the paragraph simply arrived scrambled.
- **Scanned pages report their scanning honestly:** a fully scanned PDF used to tell you it had scanned zero pages.
- **Pages, Numbers and Keynote files now fail clearly.** They were never actually readable, so importing one no longer looks like it worked.

### Search
- **More than half of every document never reached the part that makes it searchable:** a padding setting capped text at 128 tokens against models built for 512, and made the length check return the same number for every input, so nothing could notice. Measured over 139 live chunks: 90% cut short, 55% of all library content never embedded.
- **The model that reads meaning was looking at one position instead of the whole passage:** re-exported to average across the passage as it was trained to, moving rank-1 retrieval from 0.000 to 0.571 across 21 paired test questions, 12 better and none worse.
- **Libraries you already have will now offer to rebuild their search index, once:** this release changed how text becomes searchable twice over, and anything indexed before the update was built the old way. The app now notices and offers a rebuild rather than leaving those libraries quietly worse. Nothing is deleted and the library keeps working meanwhile.

### Answers
- **A long answer is no longer replaced by a one-line stub.** After the app writes a long answer, a final stage re-reads every claim in it against your documents. That stage was given a smaller budget than the answer it was checking, so on a long answer it could be shown as little as one and a half percent of it and then replace the whole thing with a fragment. It now keeps its share of the budget for the answer rather than letting the evidence take all of it, and if it still cannot see enough of the answer to judge it fairly, it declines and leaves the original alone.
- **The app stopped treating research papers as parts catalogues:** the word list that signals "this person wants a spec value" contained "min", matched anywhere in the text rather than as a whole word, so every question about dopa-**min**-e switched on scoring built for datasheets. It also read "often" as feet and "example" as amps.
- **Reference lists no longer get cited as sources:** a bibliography matches keywords beautifully and states no facts. Two of twenty sources in a real answer were citation entries.
- **Search ranks section headings again.** A weighting mistake had dropped section paths out of ranking entirely.
- **Long questions can reach Private Cloud Compute** instead of being kept on device precisely when they were too big for it.
- **The evidence behind an answer was being put in an undefined order:** the rule deciding which passage outranks which treated close scores as equal and distant ones as different, which is inconsistent across three passages, and a sort given an inconsistent rule has no defined result. It now uses a rule that always agrees with itself.
- **Deep Think was writing its answer from a fraction of what it actually found:** it could retrieve the right passages and discard most of them, including the best one, before writing a word.
- **An answer that cites your documents can no longer be replaced by one that cites nothing:** one editing pass could replace the answer on length alone with no citation check, and the citation counter only recognised one of the two ways sources get written, so the protection silently switched itself off.
- **An answer can no longer tell you your documents are silent while quoting them:** the check meant to catch a bad answer only confirmed its citation numbers pointed at real passages, so an answer asserting "no evidence in the documents" while citing twenty of them was certified at 88% confidence. An honest "I couldn't find this", citing nothing, is untouched.
- **Citations now always point at a source that's actually there,** and confidence can report a genuine failure instead of always settling on a reassuring middle number.
- **Combining keyword and meaning-based search stopped losing to keyword search alone.**

### Settings
- **Settings is a searchable list instead of one very long scroll.** It was fifteen stacked panels with everything at the same volume. It's now about ten rows in sections, each opening its own screen, with search at the top. Nothing was removed, type "temperature" and you land on it.
- **The generation controls are reachable,** in one tap, under Settings → Advanced. Temperature and response length were fully built with no way into them, and both genuinely change how answers are written, on this device and on Private Cloud Compute alike.
- **You choose how the model picks its words, and Top-P finally does something.** The app decided this for you and always landed on the same setting, so the Top-P control was read and then ignored. Top-K, Top-P and Greedy are now a choice. Existing behaviour is unchanged unless you change it.
- **Answers can be made reproducible.** Turn on "Reproducible answers" and the same question against the same library returns the same answer every time.
- **The controls that never affected Apple Intelligence now say so** rather than sitting under a heading claiming they shape every response.
- **Five switches that did nothing are no longer switches.** Writing Tools, Speech Analysis, Translation, Screen Awareness and Image Playground are real and always on; the toggles never controlled them.

### Every Word, Explained Where You Read It
- **Tap any figure the app shows you and it tells you what it means:** "38 TOPS", "32/batch", "768 search", "Chunks", "Vectors", where they already are.
- **Two explanations for each, not one:** a plain one first, and the mechanism underneath if you want it. Turn the technical version on once and it stays on everywhere.
- **The four import stages explain themselves while they run:** Extract, Chunk, Embed and Index are tappable during the import you watch on first launch.
- **Nothing is buried:** Settings has the full list under Plain English, searchable, including by the technical name if that is the word you know.
- **Tapping a Plain English term now reliably opens its definition** instead of sometimes animating to nothing and leaving the back button pointed at a blank screen.
- **Plain English covers a lot more of the app:** seven new entries, including Standard vs. Deep Think vs. Maximum, where an answer actually gets written, and the trust cluster, confidence, fidelity, the live verification checklist, and the "Abstained" badge.

### Your Libraries
- **"Remove Local Copies" is now "Remove All Documents":** it never only removed local copies, it deleted those documents from iCloud and your other devices while saying Sync Now could bring them back.
- **Emptying a library cleans up properly:** documents used to stay in Spotlight search and their files stayed on disk.
- **Moving a library off iCloud asks first.** One tap used to remove its iCloud copy with no warning.
- **The Documents toolbar stops hiding buttons off-screen.** Library Settings and the two destructive actions are in one visible menu.
- **Two libraries with the same name can be told apart.**

### Your Database Tab
- **Pick any library to inspect,** instead of only "All Libraries" or whichever one was active.
- **"All Libraries" shows all of them,** and the list says which library you are looking at.

### Library Settings
- **Changing the embedding model no longer wipes your vectors before you agree to rebuild them.** Choosing "Later" used to leave a library holding documents it could not search.
- **The chunk size sliders stop where the app actually stops:** they offered up to 600 words and 200 overlap while importing capped them at 260 and 50.
- **Two untrue descriptions corrected:** chunks are not split by comparing meaning between sentences, and the storage format described is no longer the one in use.

- **Deleting a library from its settings screen no longer half-works:** if iCloud refused, it removed the library locally anyway and the next sync brought it back. It now stops and says why.

- **The two destructive actions no longer look like the same button:** one empties a library, the other removes it, and they now say which is which.
- **"Cached Documents" is hidden until there is something in it.** It was always empty because nothing fills it yet.

- **On a Mac, a backgrounded Shortcut could reach Private Cloud Compute with nobody present to approve it:** the foreground check only ran on iPhone and iPad.
- **No cloud request when the app cannot read your remaining quota:** it answers on device instead of guessing.

### Things The App Was Claiming That Weren't True
Settings describes what the app is doing while it answers you, and several of those lines described things the code does not do.
- **Three places in the app still described Private Cloud Compute as something it does today:** the Model Info card checked whether Apple Intelligence was available rather than whether PCC was, How It Works said the app "asks" before escalating, and the sample documents had a section headed "When does PCC activate?". The App Store text and README were corrected in August; the copy inside the app was missed. All three now describe the build you are running.
- **It listed eight agentic tools, and all eight were the wrong ones.** Four are actually wired up; those four are what it names now.
- **Two advertised features did not exist,** and the model picker listed a tier the app cannot select. Both gone.
- **Speed figures that were never measured have been removed,** including from the sample documents the app reads back to you as fact.

### The App Itself
- **The upload status stops breaking its own words in half:** "Processing uploads" could render as "Process / ing / uploads" when the controls beside it left too little room.
- **The app icon now follows your device's dark mode:** the existing light mark stays the same, and a matching dark appearance is selected when your device uses dark mode.
- **Your device is identified correctly.** iPhone 17 and M5 hardware reported itself as "A12 or Older".
- **The first screen no longer cuts off its own text.**
- **The chat controls match each other,** and the mode menu shows which mode is active and how many Maximum runs are left.

## 4.9

Documents no longer disappear after importing, and libraries carry their work between devices instead of asking you to redo it.

> iPhone and iPad arrive here from 4.7, because 4.8 was withdrawn before it shipped on iOS, so everything under 4.8 below is new to you too. On Mac, 4.8 was already released, so only this section is new.

### Your Libraries
- **Documents stop disappearing after import:** a document that finished importing while the app was saving your library could be dropped from the list even though it had imported correctly. This affected a single device as well as several, and it is what made the sample documents unreliable.
- **No more re-importing on your other devices:** documents processed on one device now carry over.
- **Libraries no longer appear to lose documents** while iCloud is still catching up.

## 4.8

Deep Think and Maximum were not wired up correctly in previous releases. This release fixes that, and everything it uncovered.

### Deep Think & Maximum
- **Both modes now reason across your documents.** Previously they returned Standard quality answers after a much longer wait.
- **Answers cite their sources in every mode.** Maximum produced none at all.
- **Both stop once they stop finding new material,** typically halving Maximum's run time.
- **A single failed pass no longer ends a query.**
- **Resolved "The selected model isn't available right now."**

### Privacy & Routing
- **On-Device now covers the entire query,** including the final answer.
- **The model picker governs every mode.** It previously reached Standard only, so Deep Think and Maximum fell back to a default.

### What You See
- The live pipeline names each stage correctly, including verification and query rewriting.
- Reasoning detail wraps instead of cutting off mid-sentence.
- Follow-up suggestions come from the answer rather than stray words.
- Raw model output no longer appears in answers.
- Passes skipped for having no relevant text are shown instead of leaving gaps.
- An answer reporting that your documents do not cover something is kept, not replaced with generic help text.

### Also
- **Document import works on Mac.** The file picker there was a placeholder.
- Opening the app after an update now shows what changed.

## 4.7

- **Honest route labels:** labels now say exactly where each answer ran, on your device, or Apple Private Cloud Compute with your permission. Nothing claims more than the system can verify.
- **Steadier document understanding:** the key ideas pulled from your documents now come out the same every time, for more consistent search and more reliable connections across files.
- **Route verification:** new internal checks confirm that every answer's recorded route matches what actually ran.
- **Removed unsupported model claims:** Settings no longer advertises selectable 3B or 20B on-device models, or a parameter-count capability chip. (Correction to earlier releases: the public SDK exposes no such selector. Apple's larger on-device model is real and managed by the operating system, but no app can choose or observe it.)

## 4.6

### Reliability & Accuracy
- **Evidence-informed Private Cloud Compute routing:** OpenIntelligence now retrieves locally before deciding whether a response actually benefits from PCC. Long-context and multi-document synthesis can use a minimized evidence envelope after a live entitlement/quota check and explicit payload consent; insufficient evidence never triggers cloud escalation.
- **Truthful route receipts:** Response metadata separately records the intended, attempted, actual, fallback, and completed execution route, so the UI no longer presents a prediction as the route that ran.
- **A deterministic model picker:** Hybrid stays Hybrid after a query and after relaunch. On-Device stays local. PCC requests PCC whenever it is usable, then completes on-device if its quota or another PCC gate is unavailable.
- **A route badge on every Apple-model answer:** Green means the answer completed on-device, blue means PCC completed it, and amber means PCC was requested but the on-device fallback completed it. Tap the badge for the full route receipt.
- **Safe cloud fallback:** If consent, network availability, entitlement, quota, or PCC availability prevents cloud execution, Hybrid and explicit PCC requests fall back locally before meaningful streaming. Cloud and local partial responses are never mixed.
- **Consent that stays remembered:** Always Allow and Never Allow now survive relaunches even if an older PCC setting is stale. OpenIntelligence no longer asks at startup; it asks only when an actual evidence package is ready for PCC.
- **GPU controls that describe reality:** The percentage slider is now four execution profiles. They coordinate the app's PDF, model-compute, large vector-search, and background-GPU policies without pretending to dictate exact GPU utilization.
- **Truthful model-route reporting:** The "Advanced" on-device model preference now correctly reports the standard on-device model in telemetry and diagnostics. (Apple's 20B AFM 3 Core Advanced is real but OS-managed, the public SDK exposes no way for an app to select it or observe whether it ran, so earlier releases could display a model tier the app never actually controlled.)
- **Apple-approved PCC capability enabled:** The source entitlement is active and the app verifies the signed process entitlement before constructing Apple's PCC model. Native PCC execution is owner-confirmed on a physical iOS 27 device; Archive/TestFlight distribution signatures and PCC edge scenarios (quota exhaustion, network transition, background consent) remain the open validation items.
- **Hardened knowledge-index migrations:** Database schema migrations are now driven by a fixed, code-owned migration catalog, eliminating a class of malformed-schema risk.
- **An ingestion Stop button that actually stops:** Closing or discarding the queue prevents those exact jobs from returning after iCloud reload. Automatic repair jobs run one at a time and stay off for that library on the device where you dismissed them until you explicitly import or rebuild again.

## 4.5.1

Version 4.5.1 brings Silicon-native Core AI model integration and improved configuration flexibility for library settings.

### Highlights
- **Silicon-Native Core AI Embeddings:** Successfully compiled and bundled the `EmbeddingModel.aimodel` format inside the package resources. This activates Apple's zero-copy memory paths for 40%+ faster sentence embedding execution natively on Apple Silicon. Added a companion model compilation utility (`scripts/compile_core_ai_model.py`) to easily convert PyTorch model graphs.
- **Historical Advanced Picker Corrected:** The earlier RAM-gated 20B label was not backed by a separate public Foundation Models selector. v4.6 removes that active claim and maps the legacy saved choice to the public On-Device target.
- **Mac Catalyst Window Tabbing Resolution:** Disabled automatic macOS window tabbing programmatically on Mac Catalyst targets. This resolves a layout collision where macOS natively grouped windows into redundant system-level tabs, keeping navigation clean and centered on the app's internal TabView structure.
- **Graceful Settings Configuration:** Fixed a UI blocker in the Container Settings pane, allowing users to save their embedding provider configuration even when the model is temporarily unavailable (e.g. during a migration). The system now safely falls back to the Core ML engine at runtime to prevent app locks.

## 4.5

Version 4.5 introduces the high-performance Rust-backed Tokenizer Engine alongside major ingestion stability enhancements and Core AI diagnostics.

### Highlights
- **Rust-Backed Tokenizer Engine:** Replaced the legacy pure-Swift `BertTokenizer` with a high-performance Rust-backed `swift-tokenizers` (DePasqualeOrg) wrapper target. This yields a large speedup in document tokenization alongside exact byte-level character offset mappings for citations. *(A "100x" figure was quoted here originally; it was never measured and was withdrawn 2026-08-06.)* Renamed the SPM wrapper library to `TransformersTokenizers` and moved the tokenizer resource bundles to the local `swift-transformers` package target. This completely bypasses Xcode file-system synchronized target resource collisions and flattening bugs, resolving compile-time and runtime loading issues.
- **Ingestion Pipeline Stability:** Resolved critical FTS5 index truncation, page offset mapping errors, and background sweep race conditions during batch-based streaming ingestion. Added optional `append` support to `store(...)` methods in `SQLiteFullTextService` to keep large files searchable.
- **Core AI Selector & Diagnostics:** Fully stabilized on-device Core AI sentence embeddings on iOS 27+ / macOS 27+ targets. Cached the provider instance, introduced an awaitable model readiness gate, and added compile-time and runtime diagnostics in the settings pane to guide toolchain resolution.
- **CI/CD Build Toolchain Update:** Updated all GitHub Actions CI/CD workflows (CI, App Store, and Release) to run on `macos-26` images to natively support the modern Swift 6.2+ / Xcode 27+ build toolchain.

## 4.4

Version 4.4 introduces the new **Evidence Threads** capability alongside refined local execution boundaries.

### Highlights
- **Evidence Threads (Phase 1):** Ephemerality is eliminated by allowing queries and cited passages to be persisted in durable research threads. Conversation histories are saved as JSON files scoped per knowledge container under the `Application Support/EvidenceThreads/` directory, bidirectionally synchronized across user devices via iCloud Drive using coordinated file system helpers. Thread creation is gated by monetization tier quotas (5 Free / 20 Pro / Unlimited Lifetime) and integrates Siri App Intents for voice-based Shortcuts listing and thread generation. Replaced skeletal data structures with the production-ready `ChatMessage` model to preserve rich citations, metadata, and responses on disk.
- **Production UI Sidebar:** Integrates a slide-out `ThreadSidebarView` directly within `ChatScreen.swift` matching the unified Liquid Glass Design System. Users can create, switch between, and delete research threads seamlessly via a new leading toolbar navigation button.
- **Diagnostics-Only Exposure:** Introduces dedicated engineering telemetry and developer diagnostic views (`EvidenceThreadDebugView` and `EvidenceThreadDebugService`) to safely verify atomic persistence boundaries without affecting production chat views.
- **Entitlement Realism:** Confirmed that the Pro subscription tier caps document ingestion at a hard limit of 1,000 documents to respect device memory limits. Unlimited document storage is reserved exclusively for the Lifetime tier.
- **Native Private Cloud Compute:** Integrates native `FoundationModels.PrivateCloudComputeLanguageModel` execution when running on iOS 27 / macOS 27+. Older OS versions use real local `SystemLanguageModel` execution; PCC is never simulated or mislabeled.
- **RAG Refinements & Model Constraints**: RAG verification gate logic is refined to prevent false-positive refusals by ignoring query-specific terms and performing fuzzy plural/singular word mappings. Standard and reliability modes respect ungrounded fallback preferences, and the On-Device policy strictly bypasses PCC while using the live local context budget. Swift 6 and diagnostics fixes are included, alongside Notion roadmap access, HUD placement improvements, and isolated New Chat threads.

## 4.3.1


Version 4.3.1 introduces crucial macOS UI layout updates and resolves deep system-level file-lock hangs during iCloud synchronization.

### Highlights
- **Flawless UI Fluidity:** Eliminated deep system-level file-lock hangs that could freeze the app during iCloud synchronization, keeping the interface locked at 120fps. Expanded background file isolation across conversation transcripts and library containers to guarantee absolute Main Thread fluidity.
- **Polished macOS Elements:** Perfected layout bindings for the telemetry HUD on native Mac Catalyst/macOS builds so nothing overlaps the chat input field or Unified Metrics Bar, properly re-enabled native Image Playground "Illustrate" support, and introduced native `ShareLink` and `NSSharingServicePicker` sheets for exporting trace logs and sharing the app.
- **iCloud Sync Hardening:** Resolved a persistent queue loop where deleted ubiquitous iCloud files could be resurrected as paused ingestion tasks across devices, and eliminated a massive background extraction race-condition that would duplicate background vision OCR pipelines during self-healing rebuilds.
- **Forced LLM Generation:** Disabled the legacy extractive override bypass to guarantee all queries are properly synthesized by the LLM instead of returning raw truncated text snippets.

## 4.3

Version 4.3 introduces full visibility and support for Apple's third-generation Foundation Models (AFM 3) alongside groundbreaking performance optimizations. Legacy architectural overhead has been eliminated and the RAG (Retrieval-Augmented Generation) pipeline is supercharged for massive libraries.

### Highlights
- **Live context budgets** now come from the public Foundation Models SDK where available, with labeled conservative fallbacks when the SDK cannot report an exact value.
- **Public Apple model targets:** OpenIntelligence uses `SystemLanguageModel.default` on-device and, on supported entitled systems, `PrivateCloudComputeLanguageModel` for eligible synthesis. It does not invent 3B, 20B, “Cloud Pro,” or server parameter-count identities that the public SDK does not expose.
- **Siri Screen Awareness:** Siri can now natively ingest on-screen files and URLs directly into local RAG libraries completely hands-free using the new AppIntents background context frameworks.
- **Lightning-Fast Answer Generation:** The RAG deduplication pipeline was completely rebuilt using an O(1) hash lookup, so evidence aggregation no longer degrades as the corpus grows. *(A "1,000x speedup" was quoted here originally; it was never measured and was withdrawn 2026-08-06. The complexity change is real.)*
- **Buttery-Smooth Database Dashboard:** The Database Dashboard now utilizes a dynamic UUID dictionary cache, eliminating per-row UUID string recomputation and the stutter it caused when scrolling large libraries. *(A "~240x" figure was quoted here originally; it was never measured and was withdrawn 2026-08-06.)*
- **Simplified Architecture:** Removed legacy, unneeded models like `OnDeviceAnalysisService` to rely entirely on modernized Apple Intelligence system APIs.
- **Bulletproof Reliability:** Expanded the RAG Evaluations suite to harden token budget obedience and Hybrid Search boundary logic, ensuring extreme stability for edge cases.
- **Enhanced Platform Sync:** Aligned internal OS targets with macOS 26 and iOS 26 while hardening background ingestion and on-device routing against resource-heavy loops.
- **Apple API Context Alignment:** Context packing uses live SDK budgets when available and labeled conservative fallbacks otherwise; oversized eligible synthesis is considered for PCC rather than assuming fixed public 4K/32K identities.
- **Unleashed Mac Hardware Scaling:** Rebuilt the hardware capability service to aggressively and dynamically scale background ingestion limits, RAM buffers, and concurrent evaluation vectors when installed on ultra-advanced Apple Silicon, unlocking pure supercomputer performance on extreme workstations.
## 4.0 & 4.1

Changes since 3.7.1:

Version 4.0 & 4.1 introduces the WWDC26 Apple Intelligence modernization suite, featuring dynamic model routing, Core AI frameworks, a first-class RAG Evaluations suite, local sentence embedding acceleration, live reasoning telemetry, and a beautiful Liquid Glass UI design.

### Highlights

- **Dynamic On-Device vs. Private Cloud Compute Routing**: Queries route from post-retrieval evidence and live capability/context data. Local synthesis uses `SystemLanguageModel.default`; eligible PCC synthesis uses `PrivateCloudComputeLanguageModel`.
- **Under the Hood UI Dashboard**: A details popover visualizes the active route, live or conservatively estimated token budget, resolved On-Device/PCC path, and query telemetry.
- **Core AI Native Embeddings**: Fully enabled and integrated the `CoreAISentenceEmbeddingProvider` under Apple's Core AI framework. Unlocks zero-copy Silicon-native sentence embeddings on iOS 27+ / macOS 27+ compatible devices, with dynamic auto-tuning and library settings configuration mappings.
- **Live Reasoning UI Telemetry**: Integrates the `ThinkingStreamView` directly inside the `UnifiedMetricsBar` at the bottom of the chat interface for real-time model thinking progress feedback.
- **Smooth GPU-Accelerated Transitions**: Replaced CPU-bound layout dynamic hierarchy calculations in the `IngestionQueueOverlay` with spring-animated opacity, scale, and offset transformations to avoid dynamic UI layout stutter, adding duration timers for ingestion tasks.
- **Metal GPU Vector Acceleration**: Implemented SIMD4 batch cosine similarity and normalization pipelines inside `GPUComputeService` using threadgroup-level memory buffers to accelerate vector search. *(A "4x" figure was quoted here originally; it was never measured and was withdrawn 2026-08-06.)*
- **Adaptive Ingestion Pipeline**: Integrated `PageComplexityAnalyzer` to pre-scan document structures. Digital PDF pages skip Vision OCR execution automatically (saving ~20% processing time), and the system dynamically scales rendering resolution (360-432 DPI) based on page density risk.
- **Suggested Questions & NLTagger POS Filters**: Refined suggested questions using `NLTagger` Part-of-Speech filters to keep suggestions grammatically clean, and added offline gold-standard questions to save startup battery and cold-start latency.
- **Database Safety & Physical File GC**: Switched `BNNSVectorDatabase` disk saves to atomic writes to prevent local file corruption. Added local physical file garbage collection in `WorkspaceSyncService` to purge orphaned documents.
- **Siri, Shortcuts & Spotlight**: Document and library items are now persisted App Entities (`OIDocumentEntity`, `OILibraryEntity`), enabling Siri/Shortcuts actions. Spotlight indexes down to specific chunks and sections.
- **RAG Evaluations Suite**: Built `RAGEvalRunner` to run evaluation datasets, tracking Recall@5, Citation Precision, and Hallucination metrics against spec targets. Exposes an Apple Evaluations Bridge for native compatibility with Apple's `fm CLI` testing suite.
- **Liquid Glass UI**: Styled components using modern native glass effect modifiers (`glassCardEffectHelper`) for a premium, wowed-at-first-glance user experience.
- **Agentic RAG Retry Safeguard**: Hardened agentic RAG reasoning loops with retry safeguards to preserve valid non-empty drafts and protect against rate-limited empty responses.


## 3.7.1

Changes since 3.6:

Version 3.7.1 (incorporating 3.7 updates) is a broader release that tightens almost every stage of the app: library management, import, retrieval, answer quality, chat ergonomics, and diagnostics.

## Highlights

- Resolved a gesture conflict on iOS where long-pressing library pills in the horizontal scroll view failed to trigger the context menu, fully restoring library deletion on iPhones.
- Preserved library names more cleanly in the Documents pill strip so file counts no longer squeeze them into ambiguous truncation.
- Fixed a synchronization issue in iCloud Sync where deleted libraries could be merged back and resurrected on other devices, and implemented deletion tombstones to automatically propagate deletions across all synced devices.
- Added automated local cleanup of vector databases, Spotlight search indexes, and UI presentation caches when a synced library is deleted on another device.
- Documents was tightened again with cleaner library pills, a less crowded header, smaller sync controls, and clearer organization and management surfaces.
- Shared-workspace and background-ingestion plumbing are more robust now, with safer queue cleanup, cleaner reconciliation, and better handling for long-running work.
- Camera capture, OCR-heavy pages, and mixed digital/scanned documents are handled more reliably during import.
- Clean digital text is preserved more faithfully, while noisy scans and visual pages still get the heavier recovery path when they need it.
- Retrieval is stronger across Standard, Deep Think, and Maximum, with better context packing, better use of surrounding document context, and less tendency to drift away from the source.
- Suggested questions and follow-ups are more library-aware, more grounded, and less generic across refreshes.
- Chat works better with direct attachments and captured content, so it is easier to bring new material into the conversation flow.
- Answer inspection is much richer now, with stronger source review, timing, retrieval-quality, and evidence details when you want to see how a response was formed.
- Technical answers and structured output render more cleanly now, including stronger code block handling and clearer response detail views.
- Diagnostics and device-aware performance behavior are more stable on larger libraries and longer-running work, with deeper inspection tools behind the scenes for validation and monitoring.
- Added native App Store rating and review prompting triggers after successful query tasks.
- Resolved Mac Catalyst layout truncations, including the Sync Mode picker, action chips, and scrollable library selector pills.
- Enabled full iCloud ubiquity container access and network permissions for Mac Catalyst by packaging universal sandbox entitlements.
- Resolved Xcode build catalog warnings with a unified universal AppIcon configuration across iOS and macOS targets.
- Redesigned the Silicon hardware telemetry HUD to dynamically rotate motherboard borders (SoC and Taptic outlines) to match device layout rotation, added iPad layout coordinates, and cleanly hid visual outlines on Mac targets.
- Hardened suggested questions and 3D visualization keywords to aggressively filter out OCR junk, syntax noise, and generic templates.

This release is about making the app feel more complete from import to answer review: fewer weak spots between "I added a file" and "I trust this answer."

## 3.6

Changes since 3.5:

Version 3.6 adds optional iCloud reuse for the libraries you choose, without giving up the app's local-first default.

If you've been building one library on iPad and wishing that exact processed library could show up on iPhone or your other devices without starting over, this is the update aimed at that problem - but now it works per library instead of as an all-or-nothing cloud mode.

Shoutout to Tim for asking for this.

## Highlights

- Every library can now be set to **Local Only** or **iCloud Drive** individually.
- New libraries now ask where they should live when you create them, and existing libraries can be switched later.
- **Local Only** libraries stay fully on-device unless you explicitly change them.
- Libraries you mark **iCloud Drive** can reuse imported files and processed state across your own Apple devices on the same iCloud account.
- The app now treats shared libraries by stable library identity instead of by name, so same-name iCloud libraries are much less likely to collapse into one mixed library unexpectedly.
- Explicitly choosing **iCloud Drive** for a library now acts like a direct opt-in instead of bouncing through a second generic chooser.
- Documents now includes a global iCloud refresh and review flow so another device's new, removed, or changed shared libraries can be pulled in or reviewed more deliberately.
- Shared-library removals are clearer too: if a library disappears from iCloud on another device, the follow-up review can now surface that change and let you decide whether to delete it here too or keep a local copy.
- Paid workspace capacity is clearer in this release too: **Pro** now supports up to **10 libraries** and **Lifetime** supports up to **20 libraries**.
- If a long-running import is interrupted on one device, another device can pick up queued work for that iCloud library instead of forcing you to restart from scratch.
- The iCloud controls in Documents and Settings are cleaner, shorter, and easier to understand, with clearer status, a dedicated place to manage storage, and less truncation on tighter layouts.
- The Documents tab layout is smoother in the 3.6 follow-up build, so the new sync surfaces are easier to read and tap without crowding the rest of the page.
- Canceling in-progress imports from the in-app queue is more reliable.
- Deleting a library or changing its sync setup now cleans up queued work more safely, so old documents from removed libraries are less likely to come back unexpectedly.
- Plain text and other digital text imports are handled more conservatively now, so normal files are less likely to be over-cleaned by OCR-style repair logic.
- Safer text preservation now applies across text, markdown, code/config files, CSV, transcripts, and Office/iWork-style digital documents, while noisy OCR and scanned inputs still use the heavier cleanup path.
- OCR and image-heavy imports are also more stable in this follow-up build.

This release is about making cross-device reuse practical without compromising the app's privacy-first, local-by-default model.

## 3.5

Changes since 3.2.5:

Sorry for the rough edges in the last few updates. Version 3.5 is the cleanup release that should have landed sooner.

If dense PDFs, exact-value lookups, starter prompts, or long-running imports felt less reliable than they should have, this is the corrective pass. It rolls up the real fixes shipped after 3.2.5 and makes the app more dependable on hard documents.

## Highlights

- Exact answers are stronger across Standard, Deep Think, and Maximum for direct source-backed questions over tables, specs, measurements, counts, dates, prices, and similar exact values.
- Starter questions and follow-ups are more grounded and are less likely to surface weak, generic, or misleading prompts when the source support is thin.
- Onboarding, empty states, and the bundled sample workspace explain the app more clearly, including best-supported file types, the 4,096-token model limit, and when processing stays on-device versus uses Apple Private Cloud Compute.
- PDFs and images now share one adaptive visual-ingestion path, searchable figures and structured tables survive more often, and clean scientific PDFs are less likely to produce fake tables, broken headings, or reference-section noise.
- Table-heavy pages are less likely to collapse back into scrambled paragraph text during ingestion, which improves retrieval quality after re-import.
- Large user-initiated imports are more reliable, with better queue recovery, background cleanup, and stronger Live Activity behavior on long-running work.
- Library and settings copy better matches the app's real per-library isolation and runtime behavior.

## 3.3

This is a reliability and document-understanding update focused on making imports harder to lose and technical answers more trustworthy again.

## Highlights

- Large user-initiated imports now preserve queue state, resume more cleanly after interruption, and surface clearer progress while work continues.
- PDFs and images now use one adaptive visual-ingestion path instead of a manual fidelity toggle, so garbled, table-heavy, image-heavy, and small-text pages get stronger recovery automatically.
- Embedded PDF figures and standalone images are now preserved as searchable evidence with captions, OCR labels, nearby page context, and visual descriptions.
- Exact specification and table lookups are stronger, and starter questions stay closer to what the current library can actually answer cleanly.

## 3.2.5

This is a corrective quality update for the 3.2 line, focused on making obvious source-backed answers fast and reliable again.

## Highlights

- Exact lookups now lock onto table rows, specification values, measurements, counts, limits, dates, and prices more directly when the source clearly contains the answer.
- Deep Think and Maximum run a precision lookup before longer reasoning, so simple questions can still get short cited answers in higher-effort modes.
- Standard, Deep Think, and Maximum share stronger retrieval rescue for table and specification passages.
- Starter questions are generated from actual uploaded passages with stricter grounding checks instead of loose document labels.
- Exact measurement answers are cleaner and can include nearby equivalent units when the source provides them.

## 3.1

This is the user-facing 3.1 summary focused on document understanding, OCR reliability, and grounded answer quality after the rushed 3.0 cut.

## Highlights

- Deep Think and Maximum now preserve strong grounded partial answers if a late-stage generation interruption happens, instead of replacing useful output with a generic stop footer.
- Multi-column PDFs, noisy scans, and corrupted tables ingest more reliably, with layout-aware OCR fallback and better row and column preservation.
- Tables now retain stronger schema, row, and cell anchors, which improves factual lookups for specs, measurements, and statistical values.
- Weak first-pass retrieval now triggers a corrective evidence pass before answer generation, improving dense scientific PDFs and technical manuals.
- Final answers are stricter about evidence quality, with unsupported or weakly supported claims handled more conservatively before they reach the UI.
- Maximum mode now reasons over evidence more cleanly, with better clustering and less tendency to polish weak support into overconfident prose.
- Source review is clearer on hard documents, with better structured excerpts and stronger abstention when the corpus does not actually support the answer.

## Earlier Milestones

- App Store launch on iPhone
- Local document Q&A with citations
- Native Apple platform integration for privacy-first workflows

## Notes

This public summary is intentionally feature-facing. Internal engine changes, tuning values, and private roadmap details are not published here.

- Added the original model-preference dropdown. v4.6 supersedes its parameter-count labels with persistent Hybrid, On-Device, and PCC policies tied to public execution targets.
