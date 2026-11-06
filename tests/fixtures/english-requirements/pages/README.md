# Verbatim stored English pages (governed test evidence)

One file per stored source page: `<fact_source_id>.md`, the markdown the coverage-sweep worker stored in the private `evidence` bucket. Each file's sha256 must equal the
`content_hash` of that fact source in `stored-outcomes.json` (the spec checks it). The six pages are filled by the one authorised read-only operation
`provider_facts_inspect` (Platform Admin, 6 Nov 2026 09:44 §3); no page is fetched from the web, no data is changed, no source is replaced, no credit is used.

| Provider | fact source id |
|---|---|
| UNSW Sydney (main English page) | a1a0f40d-001a-4df2-848e-0a49812a0ac8 |
| UNSW Sydney (international entry requirements) | 002ff3bb-4106-4844-b682-b2b6b0b90a27 |
| University of Auckland | 1214c1b4-8f19-4b55-b4a6-08a098bbaac4 |
| University of Auckland | 55d9b299-d974-4db5-8ec1-ec0af352f67f |
| University of Auckland | a65734e6-d5f8-487b-9979-8b7708de4ccd |
| University of Canterbury (IELTS test centre page) | 8e0fc6c9-9d45-4d16-87cc-12b13513dc29 |

Public university web pages only; no protected production data. `cf-247-english-verbatim-pages-contract.spec.mjs` fails (never skips) while a file is absent.
