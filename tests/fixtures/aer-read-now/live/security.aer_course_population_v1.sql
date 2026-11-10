CREATE OR REPLACE FUNCTION security.aer_course_population_v1()
 RETURNS TABLE(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, prio bigint, title text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with s as (select coalesce(security.toolset_setting('pipeline', 'aer.schedule_lock_fields'), '[]'::jsonb) locks,
                    coalesce(security.toolset_setting('pipeline', 'aer.priority_provider_types'), '[]'::jsonb) pt,
                    -- CF-247 workstream C (Integration Controller 3 Nov 2026 18:30): followed providers, then the largest AER shortfall, first
                    coalesce((security.toolset_setting('pipeline', 'coverage.aer_reader_priority_on') #>> '{}')::boolean, false) gap_first,
                    coalesce(security.toolset_setting('pipeline', 'coverage.aer_priority_providers'), '[]'::jsonb) followed),
  pv as (select e.provider_id, e.country, coalesce(p.display_name, p.short_name, p.canonical_name) pname,
                case when s.gap_first and s.followed ? e.provider_id::text then -1000000
                     when s.gap_first and coalesce(k.shortfall, 0) > 0 then -least(k.shortfall, 999999)
                     when s.pt ? coalesce(t.code, '') then 1 else 2 end tier
           from security.aer_eligible_v1() e
           join catalogue.providers p on p.id = e.provider_id
           left join ref.provider_types t on t.id = p.provider_type_id
           left join pipeline.coverage_provider_reconciliation k on k.domain = 'aer' and k.provider_id = e.provider_id
          cross join s
          where (security.aer_schedule_country_v1(e.country)->>'on')::boolean
            and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = e.provider_id)),
  pr as (select pv.*, dense_rank() over (order by pv.tier, pv.pname, pv.provider_id) prio from pv)
  select c.id, pr.provider_id, pr.country, pr.pname, pr.tier, pr.prio, c.canonical_title
    from pr
    join catalogue.courses c on c.provider_id = pr.provider_id and c.lifecycle_status = 'active'
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
    join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
   cross join s
   where security.coverage_identity_allowed(c.provider_id, g.identity_basis, 'entry_requirements')
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and (s.locks ? l.field or l.field = 'all'))
$function$
