# PDF cell reader fixtures (CF-247 F-AER.07)

Reference data the reader is given in production, copied from the live database on 11 Nov 2026 (read only):

| File | Source |
|---|---|
| country-refs.json | `public.svc_entry_country_refs_v1()` (ISO 3166 names, 249 countries) |
| qualifications.json | `public.svc_aer_qualifications_v1()` (international qualifications and every-country words, migration 20261112060000) |

The table itself is `tests/fixtures/entry-matrix/pdf/wsu.json.gz` (WSU Entry Qualifications PDF, sha256 92aadee2…, the same stored copy the live source holds).
