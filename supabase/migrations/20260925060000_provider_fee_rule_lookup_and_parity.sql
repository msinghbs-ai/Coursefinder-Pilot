-- Package 2d: provider fee rules reach the AI the same way in the benchmark and production.
-- 1. provider_fee_rule_for_evidence_service: the approved rule (if any) for an Evidence page,
--    used by the benchmark to stamp its real cases exactly as production does.
-- 2. Production parity: the rule also stamps targets already marked with the rule's basis
--    (e.g. indicative_annual) on matching pages, not only "needs validation" targets, so the
--    AI always receives the rule explanation.
create or replace function public.provider_fee_rule_for_evidence_service(p_evidence_id uuid)
returns jsonb language sql stable security definer
set search_path to 'pg_catalog','pipeline'
as $function$
  select jsonb_build_object('rule_code',pf.rule_code,'resolved_basis',pf.resolved_basis)
  from pipeline.evidence_artifacts e
  join pipeline.provider_fee_profiles pf on pf.active and pf.review_by>=current_date and e.source_url ~* pf.page_url_pattern
  where e.id=p_evidence_id
  order by pf.approved_at desc limit 1
$function$;
revoke all on function public.provider_fee_rule_for_evidence_service(uuid) from public, anon, authenticated;
grant execute on function public.provider_fee_rule_for_evidence_service(uuid) to service_role;

do $mig$
declare d text;
  a text := $q$      and w.candidate_context->'provider_current_tuition'->>'basis'='annual_or_indicative_requires_validation'$q$;
  b text := $q$      and w.candidate_context->'provider_current_tuition'->>'basis' in ('annual_or_indicative_requires_validation', pf.resolved_basis)$q$;
begin
  d := pg_get_functiondef('security.apply_provider_fee_profiles_v1()'::regprocedure);
  if strpos(d,b)>0 then return; end if;
  if (length(d)-length(replace(d,a,'')))/length(a) <> 1 then raise exception 'apply anchor not found exactly once'; end if;
  execute replace(d,a,b);
end $mig$;
