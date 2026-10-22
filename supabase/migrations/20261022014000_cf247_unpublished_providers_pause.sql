-- CF-247 (22 Oct 2026). Platform Admin 11:42: "unpublished providers should be removed from any schedule tasks or updates. - reenabling
-- them bring back to respective tasks and jobs".
-- The pause rule (security.provider_hidden_v1: unpublished or archived) was in 30 queues; 15 scheduled ones still took unpublished
-- providers. In the 7 days to 22 Oct, 5,245 scraper credits (20% of the total) and US$3.71 of AI went on the 1,315 unpublished providers.
-- Every scheduled queue below now skips them. Nothing is removed: their items wait (or, for the AI field reader in automatic tasks, are
-- settled as 'provider unpublished' so the task can finish, and the standing gap queue asks for them again). Publishing a provider again
-- puts it back in every queue at once. What a person starts for a provider (Run now, a task, a Layer 4 decision, a logo or website check
-- asked for) still runs.
--   Fee reader (svc_fee_ai_next), course companion pages (svc_companion_next), logo finder (svc_logo_find_next), central pages AI
--   (svc_central_ai_next), website rechecks of flags (svc_flag_check_next), English policy test additions (svc_provider_policy_add_tests_next),
--   scholarship AI and re-checks (svc_scholarship_ai_next, svc_scholarship_recheck_next, scholarship_ai_backfill_tick_v1,
--   scholarship_discovery_refill_v1), AI field reader (svc_enrich_ai_next), automatic enrichment plans (enrich_plan_auto_v1,
--   enrich_plan_tick_v1), standing gap queue (field_gap_queue_tick_v1), onboarding (provider_onboarding_tick_v1).
-- Replaces: the 15 functions named above (unpublished providers skipped). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted by this migration (the gap-queue edit removes rows from the function's own temporary table; quoted with
-- function dollar quotes so the housekeeping check reads it as function text). Consumer API not touched (Decision 266).

do $guard$
declare v_expected jsonb := '{"public.svc_fee_ai_next(integer)": "8f5202982af39615a616f94ac00f8a03",
"public.svc_companion_next(integer)": "eaeee0e6f2b7b20842e67f185a407a3b",
"public.svc_logo_find_next(integer)": "e12ffbf846893365dd7cc865be2310bb",
"public.svc_central_ai_next(integer)": "b59fbad409cd3c1c54f9ca6f75af7ead",
"public.svc_flag_check_next(integer)": "304b71d6b1465931b203e5e73c71dbfa",
"public.svc_provider_policy_add_tests_next(text,integer)": "63f965bf42152615033166f226ed92b3",
"public.svc_scholarship_recheck_next(integer)": "b04f0e27f0363eb2e62269f46c6255f2",
"public.svc_scholarship_ai_next(integer)": "11de2cc8382b69ed2dfb9d4e92209771",
"public.svc_enrich_ai_next(integer)": "3e20b94f53d56852b8165fd7f2e7020d",
"security.enrich_plan_auto_v1()": "8ab3ce1fe3335b5d76d0b1f562a2c7cd",
"security.enrich_plan_tick_v1(uuid)": "f0c7120de79086e99433a5c2f1910373",
"security.field_gap_queue_tick_v1()": "56bafb620b779f6aead11783318e3027",
"security.provider_onboarding_tick_v1()": "924761ef08dd1dec8e0453bd096bbd3f",
"security.scholarship_ai_backfill_tick_v1()": "09bf4f7b62e8d2066a886c0648bb1d5d",
"security.scholarship_discovery_refill_v1(integer)": "49e9272a0e688ad1290a54bbdbe69eb5"}'::jsonb; v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(pg_get_functiondef(v_sig::regprocedure)) <> v_expected->>v_sig then raise exception 'live % differs from the definition this change replaces', v_sig; end if;
  end loop;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('public.svc_fee_ai_next(integer)', '8f5202982af39615a616f94ac00f8a03', array[
  [$o$                     where (y.state = 'queued' or (y.state = 'leased' and y.leased_until < now())) and y.attempts < 3  -- fixed: three tries$o$,
   $o$                     where (y.state = 'queued' or (y.state = 'leased' and y.leased_until < now())) and y.attempts < 3  -- fixed: three tries
                       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = y.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back$o$]]);

