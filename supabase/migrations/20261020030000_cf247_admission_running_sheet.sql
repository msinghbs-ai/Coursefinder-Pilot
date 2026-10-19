-- CF-247 (20 Oct 2026). Platform Admin 07:02: "Keep an running sheet for data admission per uni in the admin repo and make it daily schedule".
-- security.admission_sheet_v1(): one row per university with active courses (the Build adapter list): country, courses, onboarding stage
-- and note, adapter state and admitted fields, courses holding each field (official page, intakes, English, page fee, scholarships, from
-- the search projection), scholarships published, flags held, Layer 4 items waiting, and the next action in plain words. A daily
-- scheduled task reads it and commits docs/data-admission/ in the admin repo (RUNNING-SHEET.md, a dated CSV and the change since the
-- previous day). Read only.
-- Replaces: nothing
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

CREATE OR REPLACE FUNCTION security.admission_sheet_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with pr as (
    select p.id, coalesce(p.display_name, p.canonical_name) name, k.iso_alpha2::text cc, nullif(p.website, '') website
      from catalogue.providers p join ref.countries k on k.id = p.country_id
     where coalesce(p.lifecycle_status, 'active') = 'active'
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)),
  docs as (
    select d.provider_id, count(*) n, count(*) filter (where d.has_link) link, count(*) filter (where d.has_intake) intake, count(*) filter (where d.has_english) english,
           count(*) filter (where d.has_provider_current_tuition) fee, count(*) filter (where d.has_scholarship) sch
      from search.course_documents d group by 1),
  ob as (select distinct on (provider_id) provider_id, status, stop_reason, note, updated_at from pipeline.provider_onboarding order by provider_id, created_at desc),
  fl as (select provider_id, array_agg(distinct reason_code order by reason_code) codes from pipeline.enrichment_flags where entity = 'provider' and state = 'raised' group by 1),
  l4 as (select coalesce(c.provider_id, s.provider_id, case when r.entity_type = 'provider' then r.entity_id end) provider_id, count(*) n
           from pipeline.layer4_review_items r left join catalogue.courses c on r.entity_type = 'course' and c.id = r.entity_id
           left join scholarship.scholarships s on r.entity_type = 'scholarship' and s.id = r.entity_id
          where r.status = 'pending' group by 1),
  sh as (select provider_id, count(*) n from pipeline.scholarship_ai_reviews where status = 'pending' group by 1),
  sp as (select provider_id, count(*) filter (where publication_status = 'published') pub from scholarship.scholarships group by 1),
  rows as (
    select pr.*, (select count(*) from catalogue.courses c where c.provider_id = pr.id and c.lifecycle_status = 'active') courses,
           u.enabled adapter_on, case when coalesce(u.admit, false) then u.admit_fields end admit_fields, b.wave, b.ready, b.review, b.not_ready,
           ob.status ob_status, ob.stop_reason, ob.note ob_note, ob.updated_at ob_at,
           coalesce(docs.link, 0) link, coalesce(docs.intake, 0) intake, coalesce(docs.english, 0) english, coalesce(docs.fee, 0) fee, coalesce(docs.sch, 0) sch_courses,
           coalesce(sp.pub, 0) sch_published, fl.codes flags, coalesce(l4.n, 0) l4_items, coalesce(sh.n, 0) held_scholarships
      from pr left join pipeline.uni_adapters u on u.provider_id = pr.id left join pipeline.adapter_builds b on b.provider_id = pr.id
      left join ob on ob.provider_id = pr.id left join docs on docs.provider_id = pr.id left join fl on fl.provider_id = pr.id
      left join l4 on l4.provider_id = pr.id left join sh on sh.provider_id = pr.id left join sp on sp.provider_id = pr.id)
  select coalesce(jsonb_agg(jsonb_build_object(
           'provider_id', r.id, 'name', r.name, 'country', r.cc, 'website', r.website, 'courses', r.courses,
           'stage', case when r.ob_status is not null and r.ob_status not in ('done', 'cancelled', 'stopped') then 'building'
                         when r.admit_fields is not null and cardinality(r.admit_fields) > 0 then 'admitting'
                         when r.adapter_on then 'adapter_testing'
                         when r.wave = 'cricos-only' then 'cricos_only'
                         when r.ob_status = 'stopped' then 'stopped_' || coalesce(r.stop_reason, 'other') else 'no_adapter' end,
           'wave', r.wave, 'admitted_fields', r.admit_fields, 'ready', r.ready, 'review', r.review, 'not_ready', r.not_ready,
           'with_page', r.link, 'with_intakes', r.intake, 'with_english', r.english, 'with_fee', r.fee, 'with_scholarship', r.sch_courses,
           'scholarships_published', r.sch_published, 'held_scholarship_pages', r.held_scholarships, 'flags', r.flags, 'layer4_items', r.l4_items,
           'onboarding', r.ob_status, 'onboarding_note', r.ob_note, 'onboarding_at', r.ob_at,
           'next', case
             when 'course_pages_not_found' = any (coalesce(r.flags, '{}')) then 'Course pages not found: check the website or add page addresses, then release the flag (Pipeline Operator)'
             when r.website is null or r.stop_reason = 'no_website' then 'Enter its website (Layer 4 › Websites to find)'
             when r.l4_items > 0 then format('Decide %s item(s) in Layer 4', r.l4_items)
             when r.held_scholarships > 0 then format('Decide %s held scholarship page(s) (Layer 4 › AI could not decide)', r.held_scholarships)
             when r.ob_status = 'stopped' and r.stop_reason = 'nothing_ready' then 'Adapter built, nothing ready: review the adapter or rebuild it'
             when r.ob_status = 'stopped' and r.stop_reason = 'too_few_pages' and r.wave = 'cricos-only' then 'None: CRICOS data only (1-4 courses)'
             when r.ob_status = 'stopped' and r.stop_reason = 'too_few_pages' then 'Too few course pages read: add page addresses (Adapter builder 2.1)'
             when r.ob_status = 'stopped' then 'Onboarding stopped (' || coalesce(r.stop_reason, '?') || '): see the university''s journey'
             when coalesce(r.ready, 0) > 0 and (r.admit_fields is null or cardinality(r.admit_fields) = 0) then 'Admit its Ready fields (Layer 2 › Build adapter)'
             when r.ob_status not in ('done', 'cancelled', 'stopped') then 'Running: ' || coalesce(r.ob_note, r.ob_status)
             else 'None: kept current by the scheduled jobs' end)
         order by r.cc, r.courses desc, r.name), '[]'::jsonb)
    from rows r
$function$;
revoke execute on function security.admission_sheet_v1() from public, anon, authenticated;
comment on function security.admission_sheet_v1() is 'CF-247 20 Oct 2026: per-university data admission running sheet (read by the daily scheduled task that writes docs/data-admission in the admin repo)';

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.admission_sheet_v1', 'Operations', 'Per-university data admission running sheet (daily, admin repo)', 'active', '20261020030000')
on conflict (kind, name) do nothing;
