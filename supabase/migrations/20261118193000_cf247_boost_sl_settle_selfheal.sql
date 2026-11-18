-- CF-247 S2 - BOOST (Platform Admin 18 Nov 2026 14:29 item 2 and the closed-loop rule of 16:10): rule l4-boost-sl-settle-v1 heals itself.
-- What was read live (16:40 AEDT): 74 of the 75 open Boost study load readings were read again at 15:12 AEDT, one minute after migration
-- 20261118171000 released them, by the previous worker instance (prompt boost-study-load-v4, batch bx-20261118T041213-47558f) before the
-- new edge function had deployed; refused again under v4, they never got a v5 reading, so the rule (which settles only on the qualified
-- prompt's reading) left them open.
-- What it changes: each run first releases the page of any open reading whose last reading used an older prompt than the qualified one, so it
-- is read again with the current prompt; a release in the same change as a worker change can no longer leave readings stuck.
-- Replaces: security.boost_study_load_settle_rule_v1 of migration 20261118183000 (same signature)
-- Retires: nothing

set local lock_timeout = '5s';

do $pre$
declare v text := md5(pg_get_functiondef('security.boost_study_load_settle_rule_v1(integer)'::regprocedure));
begin
  if v <> '13aac520803d16252d7dd5ddc6837025' then raise exception 'security.boost_study_load_settle_rule_v1 is not the definition this migration replaces (md5 %)', v; end if;
end $pre$;

create or replace function security.boost_study_load_settle_rule_v1(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare w record; v_prev text; v_res jsonb; v_reason text;
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_lim int := least(greatest(coalesce(p_limit, 0), 0), 1000);  -- fixed: upper bound of the setting's range
        v_prompt text := (select q.prompt_version from pipeline.ai_route_qualifications q where q.service_code = 'boost_extract' and q.status = 'qualified' order by q.prompt_version desc limit 1);
        v_ok int := 0; v_fail int := 0; v_wait int := 0; v_by jsonb := '{}'::jsonb; v_released int := 0;
begin
  if security.pipeline_num_v1('boost.sl_settle_on', 0) < 1 or v_lim = 0 then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:boost_sl_settle'));  -- fixed: one run at a time
  perform security.boost_study_load_review_feed_v1();  -- readings whose course gained a study load are closed as superseded first
  -- self-heal (18 Nov 2026 16:40): a page re-read with an older prompt than the qualified one (an old worker instance that served during a deploy)
  -- is released to be read again; it is never settled on that reading
  with stale as (
    select x.item_key from pipeline.boost_study_load_reviews r
      join pipeline.boost_extract_items x on x.entity_id = r.course_id and x.evidence_id is not distinct from r.evidence_id and x.lane = 'study_load'
     where r.status = 'open' and x.state in ('verified', 'rejected', 'failed')
       and not exists (select 1 from pipeline.boost_inbound_staging s where s.lane = 'study_load' and s.entity_id = r.course_id
                        and s.evidence_id is not distinct from r.evidence_id and s.prompt_version = v_prompt and s.id > r.staging_id))
  update pipeline.boost_extract_items x set state = 'released', note = 'read again: the last reading used an older prompt than ' || v_prompt
   where x.item_key in (select item_key from stale);
  get diagnostics v_released = row_count;
  select count(*) into v_wait from pipeline.boost_study_load_reviews r
   where r.status = 'open' and not exists (select 1 from pipeline.boost_inbound_staging s where s.lane = 'study_load' and s.entity_id = r.course_id
     and s.evidence_id is not distinct from r.evidence_id and s.prompt_version = v_prompt and s.id > r.staging_id);
  for w in
    select r.id, r.course_id, n.worker_status, n.answer, n.verdict, n.id staging_id
      from pipeline.boost_study_load_reviews r
      join lateral (select s.* from pipeline.boost_inbound_staging s where s.lane = 'study_load' and s.entity_id = r.course_id
                     and s.evidence_id is not distinct from r.evidence_id and s.prompt_version = v_prompt and s.id > r.staging_id order by s.id desc limit 1) n on true
     where r.status = 'open'
       and (n.worker_status = 'rejected' or (n.worker_status = 'verified' and n.answer->>'study_load' is null))
     order by r.opened_at limit v_lim
  loop
    v_reason := left(format('[rule l4-boost-sl-settle-v1] Not stated: the page was read again with %s (fee notes, EFTSL and CSP never count) and %s. Approved by Platform Admin 18 Nov 2026 14:29 item 2',
      v_prompt, case when w.worker_status = 'verified' then 'the page states no study load' else 'the page check refused the reading again (' || coalesce((select string_agg(x, '; ') from jsonb_array_elements_text(coalesce(w.verdict->'problems', '[]'::jsonb)) x), 'no finding') || ')' end), 1000);
    v_prev := current_setting('request.jwt.claim.sub', true);
    perform set_config('request.jwt.claim.sub', v_sys::text, true);
    begin
      v_res := security.layer4_boost_study_load_inbox_decide_v1(w.id::text, 'not_stated', null, v_reason);
      perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true);
      if coalesce((v_res->>'ok')::boolean, false) then v_ok := v_ok + 1; v_by := jsonb_set(v_by, array[w.worker_status], to_jsonb(coalesce((v_by->>w.worker_status)::int, 0) + 1)); else v_fail := v_fail + 1; end if;
    exception when others then perform set_config('request.jwt.claim.sub', coalesce(v_prev, ''), true); v_fail := v_fail + 1;
    end;
  end loop;
  if v_ok + v_fail + v_released > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'rule_execute', 'l4-boost-sl-settle-v1', jsonb_build_object('settled_not_stated', v_ok, 'by_reread', v_by, 'failed', v_fail, 'waiting_for_reread', v_wait, 'released_again', v_released, 'prompt', v_prompt), v_sys);
  end if;
  return jsonb_build_object('ok', true, 'settled', v_ok, 'by_reread', v_by, 'failed', v_fail, 'waiting_for_reread', v_wait, 'released_again', v_released,
                            'open', (select count(*) from pipeline.boost_study_load_reviews where status = 'open'), 'prompt', v_prompt);