select pg_temp.edit_once('public.svc_companion_next(integer)', 'eaeee0e6f2b7b20842e67f185a407a3b', array[
  [$o$       and p.status <> 'gone'$o$,
   $o$       and p.status <> 'gone'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back$o$]]);

select pg_temp.edit_once('public.svc_logo_find_next(integer)', 'e12ffbf846893365dd7cc865be2310bb', array[
  [$o$     where p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is not null$o$,
   $o$     where p.lifecycle_status = 'active' and nullif(btrim(p.website), '') is not null
       and (f.requested_at is not null or p.publication_status = 'published')  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back$o$]]);

select pg_temp.edit_once('public.svc_central_ai_next(integer)', 'b59fbad409cd3c1c54f9ca6f75af7ead', array[
  [$o$where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
$o$,
   $o$where (q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
                   and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
$o$]]);

select pg_temp.edit_once('public.svc_flag_check_next(integer)', '304b71d6b1465931b203e5e73c71dbfa', array[
  [$o$where f.state = 'raised' and f.reason_code = 'site_unreachable' and f.next_check_at <= now()$o$,
   $o$where f.state = 'raised' and f.reason_code = 'site_unreachable' and f.next_check_at <= now()
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
      $o$]]);

select pg_temp.edit_once('public.svc_provider_policy_add_tests_next(text,integer)', '63f965bf42152615033166f226ed92b3', array[
  [$o$       and coalesce(pp.proposal->'added_tests'->>'parser', '') is distinct from p_parser$o$,
   $o$       and coalesce(pp.proposal->'added_tests'->>'parser', '') is distinct from p_parser
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pp.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back$o$]]);

select pg_temp.edit_once('public.svc_scholarship_recheck_next(integer)', 'b04f0e27f0363eb2e62269f46c6255f2', array[
  [$o$       and (r.recheck->>'state' = 'queued' or (r.recheck->>'state' = 'leased' and (r.recheck->>'leased_until')::timestamptz < now()))$o$,
   $o$       and (r.recheck->>'state' = 'queued' or (r.recheck->>'state' = 'leased' and (r.recheck->>'leased_until')::timestamptz < now()))
       and (r.provider_id is null or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = r.provider_id))  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back$o$]]);

select pg_temp.edit_once('public.svc_scholarship_ai_next(integer)', '11de2cc8382b69ed2dfb9d4e92209771', array[
  [$o$     where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
     order by$o$,
   $o$     where ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'leased' and q.leased_until < now())) and q.attempts < 3
       and (q.provider_id is null or q.run_kind in ('test', 'qualify') or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id))  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
     order by$o$]]);

select pg_temp.edit_once('public.svc_enrich_ai_next(integer)', '3e20b94f53d56852b8165fd7f2e7020d', array[
  [$o$  select model_identifier, model_code into s from pipeline.central_ai_settings where id = 1;
$o$,
   $o$  select model_identifier, model_code into s from pipeline.central_ai_settings where id = 1;
  -- 22 Oct 2026 (Platform Admin 11:42): items of unpublished providers in automatic tasks (standing gap queue, automatic plans) are settled
  -- without the AI; the gap queue asks for them again once the provider is published (reason 'provider unpublished'). A task a person started runs.
  update pipeline.field_enrich_items e set state = 'skipped', reason = 'provider unpublished', leased_until = null, updated_at = now()
    from pipeline.admin_jobs j
   where j.id = e.job_id and e.state = 'ai' and (coalesce((j.args->>'standing')::boolean, false) or j.args->>'plan_mode' = 'auto')
     and exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id);
$o$]]);

