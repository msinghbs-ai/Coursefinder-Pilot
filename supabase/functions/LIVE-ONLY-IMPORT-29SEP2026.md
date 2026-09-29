# Live-only edge functions imported into git (29 Sep 2026)

Source for 27 Supabase edge functions that were deployed to project `fxcwkweaxjtknorudmwp` but had no source in this repository. Each was pulled read-only from the live project with the Supabase MCP `get_edge_function` tool on 29 Sep 2026 and written byte-for-byte (UTF-8, no reformatting). Nothing was deployed or changed on the live project.

These functions are **not** added to the deploy workflow allow-list by this change. Adding them (or retiring them) is a separate, deliberate step.

## How the import was done

- Every function had exactly one file (`index.ts`); the live entrypoint `/tmp/user_fn_<ref>_<id>_<n>/source/index.ts` maps to `supabase/functions/<slug>/index.ts`.
- None of the 27 import anything from `../_shared/`, so no `_live_shared/` copies were needed and no existing `_shared` file was touched.
- `import_map` is `false` for all 27; dependencies are inline `npm:`/`jsr:` specifiers.
- All 27 files pass a TypeScript syntax parse (`ts.transpileModule`, 0 diagnostics).
- Spot check: 3 randomly chosen slugs (`layer1-ca-ab-alis-degrees`, `layer1-ca-cna-programs`, `layer1-ca-qc-university-programs`) were re-fetched from live after writing; sha256 of the re-fetched content matched the committed file for all 3.
- `ezbr_sha256` below is Supabase's hash of the deployed bundle (not of the source file). It can be compared against a future `get_edge_function` call to detect a live redeploy.

## Inventory

