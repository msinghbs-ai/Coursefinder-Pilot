-- CF-247 Decision 254 (5 Oct 2026). Fixes found on La Trobe (Platform Admin 13:02) after migration 1520.
-- 1. read_view sends back only pages not yet read with the international view (the bound page's last final address does
--    not carry the view) instead of every page read before the adapter was last saved, and can be limited:
--    only = 'view' (pages in the pattern), 'outside' (pages outside it left unread by an earlier view read) or 'all'.
-- 2. A page found by search (basis title_search or cricos_search) is read directly only. One that was rendered through
--    Firecrawl before, or was sent back by a view read, keeps the Firecrawl fallback (worker v0.17.6 reads the new
--    rendered_before flag), so La Trobe's handbook pages can be read again.
-- 3. A per-credit rate printed on a course page read in the international view (La Trobe graduate certificates,
--    "A$X full course duration (per 60 credit points)", "120 credit points represents full-time study for one year") can
--    be recorded with that course page as its evidence, not only a central page.
-- Snippet patches are md5-guarded and each is found exactly once. No text value in this file contains a semicolon:
-- where a replacement needs a statement break it is written {sc} and turned into a semicolon with chr(59).

create or replace function security.uni_adapter_view_requeue_v2(p_provider_id uuid, p_reason text, p_limit int, p_only text) returns integer
language plpgsql security definer set search_path = '' as $f$
declare n int; v_ids uuid[]; v_pat text; v_sfx text; v_only text := coalesce(nullif(btrim(p_only), ''), 'all');
begin
  if v_only not in ('all', 'view', 'outside') then raise exception 'only must be all, view or outside'; end if;
  select coalesce(nullif(btrim(u.page_view->>'url_pattern'), ''), '.'), coalesce(u.page_view->>'suffix', '') into v_pat, v_sfx from pipeline.uni_adapters u
   where u.provider_id = p_provider_id and u.enabled and coalesce(u.page_view->>'render', 'false') = 'true';
  if v_pat is null then raise exception 'the adapter names no international view to read'; end if;
  v_ids := array(select pg.course_id from pipeline.coverage_course_pages pg
                  join catalogue.courses co on co.id = pg.course_id and co.lifecycle_status = 'active'
                  where pg.provider_id = p_provider_id and pg.url is not null
                    and ((v_only in ('all', 'view') and pg.url ~* v_pat and pg.read_status in ('read', 'identity_mismatch', 'needs_render', 'fetch_failed', 'blocked')
                          and (v_sfx = '' or strpos(coalesce(pg.candidates->>'final_url', ''), substr(v_sfx, 2)) = 0))
                      or (v_only in ('all', 'outside') and pg.url !~* v_pat and pg.read_status <> 'read'
                          and exists (select 1 from pipeline.page_link_repairs x where x.course_id = pg.course_id and x.reason like 'university adapter: international view read%')))
                  order by pg.course_id limit greatest(1, least(coalesce(p_limit, 600), 600)));
  insert into pipeline.page_link_repairs(course_id, provider_id, old_url, new_url, reason)
    select pg.course_id, pg.provider_id, pg.url, pg.url, case when pg.url ~* v_pat then 'university adapter: international view read (' else 'university adapter: read again outside the international view (' end || left(p_reason, 300) || ')'
    from pipeline.coverage_course_pages pg where pg.course_id = any (v_ids);
  update pipeline.coverage_course_pages pg set status = 'bound', read_status = 'needs_render', read_attempts = 0, next_read_at = now(), leased_until = null where pg.course_id = any (v_ids);
  get diagnostics n = row_count;
  return n;
end $f$;
revoke all on function security.uni_adapter_view_requeue_v2(uuid, text, int, text) from public, anon, authenticated;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_uni_adapter_write(text,jsonb)'::regprocedure) is distinct from '7e3424a7416d31daddccce3794bef079' then
    raise exception 'admin_uni_adapter_write changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_uni_adapter_write(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$security.uni_adapter_view_requeue_v1(v_pid, v_reason, coalesce((p_args->>'limit')::int, 600))$s$,
          $s$security.uni_adapter_view_requeue_v2(v_pid, v_reason, coalesce((p_args->>'limit')::int, 600), p_args->>'only')$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.svc_coverage_read_next(integer)'::regprocedure) is distinct from '9bfcb79ff8da7eb53be7432278a2da37' then
    raise exception 'svc_coverage_read_next changed, not patching'; end if;
  v_def := pg_get_functiondef('public.svc_coverage_read_next(integer)'::regprocedure);
  v_pairs := array[
    array[$s$'manual',coalesce(u.basis='manual',false),$s$,
          $s$'manual',coalesce(u.basis='manual',false),'rendered_before',(exists (select 1 from pipeline.coverage_course_pages q where q.course_id=u.course_id and q.fetched_via='firecrawl') or exists (select 1 from pipeline.page_link_repairs x where x.course_id=u.course_id and x.reason like 'university adapter: international view read%')),$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;

alter table pipeline.provider_credit_fees add column if not exists evidence_id uuid;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_provider_credit_fee(text,jsonb)'::regprocedure) is distinct from '7901e9c15c8765900aae552217cd3321' then
    raise exception 'admin_provider_credit_fee changed, not patching'; end if;
  v_def := pg_get_functiondef('public.admin_provider_credit_fee(text,jsonb)'::regprocedure);
  v_pairs := array[
    array[$s$v_res jsonb$s$, $s$v_res jsonb{sc} v_ev uuid$s$],
    array[$s$if v_src is null then raise exception 'attach the rate page as a central page first so it is read with evidence'$s$,
          $s$if v_src is null then
      select pg.evidence_id into v_ev from pipeline.coverage_course_pages pg
       where pg.provider_id = v_pid and pg.read_status = 'read' and pg.evidence_id is not null and pg.candidates->>'final_url' = btrim(p_args->>'source_url') limit 1{sc}
    end if{sc}
    if v_src is null and v_ev is null then raise exception 'attach the rate page as a central page first, or give a course page read in the international view, so it is read with evidence'$s$],
    array[$s$currency_code, source_url, fact_source_id, reason, set_by)$s$, $s$currency_code, source_url, fact_source_id, evidence_id, reason, set_by)$s$],
    array[$s$btrim(p_args->>'source_url'), v_src, v_reason, auth.uid())$s$, $s$btrim(p_args->>'source_url'), v_src, v_ev, v_reason, auth.uid())$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], replace(v_pair[2], '{sc}', chr(59)));
  end loop;
  execute v_def;
end $p$;

do $p$
declare v_def text; v_pair text[]; v_pairs text[][];
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.provider_credit_fee_apply_v1(uuid)'::regprocedure) is distinct from '774517e0d4bd3be6874888a363be3051' then
    raise exception 'provider_credit_fee_apply_v1 changed, not patching'; end if;
  v_def := pg_get_functiondef('security.provider_credit_fee_apply_v1(uuid)'::regprocedure);
  v_pairs := array[
    array[$s$select s.evidence_id into v_ev from pipeline.provider_fact_sources s where s.id = r.fact_source_id$s$,
          $s$v_ev := coalesce(r.evidence_id, (select s.evidence_id from pipeline.provider_fact_sources s where s.id = r.fact_source_id))$s$]];
  foreach v_pair slice 1 in array v_pairs loop
    if (length(v_def) - length(replace(v_def, v_pair[1], ''))) / length(v_pair[1]) <> 1 then raise exception 'snippet not found exactly once: %', v_pair[1]; end if;
    v_def := replace(v_def, v_pair[1], v_pair[2]);
  end loop;
  execute v_def;
end $p$;
