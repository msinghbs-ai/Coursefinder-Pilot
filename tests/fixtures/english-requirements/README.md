# English requirements: production-parity fixture and baseline

Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026), for the English requirements workstream (Platform Admin 6 Nov 2026 08:12: planning and independent validation only). Owner: agent H. Plan: admin `docs/platform/work-packages/2026-11-06-english-requirements-implementation-plan.md`.

This is the regression base for the English requirements PR. It shows today's behaviour, so that the PR can prove what it changes and what it leaves alone.

## Files

| File | What it holds |
|---|---|
| `manifests/english-path.json` | Expanded production-parity manifest from read-only `fxcwkweaxjtknorudmwp` capture, PostgreSQL 17.6. It holds 13 target tables, 5 lookups, 5 referenced tables and 48 functions (30 named, 17 trigger functions and 1 dependency), with 471 facts. Every definition matches its md5. |
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

`run.sh` does four things:

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
4. Applies the English group migration and executes all 71 group/scope/search/reparse/status assertions and all 17 named-exception/own-reading/manual-lock assertions on the production-shaped fixture. Each assertion must emit its actual Postgres PASS notice; missing assertions or a SQL error refuse the final round-trip PASS.

CI runs the Node job and PostgreSQL 17.6 service with a shared Unix socket at `/var/run/postgresql`. This satisfies the unchanged generated local-only guard without permitting a Docker bridge or remote server. `set -euo pipefail` preserves the fixture exit status through the log collector. Fixture SQL executes before output filtering; SQL/generator errors cannot be converted to an empty successful parity result.

## Verbatim pages (present)

All six governed stored-page extracts are already in `pages/<fact_source_id>.md`, obtained through the authorised read-only evidence inspection. The verbatim-page spec checks `sha256(page) = content_hash` in `stored-outcomes.json`. The UNSW full-page regression reads its fourteen faculty/level groups and named exceptions; Canterbury's wrong IELTS test-centre page remains a negative case. The earlier missing-page blocker is superseded; no repeat download or paid read is needed.

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
- **Scope boundaries.** The expanded manifest captures settings, course pages, manual locks and central search used by the group path. `groups-harness.sql` explicitly labels remaining local stand-ins, including the consumer publication refresh and downstream admission writer. These scenarios prove the actual policy/group/precedence functions against captured constraints; they do not establish production consumer publication or full downstream admission acceptance.
- **Prod-parity tool defect.** A `public` function's signature is printed without its schema, so the tool creates a stray schema named after it (for example `"admin_provider_policies_read(text,uuid)"`). The check still lists no difference. This has been reported to agent E, who owns the tool.

