# Working rules for this repository (CF-247)

These rules come from the Platform Admin and apply to every change.

- **G1: every background job is catalogued.** A scheduled job is listed in `pipeline.automation_catalogue` (or `pipeline.admin_job_kinds` for tasks).
- **G2: no operational value is written into code (v2.15.269, 13 Oct 2026: "make sure in future it's not getting hard coded").**
  - A job's size, a re-read or retry time, a threshold or a limit is a setting in `pipeline.platform_toolset_settings`.
    - Pipeline values use toolset `pipeline` and are read with `security.pipeline_num_v1(key, default)`.
    - Service values use their own toolset, read with `security.toolset_setting` or `security.fc_setting_num_v1`.
  - Every setting has a label, a range, a unit and a `used_by` line. It shows on Settings › Pipeline settings or Toolsets & limits, where it is changed with a reason.
  - Scheduled job commands never contain a number. They pass `security.pipeline_num_v1('batch.…', default)`.
  - Worker code reads settings through `svc_worker_settings_v1`.
  - Only technical safety values stay in code: claim and lease timers, fire guards, the month roll-over, and API time-outs. Each such line is marked `-- fixed: <why>`.
  - `tests/uat/cf-247-s32-controls-in-settings-contract.spec.mjs` fails any migration from `20261013012900` on that breaks this.
  - `security.controls_check_v1()` raises a notice for any running job that does.
- **Website API v2 (`website-search-v2`, Decisions 257 and 258) is additive only.** Nothing the website reads is renamed or removed; the provider Published switch decides what is returned; null means not held. Before changing anything the website reads, read `docs/integrations/WEBSITE-DEVELOPER-REQUIREMENTS.md` in the admin repo (requests, status, open work). Keep `tests/uat/cf-247-website-api-v2-contract.spec.mjs` and `cf-247-institution-type-contract.spec.mjs` passing, and reissue the developer handover (Version 2, new change-log line) for any visible change.
- **Nothing is dropped or deleted by an applied migration.** Drops and deletes go to the Platform Admin as a paste file.
- **A passing qualification never switches anything on by itself.**
- Never create `package-lock.json`. Never commit the `node_modules` symlink.
