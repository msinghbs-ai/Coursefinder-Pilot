-- CF-247 worker v1.0.1: Layer 4 drain verdict rules (Platform Admin 15 Nov 2026 07:53, after the read-only diagnostic of v1.0.0 on live).
-- The v1.0.0 rules (20261115003000) counted a page check failure as a page that is gone: 1,270 of 1,302 "page gone" verdicts were
-- official_course_url reviews, whose failed check (page_refused, identity_mismatch, identity_refused) is the very reason a person was asked to
-- choose the course's page. With layer4.drain_on 1 they would have gone back to Layer 2 unanswered, and 210 of them would have been read again
-- for nothing. New rules, in order:
--   1. A newer item for the same field: superseded (unchanged).
--   2. The course page answers 404 or 410: page gone. A 5xx is gone only when it is still a 5xx after this job has asked for a read again
--      (the page's own status, attempts at least 1); before that it is read again, within layer4.drain_max_attempts like any read again.
--   3. The page exists but is refused, blocked or not this course (403 and the other refusals, page_refused, not_course_page, identity_mismatch,
--      identity_refused, refused_host, robots_disallowed): needs a person. Reading it again would not change the check.
--   4. A page not read since the item came: read again, then a dead letter (unchanged).
--   5. Otherwise: needs a person (unchanged).
--   Then official_course_url joins the reviews with their own trigger: always left for a person, never returned or read again.
-- The verdict is worked out by one function (security.layer4_drain_judge_v1), used by the job and once here to re-judge the verdicts already
-- recorded, so the next report shows the new rules at once. Only pipeline.layer4_drain_state rows are rewritten (verdict, action, detail, and
-- next_at for a row that is now a read again); no Layer 4 item, course page or setting is touched.
-- Lock rule (#1149): no ALTER of any table; nothing written to pipeline.platform_toolset_settings. layer4.drain_on is not changed (post-check).
-- Unchanged: every route switch, aer.v2_shadow_on, the OpenRouter Observe/Stop mode, every budget ceiling and cap, every paused queue.
-- G1: no new job (layer4-drain keeps its catalogue row and command). G2: no new value; ages, attempts and cooldowns stay settings; the HTTP
-- statuses and page check names are what the reads record, not limits. G3: no consumer API object is read or changed.
-- Replaces: security.layer4_drain_tick_v1(int) (same name and signature; md5-guarded against the v1.0.0 text).
-- Retires: nothing.

set local lock_timeout = '3s';

do $g$
begin
  if md5(pg_get_functiondef('security.layer4_drain_tick_v1(int)'::regprocedure)) <> 'cdf381a84be0d3b5d12437d4c4f96835' then
    raise exception 'live security.layer4_drain_tick_v1(int) differs from the v1.0.0 definition this change replaces (md5 %)',
      md5(pg_get_functiondef('security.layer4_drain_tick_v1(int)'::regprocedure));
  end if;
end $g$;

select set_config('cf247.l4_drain_on_before', security.pipeline_num_v1('layer4.drain_on', 0)::text, false);

-- 1. One verdict function
create or replace function security.layer4_drain_judge_v1(p_item_id uuid, p_attempts int) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v_max int := security.pipeline_num_v1('layer4.drain_max_attempts', 3)::int;
        v_own_trigger text[] := array['course_description_first_read', 'course_entry_first_read', 'entry_matrix_first_run', 'entry_matrix_change',
                                      'no_page_first_run', 'conjoint_rule_first_run', 'provider_description',
                                      'official_course_url'];  -- fixed: reviews a person decides (own trigger; v1.0.1: the course's own page is a person's choice)
        v_refused text[] := array['page_refused', 'not_course_page', 'identity_mismatch', 'identity_refused', 'blocked', 'refused_host',
                                  'robots_disallowed'];  -- fixed: page check results that a read again cannot change
        r record; v_page record; v_att int := coalesce(p_attempts, 0);
        v_verdict text; v_action text; v_detail jsonb := null; v_dead boolean := false;
begin
  select i.id, i.entity_type, i.entity_id, i.field_code, i.created_at into r from pipeline.layer4_review_items i where i.id = p_item_id;
  if r.id is null then return null; end if;
  select c.read_status, c.http_status, c.read_at into v_page from pipeline.coverage_course_pages c
   where r.entity_type = 'course' and c.course_id = r.entity_id;
  if exists (select 1 from pipeline.layer4_review_items j where j.entity_type = r.entity_type and j.entity_id = r.entity_id
              and j.field_code is not distinct from r.field_code and j.created_at > r.created_at and j.status in ('pending', 'approved', 'edited_approved')) then
    v_verdict := 'superseded_by_newer'; v_action := 'mark superseded';
  elsif r.entity_type = 'course' and v_page.read_status is not null
        and (v_page.http_status in (404, 410) or (v_page.http_status >= 500 and v_att >= 1)) then  -- fixed: HTTP gone; a 5xx still there after this job's read again
    v_verdict := 'page_gone'; v_action := 'return to Layer 2';
    v_detail := jsonb_build_object('read_status', v_page.read_status, 'http_status', v_page.http_status);
  elsif r.entity_type = 'course' and v_page.read_status is not null and v_page.http_status >= 500 then  -- fixed: HTTP server error
    if v_att >= v_max then v_verdict := 'dead_letter'; v_action := 'none: reads again used up'; v_dead := true;
    else v_verdict := 'read_again'; v_action := 'read the course page again (server error)'; end if;
    v_detail := jsonb_build_object('read_status', v_page.read_status, 'http_status', v_page.http_status);
  elsif r.entity_type = 'course' and v_page.read_status is not null
        and (v_page.read_status = any (v_refused) or v_page.http_status in (401, 403, 406, 429)) then  -- fixed: HTTP refusals (the page exists)
    v_verdict := 'needs_person'; v_action := 'none: the page exists but is refused or is not this course';
    v_detail := jsonb_build_object('page_check', v_page.read_status, 'http_status', v_page.http_status);
  elsif r.entity_type = 'course' and v_page.read_status is not null and (v_page.read_at is null or v_page.read_at < r.created_at) then
    if v_att >= v_max then v_verdict := 'dead_letter'; v_action := 'none: reads again used up'; v_dead := true;
    else v_verdict := 'read_again'; v_action := 'read the course page again'; end if;
  else
    v_verdict := 'needs_person'; v_action := 'none: the page was read again and the item still waits for a person';
  end if;
  if r.field_code = any (v_own_trigger) or r.field_code ilike 'entry%' or r.field_code ilike 'aer%' then
    if v_verdict <> 'needs_person' then v_detail := coalesce(v_detail, '{}'::jsonb) || jsonb_build_object('would', v_verdict); end if;
    v_verdict := 'left_for_person'; v_action := 'none: this review is decided by a person'; v_dead := false;
  end if;
  return jsonb_build_object('verdict', v_verdict, 'action', v_action, 'detail', v_detail, 'dead_letter', v_dead);
end $function$;
comment on function security.layer4_drain_judge_v1(uuid, int) is 'CF-247 worker v1.0.1: the verdict job layer4-drain records for one pending Layer 4 item, given how many reads again it has asked for. Page gone only for 404/410, or a 5xx still there after a read again; a refused, blocked or wrong page needs a person; official_course_url and the reviews with their own trigger are left for a person. Reads only.';
revoke all on function security.layer4_drain_judge_v1(uuid, int) from public, anon, authenticated;

-- 2. The job uses it (acting is unchanged and still only when layer4.drain_on is 1)
create or replace function security.layer4_drain_tick_v1(p_limit int) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare v_on boolean := security.pipeline_num_v1('layer4.drain_on', 0) = 1;
        v_age int := security.pipeline_num_v1('layer4.drain_min_age_days', 7)::int;
        v_hours int := security.pipeline_num_v1('layer4.drain_cooldown_hours', 24)::int;
        r record; j jsonb; v_verdict text; v_action text; v_applied boolean; v_attempts int; v_next timestamptz; v_dead timestamptz; v_detail jsonb;
        v_out jsonb := '{}'::jsonb;
begin
  for r in
    select i.id, d.attempts d_attempts
      from pipeline.layer4_review_items i
      left join pipeline.layer4_drain_state d on d.item_id = i.id
     where i.status = 'pending' and i.created_at < now() - make_interval(days => v_age)
       and (d.item_id is null or (d.next_at <= now() and d.dead_letter_at is null))
     order by i.created_at
     limit greatest(1, coalesce(p_limit, 1))
  loop
    v_applied := false; v_attempts := coalesce(r.d_attempts, 0);
    j := security.layer4_drain_judge_v1(r.id, v_attempts);
    v_verdict := j->>'verdict'; v_action := j->>'action'; v_detail := case when jsonb_typeof(j->'detail') = 'object' then j->'detail' end;
    v_dead := case when (j->>'dead_letter')::boolean then now() end;
    v_next := now() + make_interval(hours => v_hours);
    if v_on then
      begin
        if v_verdict = 'superseded_by_newer' then
          update pipeline.layer4_review_items set status = 'superseded', decided_at = now() where id = r.id and status = 'pending';
          v_applied := found;
        elsif v_verdict = 'page_gone' then
          update pipeline.layer4_review_items set status = 'returned_layer2', decided_at = now() where id = r.id and status = 'pending';
          v_applied := found;
        elsif v_verdict = 'read_again' then
          update pipeline.coverage_course_pages c set next_read_at = now()
            from pipeline.layer4_review_items i
           where i.id = r.id and c.course_id = i.entity_id and (c.leased_until is null or c.leased_until < now());
          v_applied := found;
          if v_applied then v_attempts := v_attempts + 1; v_next := now() + make_interval(hours => v_hours * power(2, v_attempts - 1)::int); end if;
        end if;
      exception when others then
        v_applied := false; v_detail := coalesce(v_detail, '{}'::jsonb) || jsonb_build_object('error', left(sqlerrm, 200));
      end;
    end if;
    insert into pipeline.layer4_drain_state as s (item_id, verdict, action, applied, attempts, first_at, last_at, next_at, dead_letter_at, detail)
    values (r.id, v_verdict, v_action, v_applied, v_attempts, now(), now(), v_next, v_dead, v_detail)
    on conflict (item_id) do update set verdict = excluded.verdict, action = excluded.action, applied = excluded.applied, attempts = excluded.attempts,
      last_at = excluded.last_at, next_at = excluded.next_at, dead_letter_at = coalesce(s.dead_letter_at, excluded.dead_letter_at), detail = excluded.detail;
    v_out := jsonb_set(v_out, array[v_verdict], to_jsonb(coalesce((v_out->>v_verdict)::int, 0) + 1));
  end loop;
  return jsonb_build_object('acting', v_on, 'verdicts', v_out);
end $function$;
comment on function security.layer4_drain_tick_v1(int) is 'CF-247 worker v1.0.1: job layer4-drain. Looks at up to p_limit pending Layer 4 items older than layer4.drain_min_age_days and records the verdict of security.layer4_drain_judge_v1 in pipeline.layer4_drain_state; acts on it (superseded, returned to Layer 2, read again with an exponential cooldown, then a dead letter) only when layer4.drain_on is 1. Never changes an item a person decides (official_course_url and the reviews with their own trigger).';
revoke all on function security.layer4_drain_tick_v1(int) from public, anon, authenticated;

-- 3. Re-judge the verdicts already recorded (records only: nothing was acted on, applied is 0 on live)
update pipeline.layer4_drain_state s
   set verdict = j->>'verdict', action = j->>'action',
       detail = case when jsonb_typeof(j->'detail') = 'object' then j->'detail' end,
       dead_letter_at = case when (j->>'dead_letter')::boolean then coalesce(s.dead_letter_at, now()) end,
       last_at = now()
  from (select d.item_id, security.layer4_drain_judge_v1(d.item_id, d.attempts) j
          from pipeline.layer4_drain_state d
          join pipeline.layer4_review_items i on i.id = d.item_id and i.status = 'pending'
         where not d.applied and d.dead_letter_at is null) z
 where s.item_id = z.item_id and z.j is not null;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.layer4_drain_judge_v1', 'Layer 4', 'Layer 4', 'Verdict of job layer4-drain for one pending Layer 4 item', 'active', '{}', '20261115080000')
on conflict do nothing;

-- 4. Post-checks: nothing acts, nothing a person decides is returned or read again
do $c$
begin
  if security.pipeline_num_v1('layer4.drain_on', 0) <> current_setting('cf247.l4_drain_on_before')::numeric then raise exception 'post-check: layer4.drain_on is not changed'; end if;
  if exists (select 1 from pipeline.layer4_drain_state s join pipeline.layer4_review_items i on i.id = s.item_id and i.status = 'pending'
              where i.field_code = 'official_course_url' and s.verdict <> 'left_for_person') then
    raise exception 'post-check: official_course_url reviews are left for a person';
  end if;
  if exists (select 1 from pipeline.layer4_drain_state s join pipeline.layer4_review_items i on i.id = s.item_id and i.status = 'pending'
               join pipeline.coverage_course_pages c on i.entity_type = 'course' and c.course_id = i.entity_id
              where s.verdict = 'page_gone' and not s.applied and not (c.http_status in (404, 410) or c.http_status >= 500)) then  -- fixed: HTTP gone
    raise exception 'post-check: page gone only for a page that answers 404, 410 or a lasting 5xx';
  end if;
end $c$;