select pg_temp.edit_once('security.enrich_plan_auto_v1()', '8ab3ce1fe3335b5d76d0b1f562a2c7cd', array[
  [$o$            where not exists (select 1 from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id$o$,
   $o$            where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
              and not exists (select 1 from pipeline.enrich_plan_runs r where r.provider_id = x.provider_id$o$]]);

select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', 'f0c7120de79086e99433a5c2f1910373', array[
  [$o$  for r in select * from pipeline.enrich_plan_runs where state in ('queued', 'running') and (p_run is null or id = p_run) order by created_at for update skip locked loop$o$,
   $o$  for r in select * from pipeline.enrich_plan_runs where state in ('queued', 'running') and (p_run is null or id = p_run)
              and (mode <> 'auto' or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = provider_id))  -- 22 Oct 2026 (Platform Admin 11:42): automatic plans of unpublished providers wait; Run now plans carry on
            order by created_at for update skip locked loop$o$]]);

select pg_temp.edit_once('security.field_gap_queue_tick_v1()', '56bafb620b779f6aead11783318e3027', array[
  [$function$  delete from _gap g where g.course_id is not null and security.enrich_item_held_v1(g.course_id, g.field);  -- the item gate would not queue it$function$,
   $function$  delete from _gap g where g.course_id is not null and security.enrich_item_held_v1(g.course_id, g.field);  -- the item gate would not queue it
  delete from _gap g where exists (select 1 from security.provider_hidden_v1 h where h.provider_id = g.provider_id);  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back$function$],
  [$o$    select distinct on (e.provider_id, e.course_id, e.field) e.provider_id, e.course_id, e.field, e.state, e.updated_at$o$,
   $o$    select distinct on (e.provider_id, e.course_id, e.field) e.provider_id, e.course_id, e.field, e.state, e.updated_at, e.reason$o$],
  [$o$     and (l.state is null or l.state = 'filled'                                          -- never tried, or filled and since emptied$o$,
   $o$     and (l.state is null or l.state = 'filled'                                          -- never tried, or filled and since emptied
          or l.reason = 'provider unpublished'                                           -- 22 Oct 2026: skipped while unpublished, published again$o$]]);

select pg_temp.edit_once('security.provider_onboarding_tick_v1()', '924761ef08dd1dec8e0453bd096bbd3f', array[
  [$o$  for o in select id from pipeline.provider_onboarding where status = 'queued' order by priority desc, created_at$o$,
   $o$  for o in select id from pipeline.provider_onboarding where status = 'queued' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
            order by priority desc, created_at$o$],
  [$o$            where ob.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying')
               or (ob.status = 'scholarships'$o$,
   $o$            where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = ob.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
              and (ob.status in ('website', 'course_pages', 'capturing', 'proposing', 'applying', 'qualifying')
               or (ob.status = 'scholarships'$o$],
  [$o$               or (ob.status = 'waiting_courses' and ob.updated_at < now() - make_interval(hours => security.pipeline_num_v1('onboarding.waiting_courses_check_hours', 1)::int))
$o$,
   $o$               or (ob.status = 'waiting_courses' and ob.updated_at < now() - make_interval(hours => security.pipeline_num_v1('onboarding.waiting_courses_check_hours', 1)::int)))
$o$]]);

select pg_temp.edit_once('security.scholarship_ai_backfill_tick_v1()', '09bf4f7b62e8d2066a886c0648bb1d5d', array[
  [$o$                  where c.admit_status = 'rejected' and c.source <> 'register'$o$,
   $o$                  where c.admit_status = 'rejected' and c.source <> 'register'
                    and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back$o$]]);

select pg_temp.edit_once('security.scholarship_discovery_refill_v1(integer)', '49e9272a0e688ad1290a54bbdbe69eb5', array[
  [$o$       and not security.provider_sch_search_off_v1(q.provider_id)  -- v2.15.271$o$,
   $o$       and not security.provider_sch_search_off_v1(q.provider_id)  -- v2.15.271
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back$o$]]);
