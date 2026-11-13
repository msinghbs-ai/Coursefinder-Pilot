CREATE OR REPLACE FUNCTION public.svc_scholarship_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare v jsonb; v_reuse int := security.pipeline_num_v1('waste.page_reuse_hours', 24)::int; v_win bigint[]; v_tp text[]; v_off uuid[];
        v_scan int := security.pipeline_num_v1('batch.sch_ai_pick_scan', 60)::int;
        -- CF-247 P0 mandate 3 Nov 2026 §6: while the scholarship Firecrawl lane is held, only items with a stored copy are taken
        v_paid boolean := security.pipeline_num_v1('lanes.stored_first_on', 1) < 1 or security.lane_paid_hold_v1('sch_scrape') is null;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- CF-247 F-SCH 13 Nov 2026: one bounded window of the next items, in the picker's order and filters; only these are checked and leased
  -- (the due items are put in order first and the per-item checks run only until the window is full: offset 0 keeps them out of the sort)
  select array_agg(w.id) into v_win from (
    select o.id from (select q.id, q.provider_id, q.run_kind from pipeline.scholarship_ai_queue q
                       left join pipeline.scholarship_page_candidates cd on cd.id = q.candidate_id  -- F-SCH.15: never-decided pages first
                       where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
                       order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, (cd.admit_status is not null), q.id offset 0) o
     where (o.provider_id is null or o.run_kind in ('test', 'qualify') or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = o.provider_id))
       and (v_paid or security.scholarship_ai_has_copy_v1(o.id))
     limit greatest(20, least(v_scan, 2000))) w;
  -- the same two checks, once per distinct site and provider in the window (one row each), not once per item: 67 ms for 200 items, was 1.1 s per item check
  select array_agg(h.host) into v_tp from (select distinct on (security.site_host_v1(w.url)) security.site_host_v1(w.url) host, w.url
                                              from pipeline.scholarship_ai_queue w where w.id = any(v_win)) h
   where h.host is not null and security.third_party_host_v1(h.url);
  select array_agg(p.provider_id) into v_off from (select distinct w.provider_id from pipeline.scholarship_ai_queue w where w.id = any(v_win) and w.provider_id is not null) p
   where security.provider_sch_search_off_v1(p.provider_id);
  -- v2.15.271 (Platform Admin, 14 Oct 2026): pages on a directory site, and providers whose scholarship search is Off, are closed, not read
  update pipeline.scholarship_ai_queue q
     set state = 'failed', done_at = now(), leased_until = null,
         skip_reason = case when security.third_party_host_v1(q.url) then 'directory site' else 'scholarship search off for this provider' end
   where q.id = any(v_win) and q.state in ('queued', 'leased')  -- F-SCH 13 Nov 2026: the window only (was every due item: 27 s at 8,981)
     and (security.site_host_v1(q.url) = any(v_tp) or q.provider_id = any(v_off));
  -- CF-247 15 Oct (waste rules): a queued candidate whose page was stored within the reuse time takes that copy, so it is not read again
  update pipeline.scholarship_page_candidates c set storage_path = x.storage_path, content_hash = x.content_hash, evidence_id = coalesce(c.evidence_id, x.evidence_id)
    from (select distinct on (q.candidate_id) q.candidate_id, e.storage_path, e.content_hash, e.evidence_id
            from pipeline.scholarship_ai_queue q
            join pipeline.scholarship_ai_extractions e on e.url = q.url and e.storage_path is not null and e.error is null and e.at > now() - make_interval(hours => v_reuse)
           where q.state = 'queued' and q.next_try_at <= now() and q.candidate_id is not null and not q.fresh_read  -- CF-247 4 Nov 2026: an approved fresh read takes no copy
           order by q.candidate_id, e.at desc) x
   where c.id = x.candidate_id and c.storage_path is null and v_reuse > 0;
  with pick as (
    select q.id from pipeline.scholarship_ai_queue q
     where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3 and q.id = any(v_win)  -- F-SCH 13 Nov 2026: only from the checked window
       and (q.provider_id is null or q.run_kind in ('test', 'qualify') or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id))  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
       and (v_paid or security.scholarship_ai_has_copy_v1(q.id))  -- the others wait, with no try used (they were refused and closed after 3 tries)
     order by (q.run_kind = 'test') desc, (q.run_kind = 'qualify') desc, q.step desc, q.id
     limit greatest(1, least(coalesce(p_limit, 8), 20)) for update skip locked),
  upd as (update pipeline.scholarship_ai_queue q set state = 'leased', leased_until = now() + interval '4 minutes', attempts = q.attempts + 1 from pick where q.id = pick.id returning q.*)
  select coalesce(jsonb_agg(jsonb_build_object('queue_id', u.id, 'model_code', u.model_code, 'model', m.model_identifier, 'prompt_version', u.prompt_version,
           'prompt', (select p.text from pipeline.scholarship_ai_prompts p where p.version = u.prompt_version), 'run_kind', u.run_kind, 'url', u.url, 'recovery', u.recovery,
           'scholarship_name', (select s.name from scholarship.scholarships s where s.id = u.scholarship_id),
           'candidate_id', u.candidate_id, 'scholarship_id', u.scholarship_id, 'provider_id', u.provider_id, 'country', case when u.provider_id is not null then security.coverage_country(u.provider_id) end,  -- v2.15.256
           'provider', (select coalesce(pr.display_name, pr.canonical_name) from catalogue.providers pr where pr.id = u.provider_id),
           'currency', case when u.provider_id is not null then scholarship.provider_currency(u.provider_id) else 'AUD' end,
           'storage_path', case when u.fresh_read then null else coalesce(u.storage_path, (select c.storage_path from pipeline.scholarship_page_candidates c where c.id = u.candidate_id),
                                    (select e.storage_path from pipeline.scholarship_pages sp join pipeline.evidence_artifacts e on e.id = sp.evidence_id where sp.scholarship_id = u.scholarship_id),
                                    (select e.storage_path from scholarship.scholarships s join pipeline.evidence_artifacts e on e.id = s.evidence_id where s.id = u.scholarship_id),
                                    -- CF-247 15 Oct (waste rules): a copy of the same page stored within the reuse time
                                    (select x.storage_path from pipeline.scholarship_ai_extractions x where x.url = u.url and x.storage_path is not null and x.error is null and x.at > now() - make_interval(hours => v_reuse) order by x.at desc limit 1)) end)), '[]'::jsonb)
    into v from upd u join pipeline.scholarship_ai_models m on m.code = u.model_code;
  return v;
end $function$
