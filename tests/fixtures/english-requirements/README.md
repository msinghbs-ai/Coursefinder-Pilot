# English requirements: production-parity fixture and baseline

Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026), for the English requirements workstream (Platform Admin 6 Nov 2026 08:12: planning and independent validation only). Owner: agent H. Plan: admin `docs/platform/work-packages/2026-11-06-english-requirements-implementation-plan.md`.

This is the regression base for the English requirements PR. It shows today's behaviour, so that the PR can prove what it changes and what it leaves alone.

## Files

| File | What it holds |
|---|---|
| `manifests/english-path.json` | Production-parity manifest, captured with `scripts/prod-parity-capture.mjs` on 6 Nov 2026 at 08:31 AEDT. Production `fxcwkweaxjtknorudmwp`, read only, PostgreSQL 17.6. It holds 5 target tables, 3 lookups, 4 referenced tables and 38 functions (24 named, 13 trigger functions and 1 dependency), with 282 facts. Every definition matches its md5. |
| `stored-outcomes.json` | The stored evidence for UNSW Sydney, the University of Auckland, the University of Canterbury and Massey University, read with SELECT only. It has their central English candidates, English fact sources (URL, status, `content_hash`, storage path) and every proposal (parser, status, style and the parsed content with its quotes). It holds no personal data: `decided_by` and actors are left out. |
| `baseline.mjs` | Builds today's cases from the stored evidence. The spec and `run.sh` share it. |
| `prelude.sql` | Local stand-ins for the Supabase built-ins that the definitions name: the `extensions` schema (pgcrypto) and `auth.role()` / `auth.uid()`. |
| `run.sh` | The database round trip (see below). |
| `tests/uat/cf-247-english-baseline-contract.spec.mjs` | The source contract. It runs in the default suite. |

### Manifest scope

- **Target tables:** `catalogue.course_english_requirements`, `pipeline.provider_policy_proposals`, `pipeline.provider_fact_sources`, `pipeline.central_ai_queue`, `pipeline.layer4_review_items`.
- **Lookups:** `ref.english_tests`, `ref.provider_types`, `ref.study_levels`.
- **Functions:** the policy route, from record through auto-approval, in force, level and group apply, plan and apply; the AI record; the Layer 4 English apply; the D162 table functions; and the panel read.

## Run

```
PGUSER=postgres PGHOST=/tmp bash tests/fixtures/english-requirements/run.sh
CI=1 npx playwright test -c pw-5291.config.mjs tests/uat/cf-247-english-baseline-contract.spec.mjs
```

`run.sh` does three things:

1. **Builds the fixture.** It builds the fixture from the manifest in `h_english_fixture` and requires the parity check to list no unexpected difference. The one allowed difference is PostgreSQL 17's `MAINTAIN` grant on 16; CI runs 17.6. The five functions the plan replaces must carry their live md5.
2. **Proves the production constraints refuse what production refuses.** These are the shapes the PR must respect:
   - a new proposal status;
   - a new `found_via`;
   - a second proposal with the same document, parser and content (so a re-read needs a new parser version);
   - a second row for a course and test when a withdrawn row exists (so a group rule must reuse the row, not insert).
3. **Files today's stored cases through the live copy of `svc_provider_policy_record`:**
   - the UNSW faculty table read by today's parser is filed as `no_values`;
   - the 17 Oct AI reading of one UNSW faculty row is filed as `proposed` (the Platform Admin later rejected it);
   - the three Auckland AI readings are filed as `no_values`.

## Verbatim pages (open: needs the Integration Controller)

Agents cannot read the stored page bodies. They are in the private `evidence` bucket, and reading them goes through the worker's read-only `provider_facts_inspect` mode, which is a dispatch, or through a service-role storage download. Until the pages are added, the parser baseline uses only the cells that the database holds as text: the quotes of the 17 Oct UNSW AI reading, inside a layout stand-in.

When the Controller fetches the pages, they go in `pages/<fact_source_id>.md`. The check is that `sha256(page) = content_hash` in `stored-outcomes.json`.

| Fact source | Provider | URL |
|---|---|---|
| `a1a0f40d-001a-4df2-848e-0a49812a0ac8` | UNSW Sydney | `https://www.unsw.edu.au/study/how-to-apply/english-language-requirements` (the faculty table) |
| `002ff3bb-4106-4844-b682-b2b6b0b90a27` | UNSW Sydney | `https://www.unsw.edu.au/study/how-to-apply/international/entry-requirements` |
| `1214c1b4-8f19-4b55-b4a6-08a098bbaac4` | Auckland | `…/entry-requirements/english-language-requirements.html` |
| `55d9b299-d974-4db5-8ec1-ec0af352f67f` | Auckland | `…/english-language-requirements/pearson-test-of-english.html` |
| `a65734e6-d5f8-487b-9979-8b7708de4ccd` | Auckland | `…/supporting-documents/proof-of-english-language-proficiency.html` |
| `8e0fc6c9-9d45-4d16-87cc-12b13513dc29` | Canterbury | the IELTS test centre page (the wrong page; kept as a negative case) |

Massey has no stored English page, so there is nothing to fetch for it.

## Limits

- **Re-check against production.** The manifest was proven against production when it was captured. Re-check it with `node scripts/prod-parity-capture.mjs check-sql tests/fixtures/english-requirements/manifests/english-path.json`, run through the MCP tool. No rows means it is still current.
- **Not covered.** Function bodies that need objects outside the scope fail when called: `policy_auto_approve_v1`, `english_level_apply_v1` and `provider_english_plan_v1` read settings, course pages, locks and the search projection. The PR adds those tables to the scope before it tests those functions in the database.
- **Prod-parity tool defect.** A `public` function's signature is printed without its schema, so the tool creates a stray schema named after it (for example `"admin_provider_policies_read(text,uuid)"`). The check still lists no difference. This has been reported to agent E, who owns the tool.
