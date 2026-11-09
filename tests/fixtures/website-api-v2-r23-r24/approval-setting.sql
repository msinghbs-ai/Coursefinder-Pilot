-- The Platform Admin's approval paste for the G3 change R23/R24 (approval package, admin docs/platform/approvals/2026-11-06-g3-r23-r24-approval-package.md
-- section 9). A Platform Admin write, run BEFORE migration 20261109160000_cf247_website_api_v2_r23_r24.sql is applied; the migration reads this
-- setting (step 0) and refuses to apply without it, and no migration creates it. The Platform Admin approved the change on 9 Nov 2026; the
-- setting is the database-side record of that approval. It stays in place afterwards as the audit trail. Replaces: nothing. Retires: nothing.
-- Setting shape follows G2 (label, range, unit, section and used_by shown on Settings > Pipeline settings, changed with a reason).
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, section, used_by, help, reason)
values ('pipeline', 'api.v2_r23_r24_approved', 'Website API v2 R23/R24 consumer change: approved', 'number', '1', 0, 1, 'on (1) / off (0)', 'Website API',
        'migration 20261109160000 (G3 approval gate for Website API v2 R23/R24)',
        '1 = the Platform Admin approved the additive R23/R24 consumer change (provider campuses campus_id, campus_name, course_count; scholarship nationality_eligibility_status). The migration refuses to apply unless this is 1. It does not switch anything on after the migration has applied.',
        'Platform Admin (Mandeep Singh), 9 Nov 2026, in chat: G3 change approved for R23 and R24 on condition of API compatibility tests, developer guide and versioned handover');
