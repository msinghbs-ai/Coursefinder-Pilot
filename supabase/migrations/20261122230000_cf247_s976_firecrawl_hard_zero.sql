-- CF-247 S3 / P1, 22 November 2026: Firecrawl hard-zero budget gate.
-- Migration head before this change: 20261122180000.
-- Replaces the existing svc_fc_spend function body in place (one anchored branch only).
-- No new schema objects, cron jobs, edge handlers, reader or consumer API changes.
-- Immediate on deploy: firecrawl.daily_budget_total=0 (already set in production at 23:07 AEDT)
-- refuses scheduled, on-demand and provider Fill requests, without changing historical spend.
-- G3 frozen (75 functions / 48 relations / 592 columns): none touched.
-- The cap may later be returned to a positive amount only by separate Platform Admin direction.
DO $s3$
DECLARE
  v_before text := pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure);
  v_after text;
  v_anchor text := '  if v_host is not null and security.third_party_host_v1(''https://'' || v_host) then';
  v_replacement text := '  if security.fc_setting_num_v1(''daily_budget_total'', 15000) = 0 then' || chr(10) ||
    '    v_why := ''budget_zero'';' || chr(10) ||
    '  elsif v_host is not null and security.third_party_host_v1(''https://'' || v_host) then';
BEGIN
  IF strpos(v_before, 'v_why := ''budget_zero'';') > 0 THEN
    RETURN;  -- do not apply the anchored patch twice
  END IF;
  IF md5(v_before) <> 'fbc83317e0b4c313af9133f4cb9d6a2e' THEN
    RAISE EXCEPTION 'S3 Firecrawl spending gate changed since live rehearsal; rebase and re-verify';
  END IF;
  IF length(v_before) - length(replace(v_before,v_anchor,'')) <> length(v_anchor) THEN
    RAISE EXCEPTION 'S3 Firecrawl spending gate anchor absent or repeated';
  END IF;
  v_after := replace(v_before,v_anchor,v_replacement);
  EXECUTE v_after;
  IF strpos(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure),
             'v_why := ''budget_zero'';') = 0 THEN
    RAISE EXCEPTION 'S3 Firecrawl hard-zero assertion failed';
  END IF;
END $s3$;
