-- CF-247 (19 Oct 2026). Platform Admin 22:47, choice "AI re-check, then finish" for the 49 universities (12,135 courses) whose onboarding
-- has waited at Admit scholarships since 12 to 18 Oct on 512 scholarship pages held for a person.
-- Found: both models of the chain (Qwen3 30B, then GPT-4.1 mini) already answered every one of the 512. They were held because a quote did
-- not prove who the scholarship is for (255) or its value (184), or the page could not be read (69), or the reply failed (4). Many are
-- not for international students at all (housing, asylum seeker and conference travel awards). Asking the same models the same question
-- again would give the same answers.
-- The re-check asks the first (cheap) model of the chain one narrow question per held page: who may apply, and the value, each with the
-- exact sentence. The worker checks each sentence is on the page and says international (or domestic) in words, as the extraction does.
-- The result is kept on the held item as a recommendation for the person ("Not for international students: do not publish", "International
-- students named: check and publish", "Could not be settled"). Nothing is published or rejected by the re-check.
-- 1 pipeline.scholarship_ai_reviews.recheck (jsonb): the re-check state and result.
-- 2 public.svc_scholarship_recheck_next / _record (service only); security.scholarship_recheck_fire_v1; job scholarship-recheck (every 2
--   minutes while held items are queued; stops itself when none are); setting batch.scholarship_recheck.
-- 3 The 512 held items of the 49 universities are queued.
-- 4 public.admin_scholarship_ai('reviews') also returns each held item's re-check (one line added, md5-guarded), shown in Scholarships >
--   AI could not decide.
-- Replaces: public.admin_scholarship_ai(text,jsonb) (re-check returned; nothing else changes)
-- Retires: nothing (the job and its functions are marked retiring once the queue is empty)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

alter table pipeline.scholarship_ai_reviews add column if not exists recheck jsonb;
comment on column pipeline.scholarship_ai_reviews.recheck is 'CF-247 19 Oct 2026: AI re-check of a held page (state queued, leased or done; who may apply and value, each with its sentence; recommendation for the person). Nothing is published or rejected by it.';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'batch.scholarship_recheck', 'Held scholarship pages re-checked per run', 'Each run of scholarship-recheck asks the first model of the scholarship chain about this many held pages.', 'number', to_jsonb(12), 1, 40, 'pages', 326, 'CF-247, Platform Admin 19 Oct 2026 22:47 "AI re-check, then finish"', 'Scholarships', 'job scholarship-recheck; coverage-sweep worker mode scholarship_recheck')
on conflict (toolset_key, key) do nothing;

CREATE OR REPLACE FUNCTION public.svc_scholarship_recheck_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_model text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select m.model_identifier into v_model from pipeline.scholarship_ai_extract_settings s join pipeline.scholarship_ai_models m on m.code = s.chain[1] where s.id = 1;
  with pick as (
    select r.id from pipeline.scholarship_ai_reviews r
     where r.status = 'pending'
       and (r.recheck->>'state' = 'queued' or (r.recheck->>'state' = 'leased' and (r.recheck->>'leased_until')::timestamptz < now()))
     order by r.id limit greatest(1, least(coalesce(p_limit, 12), 40)) for update skip locked),
  upd as (update pipeline.scholarship_ai_reviews r set recheck = r.recheck || jsonb_build_object('state', 'leased', 'leased_until', now() + interval '10 minutes',  -- fixed: lease timer
                                                                                         'tries', coalesce((r.recheck->>'tries')::int, 0) + 1)
            from pick where r.id = pick.id returning r.*)
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'url', u.url, 'storage_path', u.storage_path, 'provider_id', u.provider_id, 'reason', u.reason, 'model', v_model,
           'provider', (select coalesce(p.display_name, p.canonical_name) from catalogue.providers p where p.id = u.provider_id),
           'country', security.coverage_country(u.provider_id),
           'name', (select e.answer->>'name' from pipeline.scholarship_ai_extractions e where e.id = u.extraction_ids[array_upper(u.extraction_ids, 1)]))), '[]'::jsonb)
    into v from upd u;
  return v;
