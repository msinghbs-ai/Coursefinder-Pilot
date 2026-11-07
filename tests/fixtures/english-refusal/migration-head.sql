-- CF-247 English requirements and scholarships: a refusal is not a failed page (agent: English and scholarships owner, 7 Nov 2026).
-- Why (live, read-only, 7 Nov 2026 07:00-08:00 UTC, project fxcwkweaxjtknorudmwp):
--   * pipeline.provider_fact_sources: 195 English pages (117 providers) are 'failed' with error "budget" and 64 with "target_list_refused": the worker's Firecrawl check
--     refused them, svc_provider_facts_read_next had already counted a try when it leased them, and svc_provider_facts_read_record closes a source at 3 tries. Three refusals
--     (22-27 Oct, while the budget was held) made them permanent: no further attempt, no new page attached (central_pages_attach_v1 counts every source toward central.attach_per_kind).
--     Providers that only have such pages: 52 providers / 762 courses without English (stage page_not_stored), 27 / 207 (target list), 18 / 438 more behind an approved rule.
--     The same functions serve intake_calendar (191 + 39 + 6) and fee_schedule (117 + 287) sources.
--   * pipeline.scholarship_ai_queue: 202 items closed "no scraper credit after 3 tries" (13-26 Oct) and 32 more at 2 tries (waiting 30 minutes each time; 8 calls on 7 Nov 07:16 all
--     "every item waited: waiting_scraper", refusal reason university_cap) are on the same path in svc_scholarship_ai_record. A budget or university-cap hold turns into a permanent failure.
--   (AER fetches got this fix on 29 Oct, migration 20261029001000: "a budget refusal is not the page failing".)
-- What:
--   1 security.provider_fact_refusal_v1(text): the names the worker records for a refusal.
--   2 svc_provider_facts_read_record: a refused read gives its try back and the source stays 'found' (parse_summary keeps the reason). Any other failure behaves as before (3 tries).
--   3 svc_provider_facts_read_next: a source refused within retry.provider_facts_refusal_hours is not offered again at once (so refused pages do not take the read slots of the others).
--   4 svc_scholarship_ai_record: a read put back (p_retry: credits, university cap, run time) gives its try back and waits retry.sch_ai_wait_minutes; it is closed only after
--     sch_ai.wait_max_days (an approved single read ends its request then). Real failures (page unreadable, AI error) still use their 3 tries.
--   Settings (G2): retry.provider_facts_refusal_hours (6), retry.sch_ai_wait_minutes (30, was written in code), sch_ai.wait_max_days (14).
-- Not done here: the sources and items already closed stay closed. Putting them back spends Firecrawl credits, so it is a Platform Admin decision with a paste file
--   (docs/paste/PASTE-20261107-english-refused-sources-requeue.sql, and its rollback). Nothing is switched on by this migration beyond the corrected accounting.
-- Consumer API: unchanged (G3). No table or column is added, changed or read by the website.
-- Replaces: public.svc_provider_facts_read_next(integer), public.svc_provider_facts_read_record(uuid,text,integer,text,text,text,jsonb,jsonb), public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean) (each md5-guarded on its live definition, replaced in place)
-- Retires: nothing.
-- Nothing is dropped or deleted by this migration.

-- 0 guards ---------------------------------------------------------------------------------------------------------------------------------------------
do $guard$
declare r record; v_md5 text;
begin
  for r in select * from (values
  ('public.svc_provider_facts_read_next(integer)', '5125d17949c155b56bd2b3a3903e6479'),
  ('public.svc_provider_facts_read_record(uuid,text,integer,text,text,text,jsonb,jsonb)', '1d365d6a6357e6a7db701a1814744604'),
  ('public.svc_scholarship_ai_record(bigint,jsonb,jsonb,text,numeric,integer,integer,numeric,text,text,text,text,jsonb,boolean)', 'b2fafccb2532afc3e0d1337588b5c43d')
  ) g(sig, md5) loop
    select md5(pg_get_functiondef(to_regprocedure(r.sig))) into v_md5;
    if v_md5 is distinct from r.md5 then raise exception 'live % (md5 %) differs from the definition this change was written against (%)', r.sig, v_md5, r.md5; end if;
  end loop;
end $guard$;

-- 1 settings (G2) --------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'retry.provider_facts_refusal_hours', 'Provider pages refused for credits: wait before offering again',
  'A provider page (English requirements, key dates, fees) that Firecrawl refused for credits or the target list is not a failed page: it keeps its tries and waits this long before the reader is offered it again.',
  'number', to_jsonb(6), 1, 168, 'hours', 1020, 'English policies', 'public.svc_provider_facts_read_next; public.svc_provider_facts_read_record',
  'Agent finding 7 Nov 2026: 259 English pages were closed after three refusals'),
 ('pipeline', 'retry.sch_ai_wait_minutes', 'Scholarship AI reads waiting for credits: wait between tries',
  'A scholarship page the reader could not fetch for credits or the university cap is put back and offered again after this long. It keeps its tries.',
  'number', to_jsonb(30), 5, 1440, 'minutes', 1021, 'Scholarships', 'public.svc_scholarship_ai_record',
  'G2: the 30 minutes were written in code'),
 ('pipeline', 'sch_ai.wait_max_days', 'Scholarship AI reads waiting for credits: close after',
  'A scholarship page that has waited this long for credits (created longer ago than this) is closed with the reason "no scraper credit within the waiting time"; an approved single read ends its request.',
  'number', to_jsonb(14), 1, 90, 'days', 1022, 'Scholarships', 'public.svc_scholarship_ai_record',
  'Agent finding 7 Nov 2026: replaces closing after three refused tries')
on conflict (toolset_key, key) do nothing;
