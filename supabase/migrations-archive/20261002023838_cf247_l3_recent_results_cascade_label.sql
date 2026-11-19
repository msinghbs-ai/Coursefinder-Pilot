-- CF-247 (Decision 221, 2 Oct 2026). Platform Admin, 12:35, with screenshots: "Again even sonet is disabled as a model
-- work queue still passed it on to sonet model why is the leaking still happening??"
-- Found: no answer has come from Claude Sonnet 4.6 for intakes or English since 30 Sep 2026 06:03 AEST, when the
-- cascade started. Every intake and English page since was answered by Qwen3 30b or Mistral Small. The "Running ·
-- claude-sonnet-4.6" rows are claims waiting for the cascade: a claim is recorded against the task's single routed
-- profile (Sonnet, from before the cascade), then relabelled with the step that actually answers. Recent results
-- showed that placeholder label.
-- This change: Recent results shows no model for a cascade claim that no step has answered yet (model_pending), and
-- returns the cascade step number. The worker change in the same release removes the latent fallback: a cascade task
-- never calls the single routed profile, and with no step switched on nothing is claimed.
-- Patch behind an md5 guard on the current source.

do $p$
declare s text; d text;
  o1 text := $o$p.code as profile_code,p.aggregator_provider,p.model_identifier,p.prompt_profile_version,$o$;
  n1 text := $n$case when pend.v then null else p.code end as profile_code,p.aggregator_provider,
          case when pend.v then null else p.model_identifier end as model_identifier,p.prompt_profile_version,
          i.cascade_tier_no,pend.v as model_pending,$n$;
  o2 text := $o$   join pipeline.layer3_model_profiles p on p.id=i.profile_id$o$;
  n2 text := $n$   join pipeline.layer3_model_profiles p on p.id=i.profile_id
   -- Decision 221: a cascade claim not yet answered by any step carries a placeholder profile, not the model used
   cross join lateral (select coalesce((select b.route_mode='ladder' from pipeline.layer3_route_budget b where b.task_class=i.task_class),false)
                         and i.cascade_tier_no is null and i.aggregator_response_model is null as v) pend$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'layer3_recent_interpretations_impl';
  if md5(s) is distinct from '9b752374045543ecd2d6c544f6f56bdf' then raise exception 'layer3_recent_interpretations_impl changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece 1 not found once'; end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'piece 2 not found once'; end if;
  execute replace(replace(d, o1, n1), o2, n2);
end $p$;
