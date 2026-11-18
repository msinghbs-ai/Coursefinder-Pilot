-- CF-247 (21 Oct 2026, AI fee reader first run, v2.15.309). The fee reader added 21 fee pages for the eight NZ universities (from the
-- central-page search and the division pages the AI found linked from Otago's fee page). Job provider-facts tried to read them and every
-- spend was refused as 'not_due': the central-page refresh rule (firecrawl.central_refresh_days, 30) holds a provider's central pages
-- for 30 days after any central-page spend, and only a page a person added was exempt. A page never read is not a refresh.
--   public.svc_fc_spend: the refresh rule does not hold a central page that has never been read (status found or reading, read_at null),
--   whoever added it. Re-reads of pages already read keep the 30-day rule.
-- Their attempts were reset the same evening (logged in admin_control_events, area fees) so the pages are read on the next runs.
-- Replaces: public.svc_fc_spend (refresh rule exemption: never-read pages, not only manual ones). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
begin
  if md5(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) <> '3e14ec8e79596ba415071c23434c15ea' then
    raise exception 'live public.svc_fc_spend differs from the definition this change edits';
  end if;
end $guard$;

do $edit$
declare v_def text := pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure);
        v_old text := $o$and fs.found_via = 'manual' and fs.status in ('found', 'reading')) then$o$;
        v_new text := $n$and fs.status in ('found', 'reading') and fs.read_at is null) then  -- 21 Oct 2026: any page never read (fee reader)$n$;
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'edit must apply exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $edit$;
