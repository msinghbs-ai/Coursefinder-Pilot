-- CF-247 English requirements (lane ENG, 8 Nov 2026): why does an active course have no English requirement? One read-only funnel, one cause per course.
-- Why (live, read-only, 8 Nov 2026 03:09-04:30 UTC, project fxcwkweaxjtknorudmwp):
--   * 20,749 of 35,689 lifecycle-active courses hold an active English requirement; 14,940 do not. No screen or function said why, by stage, for all of them:
--     public.admin_provider_english_status_read counts providers only up to its 1,000-row limit (1,655 providers have a missing course; 655 are not counted) and says
--     nothing about the course-page route, the courses behind an approved policy, or the courses of unpublished providers.
--   * The two routes that can give a course English are the provider's English policy (central page -> reading -> approval -> level, group or named rule) and the
--     course's own page (read by the AI from the stored copy). A course can be missing for one reason on each route. This function states both and one primary cause.
-- What:
--   1 security.english_gap_funnel_v1(): rows of (layer, cause_key, who_acts, courses, providers). Layers: 'primary' (one cause per course; counts add up to the courses
--     without English), 'rule' (the policy route) and 'page' (the course-page route). who_acts: automatic (the platform proceeds when the stated condition arrives),
--     person (a Platform Admin or curator decision), spend (needs a paid read or budget, so a recorded decision), policy (held on purpose by the approved policy),
--     source (the source states nothing; nothing to extract), not_published (the provider is not shown to students).
--   2 public.admin_english_gap_funnel(): the same for the Admin UI (Curator and above), as one JSON document.
--   Records and reads only: no row is written, no job is added, no setting is added, nothing is read from the web. The English requeue (Platform Admin decision, open)
--   is reported as a cause (central_page_refused_not_retried, english_read_failed_not_retried) and is not run.
-- Consumer API: unchanged (G3). Nothing the website or Zoho reads is touched; the functions are new and in security and public.admin_*.
-- Replaces: nothing.
-- Retires: nothing.
-- Nothing is dropped or deleted by this migration.

