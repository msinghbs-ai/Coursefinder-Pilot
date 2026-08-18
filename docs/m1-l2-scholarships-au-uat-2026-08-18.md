# M1-L2-SCHOLARSHIPS — Australia first-source UAT

**Date:** 18 August 2026  
**Gate:** PASS — first authoritative AU Scholarship source implementation  
**Architecture baseline:** CourseFinder database architecture v2.10.23  
**Worker:** `scholarships-au-etl-v0.1.1`  
**Supabase project:** `coursefinder_Pilot` (`fxcwkweaxjtknorudmwp`)

## Gate scope

This gate proves real authoritative Scholarship enrichment against the accepted relational model. It is not a claim that every Australian scholarship has been loaded.

Required behaviours proven:
- stable source-native Scholarship identifiers;
- Scholarship identity separated from Offering Cycle identity;
- multiple Application Windows retained without cloning Scholarship identity;
- Scope separated from student Eligibility;
- compound `all` / `any` Eligibility groups;
- Award Tiers and Coverage represented separately;
- exact Provider mapping through accepted CRICOS identity where the source exposes CRICOS;
- raw source/evidence snapshots retained privately with SHA-256 lineage;
- dry-run, APPLY, replay and canonical idempotency;
- Scholarship rows remain unpublished until the later publication/Search gate.

## Source qualification

| Source key | Authority | Status | Stable identity strategy | Provider mapping / boundary |
|---|---|---|---|---|
| `au_study_australia_scholarships` | Australian Trade and Investment Commission — Study Australia | QUALIFIED | 32-hex source-local identifier embedded in the canonical Scholarship detail URL | Study Australia Provider source key -> Provider detail -> published CRICOS -> exact `catalogue.provider_registrations` match. Provider-name identity is prohibited. |
| `au_dfat_australia_awards` | Department of Foreign Affairs and Trade | QUALIFIED | enduring DFAT/OASIS award scheme `AAS`; `2027` is an Offering Cycle, not a new Scholarship | Government programme. Country/application rules are cycle/window/eligibility data, not Provider identity. |
| `au_education_rtp` | Australian Government Department of Education | BOUNDED | persistent government program identifier / DOI `10.82133/C42F-K220` | Central RTP identity/coverage is qualified. Provider-specific application timing is intentionally not ingested centrally because providers administer applications; provider windows require first-party provider evidence. |

Official source pages used by the worker include:
- `https://search.studyaustralia.gov.au/scholarships`
- `https://www.dfat.gov.au/people-to-people/australia-awards/australia-awards-scholarships`
- `https://www.dfat.gov.au/people-to-people/australia-awards/australia-awards-scholarships-opening-and-closing-dates`
- `https://www.dfat.gov.au/about-us/publications/australia-awards-scholarships-policy-handbook`
- `https://oasis.dfat.gov.au/`
- `https://www.education.gov.au/research-block-grants/research-training-program`

## Study Australia bounded source sample

Three source-native RMIT records were used to prove the mapping contract:

| Source identifier | Scholarship | CRICOS | Cycle | Award / coverage proof |
|---|---|---|---|---|
| `3d26fbb4f240456a8ffc71f9bd51ecf4` | RMIT Irana Turynska Scholarship | `00122A` | `current` | AUD 10,000 annually -> Award Tier |
| `d2ec6bbb95a42533d1bc38a55330b012` | RMIT David Phillips Memorial Scholarship | `00122A` | `recurring` | AUD 5,000 annually -> Award Tier |
| `475b48e53aeac5761f333d81f6e302ae` | RMIT English Language Bursary for Latin American Students | `00122A` | `2026` | 35% program-fee reduction -> Award Tier + tuition Coverage; published closing date retained as 1 December 2026 without inventing a time zone |

The first percentage parser used a trailing word-boundary after `%`, which cannot match punctuation-to-whitespace. UAT detected this before handover; worker v0.1.1 corrected the pattern and the corrected dry-run/APPLY/replay was repeated.

## Australia Awards proof

Canonical Scholarship identifier: `AAS`  
Offering Cycle: `2027` — study commencing in 2027.

Application Windows retained separately:
- `AAS-2027-MAIN`: 1 February 2026 09:00 AEDT -> 30 April 2026 14:00 AEST;
- `AAS-2027-PLW`: 30 March 2026 09:00 AEDT -> 30 June 2026 14:00 AEST.

