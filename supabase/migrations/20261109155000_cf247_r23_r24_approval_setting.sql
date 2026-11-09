-- CF-247 Website API v2 R23/R24, release step 1 of 2: define the Platform Admin's approval setting, NOT approved (value 0).
-- Replaces: nothing
-- Retires: nothing
--
-- Why a separate step: migration 20261109160000_cf247_website_api_v2_r23_r24.sql (the G3 consumer change, Pilot PR 945) reads the pipeline setting
-- api.v2_r23_r24_approved at its first step and refuses to apply unless it is 1; a setting that does not exist reads 0. A migration must not approve
-- itself, and the Platform Admin approves through the audited route, so the release is in two steps:
--   1. This migration defines the setting at 0 (off) so that it appears on Settings > Pipeline settings (section "Website API"), with its label,
--      range, unit and the line saying what uses it (G2). It changes no behaviour: nothing reads the setting until migration 20261109160000 is applied,
--      and with the value at 0 that migration still refuses to apply.
--   2. Only a Platform Admin (role rank 6 or higher) with an authenticated session changes the value to 1, on the Admin Settings screen
--      (Settings > Pipeline settings), with a reason; the decision of 9 Nov 2026 19:18 AEDT authorises it. That write is
--      public.admin_toolsets_write('setting') and is kept in
--      pipeline.admin_control_events (area toolsets, action setting, target pipeline.api.v2_r23_r24_approved, before, after, reason, actor).
--   Migration 20261109160000 is then applied.
-- Re-running this migration never changes a value that has been set (on conflict do nothing).
-- The setting does not switch anything on by itself, and it stays in place afterwards as the audit trail of the approval.
-- The consumer API is not touched: no consumer function, view, table, column or edge function is read for shape or changed. Nothing is dropped or deleted.
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, sort, section, used_by, help, reason)
values ('pipeline', 'api.v2_r23_r24_approved', 'Website API v2 R23/R24 consumer change: approved', 'number', '0'::jsonb, 0, 1, 'on (1) / off (0)', 307, 'Website API',
        'migration 20261109160000 (G3 approval gate for Website API v2 R23/R24)',
        '1 = the Platform Admin has approved the R23/R24 consumer change (provider campuses: campus_id, campus_name, course_count, one item per campus; scholarship: nationality_eligibility_status). The migration that makes the change refuses to apply unless this is 1. 0 = not approved (the setting as defined). It does not switch anything on after that migration has applied; it stays as the record of the approval.',
        'Defined at 0 (not approved) so the approval can be given through Settings with a reason (CF-247 R23/R24 release, step 1 of 2)')
on conflict (toolset_key, key) do nothing;