| Slug | Live version | verify_jwt | Entrypoint | Files | index.ts bytes | index.ts sha256 | Live bundle ezbr_sha256 | Live updated (UTC) |
|---|---|---|---|---|---|---|---|---|
| `cf212-qs-endpoint-verify` | 3 | true | `index.ts` | 1 | 215 | `e52d8f7aad3a314ec17c6ff600178c83524caf98376e2a73d1992f9733e1b04f` | `2614efcbf118db5d549397b1471771b08139d3277129c678b90b1b9c5a46dcc6` | 2026-09-05 08:55 |
| `cf212-qs-evidence-upload` | 4 | true | `index.ts` | 1 | 215 | `e52d8f7aad3a314ec17c6ff600178c83524caf98376e2a73d1992f9733e1b04f` | `45c3d0c98f5110fa0959f52305eceace978b928e2d481f072cb3d528dbb5a2fa` | 2026-09-05 08:55 |
| `cf212-qs-page-probe` | 4 | true | `index.ts` | 1 | 215 | `e52d8f7aad3a314ec17c6ff600178c83524caf98376e2a73d1992f9733e1b04f` | `40fa7ce64a0da0a08e344af062743bc7eaf8b4852523fb8a528aa513335a7254` | 2026-09-05 08:55 |
| `cf213-qs-meta-probe` | 5 | true | `index.ts` | 1 | 215 | `faa31c2dc94934801809e864a415aacaa580c7cbd4ce4094e8f088b6ba15efd3` | `a8856d66940fb7568c84f8321938138cbfdc4271eaea7de72977ea617ebc5237` | 2026-09-05 08:55 |
| `cf231-qs2026-revalidate-once` | 3 | true | `index.ts` | 1 | 227 | `989126bfee124c83e29ab5b9cc94386004f3ca65cfcee679d2b4bc2a93505172` | `a11f621ff7e33470e7f4af6432dbdfa31365c9d261b994a6edc0a3336bc6fe42` | 2026-09-06 21:03 |
| `layer1-ca-ab-alis-degrees` | 6 | false | `index.ts` | 1 | 13922 | `94a36c471f8a599e69370b6ed00e74716d411166b3fb7bc11156e576c5eecc5e` | `d0dbeef3d88dcb03cd230433af5b905666ed657971414b693485c277892bcf2d` | 2026-08-18 00:10 |
| `layer1-ca-bc-epbc-programs` | 5 | false | `index.ts` | 1 | 10592 | `ec6b01732fbb6158b3aa035e80dd51bf36e5f77d1cca27eb67f7d9c65bc8c2a9` | `0968e108bf0a50418cb7fd94b2c93895edeff7d9ef84ff8ad725d5fdb9973a80` | 2026-08-17 13:13 |
| `layer1-ca-cambrian-programs` | 2 | false | `index.ts` | 1 | 6168 | `489541d6a32843f1e8c215139ace697b3d5f712668111ecc27d9e2007658187e` | `17168ee2b070404d2a7cd3bdce8650e2803c66d01342f97f3912e91d4c670888` | 2026-08-14 00:11 |
| `layer1-ca-cna-programs` | 2 | false | `index.ts` | 1 | 9405 | `ffc8e61730a92d90a77df51f07b303a3bae64071c7c9580bcda652c7bf2d292f` | `23b67893f63ba94e4f3ed77d00a42a87ab01f1847b5713868f28f592b05096f5` | 2026-08-17 00:55 |
| `layer1-ca-fanshawe-programs` | 2 | false | `index.ts` | 1 | 6750 | `267b96c562f338379e735369217254c3daa0599823d2d27f6bd577e67a01fcd1` | `c8661480aabf226fe240507b47e93542077a22c0f6645df5c9c38ed6c9f80fa6` | 2026-08-16 23:46 |
| `layer1-ca-firstparty-catalogues` | 2 | false | `index.ts` | 1 | 10718 | `edcdfc3fec8ae8ac62fb02377025127a2f69560f548c2a3ed6031ff2d996b558` | `bee9c72dc9b73c4b9df5672bdc1db9c2ee4ad763429f5a56735a89995d97298f` | 2026-08-17 00:51 |
| `layer1-ca-mb-programs` | 2 | false | `index.ts` | 1 | 7517 | `6d3cb7650bc361a7867a5eb75ac54ab0033c8b2c317c3bafa80c4ed7e7006733` | `dc2c77cc10bf2b729123d27b7b4bc59e51e92bfaeea6b5714bf4735e844c16ff` | 2026-08-17 01:16 |
| `layer1-ca-ns-sk-programs` | 4 | false | `index.ts` | 1 | 9253 | `3aa89dcf4716effbb10d768fb1c72403a1330179c08ef9417f03672e58eadfce` | `26277596824318498dafecd301ba60efe96950133c3e3d02abbccdb89dd73a41` | 2026-08-17 01:17 |
| `layer1-ca-provider-geography` | 2 | false | `index.ts` | 1 | 4558 | `3894db0edb503c8a306313e3ddf316591dd6b5bea18b7bef87da5d6295042fe1` | `332f268b004d3689c0eb64aa92520d89740c7c4dc1030acda834e0c2d295810a` | 2026-08-17 00:30 |
| `layer1-ca-qc-university-programs` | 2 | false | `index.ts` | 1 | 9570 | `d4ef96b79ec14e64bf66b8177826d81780a1ff89a4bea8ed81eeb4cfa019121f` | `768f0cb88e180f694834658e6420ab36793ccffed4cc033a239812764729bae2` | 2026-08-17 09:09 |
| `layer1-ca-sk-programs` | 2 | false | `index.ts` | 1 | 7557 | `1c1d50ae5626d659c76d9d42544ec9311e600de509f3a1f480935fc7c236a749` | `f75676aa028f722f617368cf19bb5567c5cdcbe32c9428afd9541414b422867f` | 2026-08-17 08:56 |
| `layer2-scholarship-extract-v2` | 3 | false | `index.ts` | 1 | 7733 | `62a49f2c5f30dca9f10e8e60af7941cff819c9f5b3487c1f2c13ca13b04422dc` | `b6d5044f272e5bf625a992949502100e10ea93769dd2103ff3c071bc6a51d947` | 2026-08-24 01:55 |
| `layer2-v2-diagnostic` | 2 | false | `index.ts` | 1 | 1210 | `e37c6c3b39f199e7806563102d527bb91b9b9ddde27c8f83c5c1fe0d7278e259` | `d773ee63474c08eacceec81a02808a7262e69aefe5549d8b193a3ac2ee2af9fb` | 2026-08-24 01:36 |
| `layer4-course-resolve` | 2 | true | `index.ts` | 1 | 2364 | `0d5134de743ad8f131054c2cb8efcc4970645de501cefc6df880715337ed987e` | `59e37209b745381abec7d8aaa500fd711cf200648238720edfe810c90fe6326a` | 2026-08-24 06:41 |
| `ranking-qs-2027-binary-recovery` | 2 | false | `index.ts` | 1 | 2952 | `e90851753ae3100d4aba8f48f6d0ace309867fad8076795500c13cd1a05efbc6` | `0ee618f7b59c1236c196d48bcf115b8763944e5e97b17934dc134867d484c338` | 2026-09-09 23:20 |
| `ranking-qs-2027-publish-recovery` | 4 | false | `index.ts` | 1 | 6965 | `df827ef0c0764421c03f06c29ef0f9f146de164b69e76c556dd07b92601306b3` | `2c02cd91053184f8bbeeddcc438379c0ed32d5d4e0eb66272b9d7c0d59ef98e1` | 2026-09-09 23:13 |
| `ranking-qs-backfill-once` | 5 | true | `index.ts` | 1 | 221 | `9cbfdf8470ae9aab39c01d320ac3cb2ec7ac5e208ebab02031fe7f12ed25ba18` | `2ce25c9c659faab6b9ea6e9a777beea99f384923dfe6c7c1352fe58fe0bfdea9` | 2026-09-05 17:20 |
| `ranking-qs-backfill-trigger-once` | 3 | true | `index.ts` | 1 | 220 | `60da3fc5e95f0c7f41ee373ae0bf22b505af31fa8b1298099a7712aa0049de49` | `bd8dd65791bc87d75cf45c1dbb58d223d40f29d27c77098a4237d4458983c643` | 2026-09-05 17:20 |
| `ranking-qs-source-recovery` | 3 | true | `index.ts` | 1 | 3598 | `c7f3b3c00e823aef15f62bb293b168cfb49250763c13d55ad77650cc686edfb0` | `86f82424b94d6bdb1474bc45d629f556fa66af79ac1f84d3a32437e5990ae558` | 2026-09-09 13:49 |
| `ranking-qs-static-backfill-year` | 3 | true | `index.ts` | 1 | 226 | `2019cdd87ef184183cd398d568f6f238a7b6d91b12f31b192d6363ff30b33309` | `59fc20c90d648cbe647b5f933ce11db2928cdc584e41e45eb19bba4a921c72ee` | 2026-09-05 17:20 |
| `ranking-qs-upload-recovery` | 2 | true | `index.ts` | 1 | 3164 | `1ef52587ce76c6ba690284b182a6397dab1fd14ab874286c4bacd8116a2f455d` | `81c5bc7e9810cbadaa26f69f7e2a9d43e3900d69e151379b580ff78b7ea497f9` | 2026-09-10 01:56 |
| `search-vector-gate` | 9 | true | `index.ts` | 1 | 319 | `bec432bc424ee958e7b5b0338172333d9c03124dfc2301783841b46589eef487` | `30cf541ad87c22787f8c2312f56272a1b23034650df8937a4f0a09e5d18dace3` | 2026-08-23 09:51 |

