-- CF-247 S1-CourseLink-2027-CRICOS s894 (Platform Admin 21 Nov 2026 07:35 AEDT): two tuning fixes to rule course_link_year_rollover_v1 (s891).
-- What was read live (21 Nov 2026 07:40-07:50 AEDT, rolled-back dry run, head 20261120235000):
--   All 158 held items tried: 39 admitted (5 at a newer year, 34 at the held address), 119 not proved. 4 of 15 worker calls failed, at least one at the
--   120-second call limit with 15 items in the call. Of the 119, 60 have a stored copy of the held address read with the exact CRICOS code (cricos_code;
--   39 read directly, 21 through Firecrawl earlier), which a plain read today cannot see (pages drawn by script, La Trobe and Melbourne among them).
--   The Platform Admin keeps the old-year fallback (a held address proved by the exact CRICOS code and no "discontinued / no longer offered" words).
-- What this change does:
--   1 Setting link_rollover.items_per_call 15 -> 8 (Platform Admin 07:35), so one call stays inside the 120-second limit.
--   2 When no live read proves the course, the worker reads the stored copy already bound to the held address ($0: the evidence store, no fetch) and admits the
--     held address if that copy proves this course by the platform's identity rule (the exact CRICOS code in Australia) and carries none of the
--     link_rollover.page_markers words. The claim gives the worker that copy: security.link_rollover_claim_v2 (v1 returns fewer columns; it stays unused and
--     is marked retiring). security.link_rollover_tick_v1 calls v2; security.link_rollover_record_v1 names the source in the reason and the decision
--     (md5-guarded edits).
--   3 The 119 items not proved are due again at once (their check time is moved back), so the next runs try them with the stored copy.
-- Not changed: the consumer API (G3 75 functions and 48 relations, read before and after), the manual locks (7,585, checked before and after), the jobs (no new
-- job; 137 active), the rule's other checks (locked, refused before, own host, archived handbook). Nothing dropped or deleted. $0.
-- Numbering: spec s894; migration 20261121093000. First issued as 20261121080000, a version S1-ELR-Central-Policy applied first (#1443, s895-s896): the file was
-- never applied under that version, so it is issued again above the live head 20261121090000 (s900). Deploy on merge refused the duplicate and ran nothing.
-- Replaces: security.link_rollover_claim_v1 (by security.link_rollover_claim_v2 in the tick).
-- Retires: security.link_rollover_claim_v1 (component register: retiring, replaced_by security.link_rollover_claim_v2, retire_after 5 Dec 2026).
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'guard: the manual locks are not 7,585 before this change'; end if;
  if md5(pg_get_functiondef('security.link_rollover_record_v1(jsonb,text)'::regprocedure)) <> '268b27dbf8a73ffffd15ba9aa2cbf0e6' then
    raise exception 'pre-check: security.link_rollover_record_v1 changed since it was read';
  end if;
  if md5(pg_get_functiondef('security.link_rollover_claim_v1(integer)'::regprocedure)) <> '09ed30fe1960f5ecc5d3c4afb550e502' then
    raise exception 'pre-check: security.link_rollover_claim_v1 changed since it was read';
  end if;
  if security.pipeline_num_v1('link_rollover.items_per_call', 15) <> 15 then raise exception 'pre-check: link_rollover.items_per_call is not 15'; end if;
end $g$;

-- 1 items per worker call 15 -> 8 ------------------------------------------------------------------------------------------------------------------
update pipeline.platform_toolset_settings
   set value = '8'::jsonb, reason = 'CF-247 s894, Platform Admin 21 Nov 2026 07:35: 15 to 8 so one call stays inside the 120-second call limit'
 where toolset_key = 'pipeline' and key = 'link_rollover.items_per_call';

-- 2 the claim gives the stored copy bound to the held address ----------------------------------------------------------------------------------------
create or replace function security.link_rollover_claim_v2(p_limit integer)
returns table (item_id uuid, course_id uuid, provider_id uuid, url text, code text, title text, country text, stored_path text, stored_sha text)
language sql stable security definer set search_path to '' as $f$
  select r.id, r.entity_id, c.provider_id, u.url, btrim(c.course_code), coalesce(nullif(btrim(c.display_title), ''), c.canonical_title), security.coverage_country(c.provider_id),
         s.storage_path, s.content_hash
    from pipeline.layer4_review_items r
    join catalogue.courses c on c.id = r.entity_id and c.lifecycle_status = 'active'
    cross join lateral (select btrim(coalesce(security.layer4_item_page_v1(r.field_code, r.proposed_value, r.layer2_state), '')) url) u
    left join lateral (select ea.storage_path, ea.content_hash
                         from pipeline.coverage_course_pages p join pipeline.evidence_artifacts ea on ea.id = p.evidence_id
                        where p.course_id = r.entity_id and p.read_status = 'read' and lower(p.url) = lower(u.url) and nullif(ea.storage_path, '') is not null
                        limit 1) s on true
   where r.status = 'pending' and r.entity_type = 'course' and r.field_code = 'official_course_url'
     and r.escalation_reason like 'The page we show carries the year%'
     and u.url ~* '^https://' and nullif(btrim(c.course_code), '') is not null
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.entity_id and l.field in ('official_url', 'course_url'))
     and not exists (select 1 from pipeline.link_rollover_checks k where k.item_id = r.id
                      and (k.outcome = 'sent' or k.checked_at > now() - make_interval(days => security.pipeline_num_v1('link_rollover.retry_days', 7)::int)))
   order by r.created_at, r.id
   limit greatest(0, least(coalesce(p_limit, 0), 400))  -- fixed: upper bound of the setting's range
