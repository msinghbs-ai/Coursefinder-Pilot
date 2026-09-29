-- CF-247 Layer 3: OpenRouter refused every call from 29 Sep 2026 15:37 UTC with "Key limit exceeded (weekly limit)".
-- The account still has credit (about US$19.69); the API key itself carries a weekly spending cap set in OpenRouter.
-- Every refused page was sent to Layer 4 as if the model had failed on it (427 intake and English items), and the
-- health check did not flag it. This migration:
--  1. pauses the Layer 3 routes that call OpenRouter (intake, English, tuition dispatch) until the key works again; the
--     cascade ladders stay configured (route mode ladder) so they resume as ladders;
--  2. supersedes the 427 Layer 4 items created only by the key refusal, fails their work items with a note and releases
--     the pages so they are claimed again (the retry allowance is not used up);
--  3. adds a health check: 5 or more provider refusals (HTTP 401/402/403/429) in 30 minutes is critical, with the
--     provider's message, so a key or billing problem shows on Platform health straight away.
select cron.alter_job(jobid, active => false) from cron.job where jobname in ('layer3-intake-route','layer3-english-route','layer3-tuition-dispatch');
update pipeline.layer3_route_budget set route_mode='ladder' where task_class in ('provider_intake_validation','provider_english_validation');
insert into pipeline.layer3_route_events(kind,detail) values ('routes_paused_key_limit',jsonb_build_object('reason','OpenRouter: Key limit exceeded (weekly limit)','first_refusal','2026-09-29 15:37 UTC','resume','raise or remove the key''s weekly limit in OpenRouter, then re-activate the three route jobs'));

with bad as (
  update pipeline.layer4_review_items l set status='superseded', decided_at=now(), escalation_reason='Superseded: raised only because the OpenRouter key weekly limit refused the call (29 Sep 2026); the page is retried automatically.'
   where l.status='pending' and l.layer3_state::text like '%Key limit exceeded%'
  returning l.id)
select count(*) from bad;

with w as (
  update pipeline.layer3_work_items set status='failed', updated_at=now(),
         last_error='released: OpenRouter key weekly limit refused the call (29 Sep 2026); the page will be retried'
   where last_error like '%Key limit exceeded%' and status='layer4_required'
  returning id)
update pipeline.layer3_fact_handoffs h set work_item_id=null from w where h.work_item_id=w.id;

do $patch$
declare v text; a text; b text;
begin
  if (select md5(prosrc) from pg_proc where oid='security.platform_health_check_v1(boolean)'::regprocedure)<>'0e4cae185ffd51247a34f41853624fae' then
    raise exception 'platform_health_check_v1 changed since review; not replaced'; end if;
  v:=pg_get_functiondef('security.platform_health_check_v1(boolean)'::regprocedure);
  a:=$o$      select o.remaining_usd into v_num from pipeline.layer3_openrouter_observations o where o.kind='credits' and o.remaining_usd is not null order by o.observed_at desc limit 1;$o$;
  b:=$n$      select count(*) into v_num from pipeline.layer3_interpretations i
       where i.created_at>=now()-interval '30 minutes' and i.validator_result::text ~ 'provider_(401|402|403|429)';
      if v_num>=5 then
        v_found:=v_found||security.platform_health_issue_v1('budgets:openrouter_refusing','critical','Layer 3',
          'OpenRouter is refusing Layer 3 calls ('||v_num||' in 30 minutes): '||coalesce((select left(i.validator_result->'errors'->>0,160)
             from pipeline.layer3_interpretations i where i.created_at>=now()-interval '30 minutes' and i.validator_result::text ~ 'provider_(401|402|403|429)' order by i.created_at desc limit 1),'see the Layer 3 work queue')||'. Check the OpenRouter key and billing.',
          jsonb_build_object('refusals_30m',v_num));
      end if;
      select o.remaining_usd into v_num from pipeline.layer3_openrouter_observations o where o.kind='credits' and o.remaining_usd is not null order by o.observed_at desc limit 1;$n$;
  if (length(v)-length(replace(v,a,'')))/length(a)<>1 then raise exception 'credit anchor not found exactly once'; end if;
  execute replace(v,a,b);
end $patch$;
