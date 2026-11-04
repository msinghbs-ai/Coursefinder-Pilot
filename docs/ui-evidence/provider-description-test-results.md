# Provider Description development validation

Recorded 4 November 2026. All workflow writes below used the isolated PostgreSQL 17.6 fixture. No production writes, vendor calls, merge or deployment were performed by this workstream.

The actual existing FieldCoverage card and its unmodified Supabase RPC adapter ran against real SQL. The fixture controls authenticated identities, stored HTML delivery and the external model response. Reader extraction, quote/identity checks, price reservation, proposal recording, Layer 4 decisions and Website/Zoho projections execute the real implementations.

| Check | Result |
|---|---|
| Production-representative schema, positive workflow | 32 assertions passed; ten selected, ten proposals, zero admission before review, then ten authorised admissions and ten Website/Zoho verifications |
| Negative and recovery workflow | 29 assertions passed; policy, source/identity drift, manual locks, unsupported claims, duplicate work, cost reservations, review capacity, rejection, continuation and consumer mismatch |
| Database-backed desktop/mobile browser | 3 passed, 0 failed, 0 skipped, 0 flaky; 82.5 seconds |
| Layer 4 navigation | Exact keyset cursor reaches the target after 600 same-provider, same-kind, same-microsecond predecessors; all 601 review rows roll back |
| Final complete local UAT invocation | 1,877 passed, 2 runner timeouts, 0 skipped; 37.0 minutes |
| Post-rebase focused regressions | 147 passed, 0 failed, 0 skipped |
| The two timed-out UAT cases rerun alone | 2 passed, 0 failed, 0 skipped; 19.5 seconds, without retries or product changes |

The complete UAT invocation was **not** an uninterrupted green run. Its two failures were a 20-second element-stability wait in the existing Layer 4 release test and a browser-context teardown exceeding 120 seconds in the existing OpenRouter screen test. Both exact cases passed when rerun in a separate Vite server with separate output. No failing assertion was retired or skipped.

The browser workflow loses the HTTP response only after SQL commits Run Now. Recovery retains the same cohort and task. Independent SQL read-back confirms **one task, one fixed member, one reader row, one reader attempt and one actual governed worker dispatch**. The dispatch contains the exact cohort and the configured batch limit. A real pending Layer 4 item precedes the test-authorised decision. Catalogue, Website and Zoho then each verify the admitted description. The saved evidence explanation survives refresh. An actual rank-three caller is refused preparation and execution.

The extra browser case records one proposal/admission, one reported model call, simulated model usage of US$0.0001 and zero retries. The final fixture contains twelve admitted descriptions: the initial ten, the separate NZ continuation case and the browser case. [Saved browser result and SQL counts](provider-description-browser-result.json) distinguish these cases from the initial ten-provider target.

Performance uses 2,825 active published fictional providers: AU 1,279, NZ 416 and CA 1,130; 30,220 active courses. It includes 3,856 unsuitable stored copies for the largest institution and 600 copies for each of nine others. The approved About-page selection remains unchanged. Five samples per stage use the actual 8-second statement timeout and `lock_timeout=0` (disabled).

| Stage | Median | Maximum |
|---|---:|---:|
| Authenticated AU preview | 1,119 ms | 4,085 ms |
| Authenticated NZ preview | 271 ms | 348 ms |
| Authenticated CA preview | 31 ms | 122 ms |
| Dominant institution's stored source lookup | 26 ms | 29 ms |

These are isolated development measurements. They do not establish production latency. Raw plans, buffers and all samples are in [the benchmark](provider-description-benchmark.json).

Evidence:

- [Browser test summary](provider-description-browser-tests.json)
- [Initial ten-provider database result](provider-description-database-result.json)
- [Positive workflow and stage timings](provider-description-integration-results.json)
- [Negative and recovery cases](provider-description-negative-results.json)
- [Actual keyset navigation result](provider-description-navigation.json)
- [Desktop](provider-description-database-desktop.png) · [Phone](provider-description-database-phone.png)

Production acceptance remains the Integration Controller's responsibility after Platform Admin release authorisation. Actual production proposals, human decisions and publication must be measured separately within the documented post-deployment gate.