end $function$;
revoke execute on function public.svc_scholarship_recheck_next(integer) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.svc_scholarship_recheck_record(p_id bigint, p_result jsonb, p_cost numeric, p_error text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.scholarship_ai_reviews%rowtype; v_state text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into r from pipeline.scholarship_ai_reviews where id = p_id for update;
  if r.id is null then return 'missing'; end if;
  v_state := case when p_error is not null and coalesce((r.recheck->>'tries')::int, 0) < 2 then 'queued' else 'done' end;  -- fixed: two tries, then settle as not settled
  update pipeline.scholarship_ai_reviews set recheck = (r.recheck - 'leased_until') || jsonb_build_object('state', v_state, 'at', now(), 'cost_usd', coalesce((r.recheck->>'cost_usd')::numeric, 0) + coalesce(p_cost, 0))
           || case when v_state = 'done' then coalesce(p_result, '{}'::jsonb) || jsonb_build_object('error', p_error) else jsonb_build_object('last_error', p_error) end
   where id = p_id;
  return v_state;
end $function$;
revoke execute on function public.svc_scholarship_recheck_record(bigint, jsonb, numeric, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.scholarship_recheck_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not security.ai_use_allowed_v1('scholarship_ai') then return 0; end if;
  if not exists (select 1 from pipeline.scholarship_ai_reviews r where r.status = 'pending'
                  and (r.recheck->>'state' = 'queued' or (r.recheck->>'state' = 'leased' and (r.recheck->>'leased_until')::timestamptz < now()))) then return 0; end if;
  perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'scholarship_recheck', 'limit', security.pipeline_num_v1('batch.scholarship_recheck', 12)::int));
  return 1;
end $function$;
revoke execute on function security.scholarship_recheck_fire_v1() from public, anon, authenticated;

insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
 ('scholarship-recheck', 'Scholarships', 24, 'Re-check held scholarship pages', 'Every 2 minutes while held pages are queued: the first model of the scholarship chain answers who may apply and the value, each with its sentence; the result is a recommendation on the held item. Nothing is published or rejected.', 5, true)
on conflict (jobname) do nothing;
select cron.schedule('scholarship-recheck', '*/2 * * * *', $$select security.scholarship_recheck_fire_v1()$$);

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.svc_scholarship_recheck_next', 'Scholarships', 'Held scholarship pages: next to re-check', 'active', '20261019130000'),
 ('function', 'public.svc_scholarship_recheck_record', 'Scholarships', 'Held scholarship pages: re-check result', 'active', '20261019130000'),
 ('function', 'security.scholarship_recheck_fire_v1', 'Scholarships', 'Starts the re-check run while held pages are queued', 'active', '20261019130000'),
 ('job', 'scholarship-recheck', 'Scholarships', 'Re-check held scholarship pages (AI, recommendation only)', 'active', '20261019130000')
on conflict (kind, name) do nothing;

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

select pg_temp.edit_once('public.admin_scholarship_ai(text,jsonb)', 'fba8a1f36f2deb75ab92e43f9c5f2927', array[
  array['''decision'', r.decision,', '''decision'', r.decision, ''recheck'', r.recheck,']
]);

-- 3 the held items of the universities waiting at Admit scholarships
update pipeline.scholarship_ai_reviews r set recheck = jsonb_build_object('state', 'queued', 'queued_at', now(), 'scope', 'onboarding_scholarship_admit_20261019')
 where r.status = 'pending' and r.recheck is null
   and r.provider_id in (select o.provider_id from (select distinct on (provider_id) * from pipeline.provider_onboarding order by provider_id, created_at desc) o
                          where o.status = 'scholarships' and o.result->>'phase' = 'scholarship_admit');