$f$;
revoke all on function security.link_rollover_claim_v2(integer) from public, anon, authenticated;
comment on function security.link_rollover_claim_v2(integer) is 'CF-247 s894: the held Course link items rule course_link_year_rollover_v1 tries next, with the stored copy already bound to the held address (storage path and hash) for the worker''s stored-copy proof; reads only. Replaces security.link_rollover_claim_v1.';
comment on function security.link_rollover_claim_v1(integer) is 'CF-247 s891, retiring (s894): replaced by security.link_rollover_claim_v2, which also gives the stored copy of the held address. Not called.';

do $e$
declare v_def text := pg_get_functiondef('security.link_rollover_tick_v1()'::regprocedure);
        v_old constant text := 'from security.link_rollover_claim_v1(v_batch) c;';
        v_new constant text := 'from security.link_rollover_claim_v2(v_batch) c;  -- s894: with the stored copy of the held address';
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'guard: the tick''s claim call is not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $e$;

do $r$
declare v_def text := pg_get_functiondef('security.link_rollover_record_v1(jsonb,text)'::regprocedure);
        v_old1 constant text := $q$proved this course (%s, plain read, $0).$q$;
        v_new1 constant text := $q$proved this course (%s, $0).$q$;
        v_old2 constant text := $q$coalesce(ch->>'identity', '?')), 1000);$q$;
        v_new2 constant text := $q$coalesce(ch->>'identity', '?') || case when ch->>'source' = 'stored_copy' then ', from the stored copy of the held page; no live read proved it (s894)' else ', plain read' end), 1000);$q$;
        v_old3 constant text := $q$jsonb_build_object('result', v_res, 'stored', v_rec, 'run', p_run)$q$;
        v_new3 constant text := $q$jsonb_build_object('result', v_res, 'stored', v_rec, 'run', p_run, 'source', coalesce(ch->>'source', 'live_read'))$q$;
begin
  if (length(v_def) - length(replace(v_def, v_old1, ''))) / length(v_old1) <> 1
     or (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2) <> 1
     or (length(v_def) - length(replace(v_def, v_old3, ''))) / length(v_old3) <> 1 then
    raise exception 'guard: a line to edit in security.link_rollover_record_v1 is not found exactly once';
  end if;
  execute replace(replace(replace(v_def, v_old1, v_new1), v_old2, v_new2), v_old3, v_new3);
end $r$;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('function', 'security.link_rollover_claim_v2', 'Layer 4', 'Course links', 'The held Course link items to try, with the stored copy of the held address', 'active', '{security.link_rollover_claim_v1}', '20261121080000')
on conflict do nothing;
update pipeline.component_register set status = 'retiring', replaced_by = 'security.link_rollover_claim_v2', retire_after = date '2026-12-05'
 where kind = 'function' and name = 'security.link_rollover_claim_v1';

-- 3 the items not proved are due again at once ----------------------------------------------------------------------------------------------------
update pipeline.link_rollover_checks set checked_at = now() - make_interval(days => 365)  -- fixed: due again at once
 where outcome = 'not_proved';

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'post-check: manual locks changed'; end if;
  if security.pipeline_num_v1('link_rollover.items_per_call', 15) <> 8 then raise exception 'post-check: items per call is not 8'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active jobs'; end if;
  if position('link_rollover_claim_v2' in pg_get_functiondef('security.link_rollover_tick_v1()'::regprocedure)) = 0 then raise exception 'post-check: the tick does not call v2'; end if;
end $p$;