end $function$;
revoke all on function security.boost_study_load_settle_rule_v1(integer) from public, anon, authenticated;
revoke all on function security.boost_study_load_settle_rule_v1(integer) from public, anon, authenticated;
comment on function security.boost_study_load_settle_rule_v1(integer) is 'CF-247 rule l4-boost-sl-settle-v1 (Platform Admin 18 Nov 2026 14:29 item 2): settles as Not stated each open Boost study load reading whose page, read again with the current prompt, still gives no admissible study load; first releases any page last read with an older prompt; through the Layer 4 Inbox decision under the system automation account.';

create temp table cf_run on commit drop as select security.boost_study_load_settle_rule_v1(security.pipeline_num_v1('batch.boost_sl_settle', 400)::int) r;

do $c$
declare v jsonb := (select r from cf_run);
begin
  if (v->>'failed')::int > 0 then raise exception 'post-check: % settlements failed: %', v->>'failed', v; end if;
  if exists (select 1 from pipeline.boost_study_load_reviews r join pipeline.boost_extract_items x on x.entity_id = r.course_id and x.evidence_id is not distinct from r.evidence_id and x.lane = 'study_load'
              where r.status = 'open' and x.state in ('verified', 'rejected', 'failed')
                and not exists (select 1 from pipeline.boost_inbound_staging s where s.lane = 'study_load' and s.entity_id = r.course_id and s.evidence_id is not distinct from r.evidence_id
                                 and s.prompt_version = (v->>'prompt') and s.id > r.staging_id)) then
    raise exception 'post-check: an open reading still rests on a reading with an older prompt';
  end if;
  raise notice 'Rule l4-boost-sl-settle-v1 self-heal run: %', v;
end $c$;
