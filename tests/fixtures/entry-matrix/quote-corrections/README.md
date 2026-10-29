# Entry-matrix quote-correction fixtures (CF-247 AER reader corrections, worker v0.52.0)

Small excerpts that reproduce the table structure of three public entry-requirements pages, for `tests/uat/cf-247-s159-entry-reader-quote-corrections-contract.spec.mjs`. The printed text of each cell is copied from the public page (read 29 Oct 2026) and from the quotes of the live reads (kept rows in `catalogue.provider_entry_matrix`, dropped quotes in `pipeline.entry_matrix_runs.result`); the markup is a minimal rebuild of the page's structure, not the stored copy. A few rows only, no full pages.

Federation University uses the existing PDF fixture `tests/fixtures/entry-matrix/pdf/federation.json.gz`, whose PDF sha256 (5414e3cc52e81c2a81a4e05e14a7cadc33a96ecf18cf385f41de4a2295638f01) is the content hash of the live stored copy.

| Fixture | Source | Live run | Stored copy content hash | Fixture sha256 |
|---|---|---|---|---|
| uwa-score-tables.html | https://www.uwa.edu.au/study/how-to-apply/pathways-and-eligibility/international-and-overseas-qualifications | review item c70b3d2a | b2d394b5290e0fedf27afc1dbe2b587c4fbdcda349ebb6ff40f7efa45e96af2d | c3f836acd6ac5a0b1a9aa23cb48f2a05609173d81544ef7aa31abbbba68cee55 |
| uow-country-matrix.html | https://www.uow.edu.au/study/international/representatives/international-entry-requirements/ | review item 50b5cbf6 | 4277ee15179db4985209acab3956c3d39f4dc6fc5bdbaec19d2fc68e93d5dccd | 522b5b08c2b2b9ddc512d4d5813990e8cd7a51d7e3f04c3de05e7719b69dea7f |
| otago-country-tables.html | https://www.op.ac.nz/international/apply-and-enrol/entry-requirements | review item 5e40fcd8 | 370a12ce0da757986a1746dccbcb22588772f1032b3afdfd9cda5680ea8aa2fd | bdd937acb6459b7898419c0e827439cb287702fadad22d02cd2331423972abe4 |

Structure each fixture keeps:

- UWA: score tables of two columns (a `<thead>` table and tables whose first row is the column headings in plain cells), a worded grade table ("CDD | 7 | 70"), a range table ("330 to 339 | 76") and a table introduced by a sentence (Gao Kao).
- Wollongong: one matrix per country, the top-left cell empty, a row per qualification and a column per study level, followed by an "Assessment methodology" note.
- Otago Polytechnic: one table per country, the country printed on the accordion button just before it, two rows (NCEA Level 2 and Level 3), no header row.