Compound Eligibility:
- root group `2027:eligibility_all` — conjunction `all`;
- child group `2027:country_any` — conjunction `any`;
- 9 structured/narrative criteria total, including participating-country pathway, age, Australian citizenship/permanent-residency restriction, military-status restriction, prior-award interval, institution admission, Student Visa requirements and overlapping-funding restriction.

Coverage retained as 9 separate facts:
- 100% tuition fees;
- return air travel;
- establishment allowance;
- living expenses;
- Introductory Academic Program;
- Overseas Student Health Cover;
- conditional pre-course English;
- conditional supplementary academic support;
- conditional fieldwork travel.

## Dry-run UAT

Study Australia corrected dry-run:
- HTTP 200;
- stable source identifiers: PASS;
- exact CRICOS mappings: 3 mapped / 0 fallback mappings;
- 3 cycles;
- 3 windows;
- 3 Provider scopes;
- 3 eligibility criteria;
- 3 Award Tiers;
- 1 Coverage row.

Australia Awards dry-run:
- HTTP 200;
- stable identifier `AAS`;
- 1 Offering Cycle;
- 2 Application Windows;
- 2 criterion groups;
- 9 criteria;
- 9 Coverage rows.

Dry-run did not create canonical Scholarship rows before APPLY in the initial gate run.

## Corrected APPLY and replay UAT

Final canonical population after corrected APPLY:

| Relation | Count |
|---|---:|
| Scholarships | 4 |
| Source Identifiers | 4 |
| Offering Cycles | 4 |
| Application Windows | 5 |
| Criterion Groups | 5 |
| Eligibility Criteria | 12 |
| Scopes | 3 |
| Award Tiers | 3 |
| Coverage | 10 |

All four Scholarships remain `publication_status='unpublished'`.

Replay used the same Study Australia source identifiers and the same `AAS` scheme identity. After replay, all canonical counts above remained unchanged and every deterministic-ID fingerprint remained byte-for-byte identical:

| Canonical relation | ID fingerprint |
|---|---|
| Scholarships | `96203df1062d17a0f1e5c8d44a151715` |
| Offering Cycles | `3c14cc1d151fa9743c1b742a19fd6be1` |
| Application Windows | `7680638e21c4a957b3457c4d052c9657` |
| Criterion Groups | `08f0a78efba95347807d5ec23a9330e2` |
| Criteria | `7622006a9000613cde68c148dcc1d352` |
| Scopes | `ebc4950c24dea0750a16a8fdd9c28112` |
| Award Tiers | `2a5463b3d914499f282d36704ab249a2` |
| Coverage | `db52862b231baea866419365c5cb2f0f` |

**Canonical replay/idempotency: PASS.**

Evidence/source-record history is intentionally versioned independently from canonical identity. Dynamic upstream HTML can therefore create a new evidence/source-record version when bytes change without creating a duplicate Scholarship or child relation.

## Evidence and security UAT

- evidence bucket `evidence`: `public=false`;
- Scholarship evidence is stored under `layer2a/AU/scholarships/...`;
- raw HTML/PDF and manifest snapshots are content-hashed;
- source record versions retain source identifiers, provider source identifiers/CRICOS, payload, hash, observed/applied timestamps and evidence lineage;
- all `public.svc_scholarship_*` RPCs: `anon=false`, `authenticated=false`, `service_role=true` for EXECUTE;
- Pilot Edge invocation uses a one-time nonce and no persistent bearer secret in the request;
- no Scholarship row is currently published.

Performance advisor rerun after the gate no longer reports the newly introduced `pipeline.scholarship_source_qualifications.country_id` foreign-key index gap. Remaining performance INFO findings are inherited/project-wide or expected unused-index notices at this small data volume.

## Gate result

**PASS — M1-L2-SCHOLARSHIPS Australia first-authoritative-source gate.**

Accepted now:
- Study Australia source contract and worker;
- Australia Awards source contract and worker;
- RTP qualification boundary;
- stable identity/cycle/window/scope/eligibility/award/coverage/evidence semantics;
- autonomous dry-run/APPLY/replay/idempotency/security/performance UAT.

Not claimed by this gate:
- complete ingestion of all Study Australia catalogue records;
- provider-specific RTP application rounds;
- New Zealand Scholarship sources;
- Admin Scholarship workspace completion;
- student-facing Scholarship publication/Search projection.
