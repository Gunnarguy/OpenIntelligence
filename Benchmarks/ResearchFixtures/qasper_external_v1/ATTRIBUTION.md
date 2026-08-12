# Attribution and licence

The documents in `fixtures/` are adapted from **QASPER**, used under CC BY 4.0.

> Pradeep Dasigi, Kyle Lo, Iz Beltagy, Arman Cohan, Noah A. Smith, Matt Gardner.
> *A Dataset of Information-Seeking Questions and Answers Anchored in Research Papers.*
> NAACL 2021.

- Source: <https://huggingface.co/datasets/allenai/qasper>
- Dataset revision: `fdc9d8214fbab5dd782958601db4d678e6934a54`
- Licence: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- Split: `test`, config `qasper`, 40 papers

**Changes made.** Each paper's title, abstract and full text were rendered to Markdown
with section headings preserved. Questions, answers and evidence are reproduced from the
dataset without modification. No content was added.

## Datasets deliberately not used here

This repository is public and backs a paid application, so a dataset that forbids
commercial use cannot be committed to it.

| Dataset | Licence | Status |
| :--- | :--- | :--- |
| `allenai/qasper` | CC BY 4.0 | used, attributed above |
| `PatronusAI/financebench` | CC BY-NC 4.0 | excluded, non-commercial |
| `allenai/scifact` | CC BY-NC 2.0 | excluded, non-commercial |
| `BeIR/scifact` | CC BY-SA 4.0 | excluded, conflicts with the line above |
| `BeIR/nfcorpus` | CC BY-SA 4.0 | permitted, share-alike on any derived files |

Licence values were read from the Hugging Face dataset cards. This is a record of what
the cards said, not legal advice.