## verify_jwt summary (for the deploy allow-list)

- **verify_jwt = true (12):** `cf212-qs-endpoint-verify`, `cf212-qs-evidence-upload`, `cf212-qs-page-probe`, `cf213-qs-meta-probe`, `cf231-qs2026-revalidate-once`, `layer4-course-resolve`, `ranking-qs-backfill-once`, `ranking-qs-backfill-trigger-once`, `ranking-qs-source-recovery`, `ranking-qs-static-backfill-year`, `ranking-qs-upload-recovery`, `search-vector-gate`
- **verify_jwt = false (15):** `layer1-ca-ab-alis-degrees`, `layer1-ca-bc-epbc-programs`, `layer1-ca-cambrian-programs`, `layer1-ca-cna-programs`, `layer1-ca-fanshawe-programs`, `layer1-ca-firstparty-catalogues`, `layer1-ca-mb-programs`, `layer1-ca-ns-sk-programs`, `layer1-ca-provider-geography`, `layer1-ca-qc-university-programs`, `layer1-ca-sk-programs`, `layer2-scholarship-extract-v2`, `layer2-v2-diagnostic`, `ranking-qs-2027-binary-recovery`, `ranking-qs-2027-publish-recovery`

## Retirement candidates

Already-retired stubs (live code just returns HTTP 410). Safe to delete from the live project after go-live, then remove from git:

- `cf212-qs-endpoint-verify`
- `cf212-qs-evidence-upload`
- `cf212-qs-page-probe`
- `cf213-qs-meta-probe`
- `cf231-qs2026-revalidate-once`
- `ranking-qs-backfill-once`
- `ranking-qs-backfill-trigger-once`
- `ranking-qs-static-backfill-year`
- `search-vector-gate`

One-off recovery functions that are **still executable** on live. Recommend retiring after go-live, ahead of the stubs:

- `ranking-qs-2027-binary-recovery` - One-off QS 2027 recovery. Still executable (not a 410 stub), verify_jwt=false, gated only by a hard-coded x-recovery-key literal that is now in git history. Retire (delete live) after go-live; treat the key as disclosed.
- `ranking-qs-2027-publish-recovery` - One-off QS 2027 recovery. Still executable, verify_jwt=false and has NO in-code auth check; guarded only by a state check on a fixed import id. Retire after go-live (high priority).
- `ranking-qs-source-recovery` - One-off QS recovery. Still executable (verify_jwt=true). Retire after go-live.
- `ranking-qs-upload-recovery` - One-off QS 2027 recovery. Still executable (verify_jwt=true). Retire after go-live.

## Other notes

- `layer2-v2-diagnostic`: Diagnostic endpoint (pilot-key gated). Review whether it is still needed in production.
- `layer4-course-resolve`: Operator-facing Layer 4 scalar resolve endpoint (user JWT). Appears to be live product functionality - keep.
- `layer2-scholarship-extract-v2`: Hard-codes CORS origin https://coursefinder-pilot.techm.workers.dev. Review before production.
- `layer1-ca-cambrian-programs`: Uses one-time nonce auth (svc_pilot_consume_nonce) rather than pilot key.
- `layer1-ca-fanshawe-programs`: Uses one-time nonce auth; hard-coded expected counts (22 pages / 204 programmes / 61 suspensions) will fail on catalogue drift.
- `layer1-ca-qc-university-programs`: Hard-coded expected counts (1424 segments / 1363 accepted / 17 DLIs) will fail on source drift.
- `layer1-ca-bc-epbc-programs`: Hard-coded expected mapping count (24).


## Retired on import (29 Sep 2026)
`ranking-qs-2027-publish-recovery` (no caller authentication) and `ranking-qs-2027-binary-recovery` (access key embedded in source) were replaced live with 410 'retired' stubs (versions 5 and 3, verify_jwt true) and the stubs are what is kept here. The original recovery code is not kept in this public repository.