create or replace function security.english_gap_funnel_v1()
returns table(layer text, cause_key text, who_acts text, courses bigint, providers bigint)
language sql stable security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security' as $function$
  -- Every lifecycle-active course without an active English requirement, classified on the policy route (rule_cause) and the course-page route (page_cause), then one primary cause.
  -- Policy route: the provider's stage from security.english_policy_status_v1 (queried per stage so that no stage is cut at its row limit), and for a provider with an approved
  -- policy the plan of security.provider_english_plan_v1 for the course. Course-page route: the course's page binding and read status, and the last English item of the AI reader.
  with m as (
    select c.id course_id, c.provider_id from catalogue.courses c
     where c.lifecycle_status = 'active'
       and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active')),
  hid as (select h.provider_id from security.provider_hidden_v1 h),
  st as (select x.provider_id, x.stage
           from unnest(array['approved', 'group_proposed', 'rule_proposed', 'rejected', 'page_read_no_rule', 'page_not_stored', 'weak_candidates_only', 'mapped_no_page', 'not_mapped']) s(stage),
                lateral security.english_policy_status_v1(null, s.stage, 1000) x),  -- fixed: the status read's own display cap, applied per stage
  pl as (
    select distinct on (z.course_id) z.course_id, z.outcome, z.reason
      from (select x.course_id, x.outcome, x.reason
              from pipeline.provider_policy_proposals p, lateral security.provider_english_plan_v1(p.id) x
             where p.kind = 'english_policy' and p.status = 'approved') z
     order by z.course_id, (z.outcome = 'write') desc, (z.outcome <> 'held') desc),
  refused as (
    select distinct fs.provider_id from pipeline.provider_fact_sources fs
     where fs.kind = 'english_policy' and fs.status = 'failed' and security.provider_fact_refusal_v1(fs.parse_summary->>'error')),
  pg as (select g.course_id, g.status, g.read_status, (g.evidence_id is not null) stored from pipeline.coverage_course_pages g),
  li as (select distinct on (i.course_id) i.course_id, i.state from pipeline.field_enrich_items i where i.field = 'english' order by i.course_id, i.updated_at desc),
  cov as (select a.course_id, a.state from pipeline.course_attribute_coverage a where a.attribute = 'english'),
  j as (
    select m.course_id, m.provider_id, (h.provider_id is not null) hidden, st.stage, pl.outcome, pl.reason, (r.provider_id is not null) refused,
           pg.status pstatus, pg.read_status, pg.stored, li.state lstate, cov.state cstate
      from m left join hid h on h.provider_id = m.provider_id left join st on st.provider_id = m.provider_id left join pl on pl.course_id = m.course_id
           left join refused r on r.provider_id = m.provider_id left join pg on pg.course_id = m.course_id left join li on li.course_id = m.course_id
           left join cov on cov.course_id = m.course_id),
  k as (
    select j.*,
      case when j.hidden then 'provider_not_published'
           when j.stage = 'group_proposed' then 'faculty_table_awaiting_person'
           when j.stage = 'rule_proposed' then 'policy_reading_awaiting_person'
           when j.stage = 'approved' and j.outcome = 'write' then 'default_ready_to_apply'
           when j.stage = 'approved' and j.outcome = 'other_value' then 'default_blocked_by_withdrawn_reading'
           when j.stage = 'approved' and j.outcome = 'differs' then 'withdrawn_reading_differs_from_default'
           when j.stage = 'approved' and j.outcome = 'set_by_hand' then 'manual_lock'
           when j.stage = 'approved' and j.outcome = 'in_review' then 'in_layer4_review'
           when j.stage = 'approved' and j.outcome = 'waiting' then 'course_page_waiting'
           when j.stage = 'approved' and j.outcome = 'held' then 'policy_held:' || case
                when j.reason like 'level not covered%' then 'level_not_covered'
                when j.reason like 'the policy gives no default%' then 'no_default_for_level'
                when j.reason like 'research degree%' then 'research_degree'
                when j.reason like 'named in the policy%' then 'named_in_policy'
                when j.reason like 'double degree%' then 'double_degree'
                when j.reason like 'exit award%' then 'exit_award'
                when j.reason like 'study level unknown%' then 'level_unknown'
                else 'other' end
           when j.stage = 'approved' then 'policy_no_plan_row'
           when j.stage = 'rejected' then 'policy_rejected'
           when j.stage = 'page_read_no_rule' then 'central_page_read_no_values'
           when j.stage = 'page_not_stored' and j.refused then 'central_page_refused_not_retried'
           when j.stage = 'page_not_stored' then 'central_page_not_stored'
           when j.stage = 'weak_candidates_only' then 'central_candidates_weak'
           when j.stage = 'mapped_no_page' then 'central_site_mapped_no_page'
           when j.stage = 'not_mapped' then 'central_site_not_mapped'
           else 'rule_unclassified' end rule_cause,
      case when j.lstate = 'failed' then 'english_read_failed_not_retried'
           when j.pstatus = 'mismatch' then 'page_for_another_course'
           when j.pstatus = 'ambiguous' then 'page_identity_ambiguous'
           when j.pstatus = 'bound' and j.read_status = 'read' and j.stored then 'page_read_no_english_stated'
           when j.pstatus is not null and j.read_status is distinct from 'read' then 'page_unreadable:' || coalesce(j.read_status, 'not_read')
           when j.pstatus is not null then 'page_read_not_stored'
           when j.cstate = 'no_website' then 'no_website'
           else 'no_course_page' end page_cause
      from j),
  p as (
    select k.*,
      -- the primary cause: what a person or the platform can act on first, then what the policy holds, then what the page says
      case when k.rule_cause = 'provider_not_published' then k.rule_cause
           when k.rule_cause in ('faculty_table_awaiting_person', 'policy_reading_awaiting_person', 'default_ready_to_apply', 'default_blocked_by_withdrawn_reading', 'withdrawn_reading_differs_from_default', 'manual_lock', 'in_layer4_review', 'course_page_waiting') then k.rule_cause
           when k.page_cause = 'english_read_failed_not_retried' then k.page_cause
           when k.rule_cause = 'central_page_refused_not_retried' then k.rule_cause
           when k.rule_cause like 'policy_held:%' then k.rule_cause
           when k.page_cause in ('page_for_another_course', 'page_identity_ambiguous') or k.page_cause like 'page_unreadable:%' or k.page_cause = 'page_read_not_stored' then k.page_cause
           when k.page_cause = 'page_read_no_english_stated' then k.page_cause
           when k.rule_cause in ('central_page_read_no_values', 'central_page_not_stored', 'central_candidates_weak', 'central_site_mapped_no_page', 'central_site_not_mapped', 'policy_rejected', 'policy_no_plan_row') then k.rule_cause
           else k.page_cause end primary_cause
      from k),
  u as (
    select 'primary'::text layer, p.primary_cause cause_key, count(*) courses, count(distinct p.provider_id) providers from p group by 2
    union all select 'rule', p.rule_cause, count(*), count(distinct p.provider_id) from p group by 2
    union all select 'page', p.page_cause, count(*), count(distinct p.provider_id) from p group by 2)
  select u.layer, u.cause_key,
         case when u.cause_key = 'provider_not_published' then 'not_published'
              when u.cause_key in ('faculty_table_awaiting_person', 'policy_reading_awaiting_person', 'default_blocked_by_withdrawn_reading', 'manual_lock', 'in_layer4_review', 'policy_rejected', 'policy_no_plan_row', 'rule_unclassified', 'withdrawn_reading_differs_from_default') then 'person'
              when u.cause_key in ('default_ready_to_apply', 'course_page_waiting', 'central_page_not_stored', 'central_candidates_weak', 'central_site_not_mapped', 'central_site_mapped_no_page', 'no_course_page', 'page_unreadable:not_read', 'page_read_not_stored') then 'automatic'
              when u.cause_key in ('central_page_refused_not_retried', 'english_read_failed_not_retried', 'page_unreadable:fetch_failed', 'page_unreadable:needs_render', 'page_unreadable:blocked') then 'spend'
              when u.cause_key like 'policy_held:%' then 'policy'
              when u.cause_key in ('central_page_read_no_values', 'page_read_no_english_stated', 'no_website', 'page_unreadable:robots_disallowed', 'page_unreadable:too_thin') then 'source'
              when u.cause_key in ('page_for_another_course', 'page_identity_ambiguous') then 'person'
              else 'person' end,
         u.courses, u.providers
    from u
$function$;
revoke all on function security.english_gap_funnel_v1() from public, anon, authenticated;
comment on function security.english_gap_funnel_v1() is 'CF-247 ENG 8 Nov 2026: why an active course has no English requirement; layers primary (one cause per course), rule (policy route) and page (course-page route). Read-only.';

create or replace function public.admin_english_gap_funnel()
returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare v_active bigint; v_with bigint;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  select count(*) into v_active from catalogue.courses c where c.lifecycle_status = 'active';
  select count(distinct r.course_id) into v_with from catalogue.course_english_requirements r join catalogue.courses c on c.id = r.course_id and c.lifecycle_status = 'active' where r.status = 'active';
  return jsonb_build_object('at', now(), 'active_courses', v_active, 'with_english', v_with, 'without_english', v_active - v_with,
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('layer', f.layer, 'cause', f.cause_key, 'who_acts', f.who_acts, 'courses', f.courses, 'providers', f.providers)
                                       order by f.layer, f.courses desc), '[]'::jsonb) from security.english_gap_funnel_v1() f));
end $function$;
revoke all on function public.admin_english_gap_funnel() from public, anon;
grant execute on function public.admin_english_gap_funnel() to authenticated;
comment on function public.admin_english_gap_funnel() is 'CF-247 ENG 8 Nov 2026: the English gap funnel for Settings and Layer 2/3 Operations (Curator and above). Read-only.';
