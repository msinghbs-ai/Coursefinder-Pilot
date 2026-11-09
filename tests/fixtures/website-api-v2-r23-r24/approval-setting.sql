-- The Platform Admin's approval of the G3 change R23/R24 (approval package, admin docs/platform/approvals/2026-11-06-g3-r23-r24-approval-package.md
-- section 9), as the Settings page records it: Settings > Pipeline settings > Website API > "Website API v2 R23/R24 consumer change: approved",
-- value 0 -> 1 with a reason (public.admin_toolsets_write('setting'): Platform Admin only, range 0 to 1 checked, the change and reason kept in
-- pipeline.admin_control_events). It runs AFTER migration 20261109155000_cf247_r23_r24_approval_setting.sql has defined the setting at 0 and BEFORE
-- migration 20261109160000_cf247_website_api_v2_r23_r24.sql is applied; that migration reads the setting (step 0) and refuses to apply unless it is 1,
-- and no migration sets it to 1. Platform Admin authorisation: 9 Nov 2026 19:18 AEDT, in chat. The setting stays in place afterwards as the audit
-- trail. The fixture has no auth or audit tables, so only the settings row is changed here. Replaces: nothing. Retires: nothing.
do $approve$
declare n int;
begin
  update pipeline.platform_toolset_settings
     set value = '1'::jsonb,
         reason = 'Platform Admin (Mandeep Singh), 9 Nov 2026 19:18 AEDT, in chat: formal G3 authorisation of Website API v2 R23 and R24 including the documented campus-array content and ordering changes for 489 providers',
         updated_at = now()
   where toolset_key = 'pipeline' and key = 'api.v2_r23_r24_approved' and value = '0'::jsonb;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'the approval setting is not defined at 0 (migration 20261109155000 first)'; end if;
end $approve$;
