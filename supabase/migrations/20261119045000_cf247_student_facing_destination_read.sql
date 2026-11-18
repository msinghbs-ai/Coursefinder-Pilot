-- CF-247 s712: student-facing correlated read and the admin accreditations read (S2-Build; hand-off from S1-RM-Design, Platform Admin
-- 18 Nov 2026 21:23, admin docs/platform/2026-11-18-correlated-blades-role-visibility-mockup.md: "a read-only correlated read open to every
-- StudySearch role that returns student-facing fields only (approved and published rows) ... and an admin read of provider accreditations").
--
-- What was read live (19 Nov 2026 04:20 AEDT): the Course and Provider detail cards read city figures, careers and the rule list through
-- public.admin_destination_review, which refuses anyone below Curator (rank 3), so Viewers and Counsellors see a read-gap note.
-- public.admin_course_destination_read is already open to every StudySearch role. Provider detail (public.admin_read 'provider_detail')
-- carries no accreditations, although catalogue.provider_accreditations holds 13 AMBA rows (all under_review).
--
-- What it changes (two existing functions, each an md5-guarded single edit; no new table or function; G3 untouched at 75 and 48):
--   * public.admin_destination_review: a Viewer or Counsellor (rank 1 or 2) may read kinds locality_metric, career_outcome and study_rule.
--     They get approved rows only (career outcomes and study rules also need a published edition) and student-facing fields only: the value,
--     its unit or currency, period, source link and attribution. Ids, the status the screen filters on, and locality names stay for the joins.
--     Diagnostics, evidence, applicability, edition and terms status, dataset edition and audit columns are not returned. Every other
--     kind stays Curator and above. Curator and above see exactly what they saw before.
--   * public.admin_read 'provider_detail': adds accreditations[]. Curator and above see every row with its status (so under_review rows
--     can be checked); Viewer and Counsellor see what API v3 sends (security.provider_accreditations_v3_v1: active, not expired).
-- Nothing is dropped or deleted.
-- Replaces: nothing (the Curator-only gate on the three student-facing kinds is widened in place).
-- Retires: nothing.

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

-- 1. student-facing read for Viewer and Counsellor
select pg_temp.cf_edit('public.admin_destination_review(text,text)'::regprocedure, '228efaa4e251a9e0bfab8e1081dd0618',
  $o$  if coalesce(security.current_role_rank(), 0) < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;$o$,
  $n$  if coalesce(security.current_role_rank(), 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  -- 20261119045000 (s712): Viewer and Counsellor read the student-facing figures only (approved rows of published editions)
  if coalesce(security.current_role_rank(), 0) < 3 then
    if p_kind = 'locality_metric' then
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (
        select m.id, m.locality_id, m.metric_category, m.metric_key, m.numeric_value, m.unit, m.currency_code, m.reference_period,
               m.source_url, m.attribution_text, m.status, l.name locality_name, l.country_code
          from destination.locality_metrics m join destination.localities l on l.id = m.locality_id
         where m.status = 'approved' and l.status = 'approved' order by l.country_code, l.name, m.metric_key limit v_max) x;
    elsif p_kind = 'career_outcome' then
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (
        select o.id, o.locality_id, o.occupation_scheme, o.occupation_code, o.occupation_title, o.study_area_code, o.skill_shortage_status,
               o.median_salary, o.salary_currency, o.salary_period, o.employment_rate_pct, o.employment_count, o.job_outlook_rating,
               o.outlook_horizon_years, o.reference_period, o.geography_level, o.state_code, o.source_url,
               coalesce(o.attribution_text, e.attribution_text) attribution_text, o.status,
               (select c.iso_alpha2 from ref.countries c where c.id = o.country_id) country_code,
               (select l.name from destination.localities l where l.id = o.locality_id) locality_name
          from destination.career_outcomes o join destination.editions e on e.id = o.edition_id
         where o.status = 'approved' and e.status = 'published' order by o.occupation_code limit v_max) x;
    elsif p_kind = 'study_rule' then
      select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) into v from (
        select r.id, r.rule_category, r.applicant_scope, r.visa_subclass, r.visa_name, r.title, r.summary, r.application_fee_amount,
               r.fee_currency, r.financial_capacity_annual, r.work_hours_fortnight, r.work_hours_notes, r.post_study_work_years_min,
               r.post_study_work_years_max, r.numeric_threshold, r.currency_code, r.state_code, r.effective_from, r.effective_to,
               r.evidence_date, r.source_url, r.approval_status, e.attribution_text,
               (select c.iso_alpha2 from ref.countries c where c.id = r.country_id) country_code
          from destination.study_rules r join destination.editions e on e.id = r.edition_id
         where r.approval_status = 'approved' and e.status = 'published' order by r.created_at desc limit v_max) x;
    else
      raise exception 'Curator role or above required' using errcode = '42501';
    end if;
    return jsonb_build_object('kind', p_kind, 'status', 'approved', 'audience', 'student', 'limit', v_max, 'rows', v);
  end if;$n$,
  '20261119045000 (s712)');

-- 2. accreditations on the provider detail
select pg_temp.cf_edit('public.admin_read(text,jsonb)'::regprocedure, 'b6570ab86cecb6c4d2f843538c56bd1f',
  $o$return security.admin_provider_detail(v_id)-'courses'-'courses_page'-'evidence'-'evidence_page'-'sources'-'history';$o$,
  $n$return (security.admin_provider_detail(v_id)-'courses'-'courses_page'-'evidence'-'evidence_page'-'sources'-'history')
   -- 20261119045000 (s712): accreditations; Curator and above see every row with its status, Viewer and Counsellor what API v3 sends
   ||jsonb_build_object('accreditations',case when coalesce(security.current_role_rank(),0)>=3 then
       (select coalesce(jsonb_agg(jsonb_build_object('body_code',a.body_code,'accredited_unit_name',a.accredited_unit_name,'status',a.status,
                'accredited_since',a.accredited_since,'expires_at',a.expires_at,'rating',a.rating,'rating_period',a.rating_period,
                'source_url',a.source_url,'verified_at',a.verified_at) order by a.body_code,a.accredited_unit_name nulls first,a.id),'[]'::jsonb)
          from catalogue.provider_accreditations a where a.provider_id=v_id)
     else security.provider_accreditations_v3_v1(v_id) end);$n$,
  '20261119045000 (s712): accreditations');

-- post-checks (rolled back with the dry run if any fails)
do $chk$
declare v_src text; v_drift jsonb;
begin
  v_src := (select prosrc from pg_proc where oid = 'public.admin_destination_review(text,text)'::regprocedure);
  if position('''audience'', ''student''' in v_src) = 0 or position('evidence_id' in substr(v_src, position('20261119045000' in v_src), 3000)) > 0 then
    raise exception 's712: the student-facing branch is missing or returns evidence';
  end if;
  v_src := (select prosrc from pg_proc where oid = 'public.admin_read(text,jsonb)'::regprocedure);
  if position('provider_accreditations_v3_v1' in v_src) = 0 then raise exception 's712: provider_detail does not read accreditations'; end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_typeof(v_drift) = 'array' then
    if jsonb_array_length(v_drift) > 0 then raise exception 's712: consumer API drift %', v_drift; end if;
  elsif jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 's712: consumer API drift %', v_drift->'drift';
  end if;
end $chk$;
