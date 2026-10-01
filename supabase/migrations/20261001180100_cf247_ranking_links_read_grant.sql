-- CF-247 (Decision 208, fix): signed-in users could not open the QS and THE filters ("permission denied for function
-- admin_ranking_links_read", reported 1 Oct 2026 23:28). public.admin_read runs as the signed-in user and calls the
-- area read functions directly, so each must be executable by authenticated (as security.admin_ranking_read is).
-- 20261001180000 revoked it from authenticated. The function checks the person's role itself (Viewer and above).
grant execute on function security.admin_ranking_links_read(text, jsonb) to authenticated;
