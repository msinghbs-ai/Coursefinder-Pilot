-- CF-247 F-SCH: the Scholarship Catalogue (admin UI, Scholarships) shows the verified detail fields and filters on them (Platform Admin 12 Nov 2026
-- 20:44: "hold on to API release but continue with data fill and make the column and filter available in ui to see results"). Admin read only:
-- security.admin_scholarships_page (operation scholarships_page of public.admin_read). The consumer API is untouched (G3; Pilot #1077 stays held).
-- New row fields: award_type, sponsor, programme, award_code, application_method, application_rolling, benefit_count, benefits_label,
-- award_duration, nationality_status (restricted | unrestricted | under_review | unknown, the R24 rule of the held API change), detail_read (a
-- version 3 extraction is held), has_description. New filters (p_args): award_type, nationality_status, application_method, has_description,
-- has_benefits, has_sponsor, has_close_date, detail_read. New sorts: award_type, sponsor, nationality, method.
-- Replaces: security.admin_scholarships_page(jsonb) (same name and signature; md5-guarded edits). Retires: nothing.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.admin_scholarships_page(jsonb)', 'a27526afafe6d7fbc501224024e0f26f', array[
  -- (a) the detail facts, read once for every scholarship
  array[$o$    mapped as (select m.scholarship_id, count(*)::int n from scholarship.course_mappings m where m.mapping_state = 'mapped' group by 1),$o$,
        $n$    mapped as (select m.scholarship_id, count(*)::int n from scholarship.course_mappings m where m.mapping_state = 'mapped' group by 1),
    -- 20261113130000: verified detail facts (F-SCH detail fill)
    cvb as (select cv.scholarship_id, count(*) filter (where cv.notes like 'sch-extract-v3:%')::int benefit_count,
                   (array_agg(jsonb_build_object('value', cv.duration_value, 'unit', cv.duration_unit) order by cv.id desc) filter (where cv.coverage_type = 'award_duration' and cv.duration_unit is not null))[1] award_duration
              from scholarship.coverage cv group by 1),
    win as (select distinct on (w.scholarship_id) w.scholarship_id, w.application_method from scholarship.application_windows w where w.application_method is not null order by w.scholarship_id, w.created_at desc),
    natc as (select cr.scholarship_id, bool_or(jsonb_array_length(coalesce(cr.value_json->'excluded', '[]')) > 0 or jsonb_array_length(coalesce(cr.value_json->'regions', '[]')) > 0) excl_or_regions
               from scholarship.criteria cr where cr.criterion_type = 'nationality' and coalesce(cr.status, 'active') not in ('rejected', 'superseded', 'withdrawn') group by 1),
    l4n as (select distinct li.entity_id from pipeline.layer4_review_items li where li.status = 'pending' and li.field_code in ('nationalities', 'nationality', 'citizenship_eligibility')),
    v3r as materialized (select distinct x.scholarship_id from pipeline.scholarship_ai_extractions x where x.prompt_version >= 3 and x.error is null and x.scholarship_id is not null),$n$],
  -- (b) the row fields
  array[$o$        s.evidence_id,coalesce(mp.n,0) mapped_course_count$o$,
        $n$        s.evidence_id,coalesce(mp.n,0) mapped_course_count,
        ad.award_type, ad.sponsor, ad.programme, ad.award_code, ad.application_rolling, wn.application_method,
        coalesce(cb.benefit_count, 0) benefit_count, cb.award_duration,
        case when l4.entity_id is not null then 'under_review'
             when cardinality(coalesce(nr.codes, '{}'::text[])) > 0 or coalesce(nc.excl_or_regions, false) then 'restricted'
             when coalesce(nr.phrases ? 'ANY', false) then 'unrestricted' else 'unknown' end nationality_status,
        (v3.scholarship_id is not null) detail_read, length(coalesce(s.description, '')) >= 80 has_description$n$],
  -- (c) the joins
  array[$o$      left join mapped mp on mp.scholarship_id=s.id$o$,
        $n$      left join mapped mp on mp.scholarship_id=s.id
      left join scholarship.award_details ad on ad.scholarship_id = s.id
      left join cvb cb on cb.scholarship_id = s.id
      left join win wn on wn.scholarship_id = s.id
      left join natc nc on nc.scholarship_id = s.id
      left join scholarship.nationality_readings nr on nr.scholarship_id = s.id
      left join l4n l4 on l4.entity_id = s.id
      left join v3r v3 on v3.scholarship_id = s.id$n$],
  -- (d) the filters
  array[$o$        and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')$o$,
        $n$        and (nullif(p_args->>'audience','') is null or s.audience::text=p_args->>'audience')
        and (nullif(p_args->>'award_type','') is null or coalesce(ad.award_type, 'not_held') = p_args->>'award_type')
        and (nullif(p_args->>'application_method','') is null or coalesce(wn.application_method, 'not_held') = p_args->>'application_method')
        and (nullif(p_args->>'nationality_status','') is null or (case when l4.entity_id is not null then 'under_review'
             when cardinality(coalesce(nr.codes, '{}'::text[])) > 0 or coalesce(nc.excl_or_regions, false) then 'restricted'
             when coalesce(nr.phrases ? 'ANY', false) then 'unrestricted' else 'unknown' end) = p_args->>'nationality_status')
        and (nullif(p_args->>'has_description','') is null or (length(coalesce(s.description, '')) >= 80) = (p_args->>'has_description')::boolean)
        and (nullif(p_args->>'has_benefits','') is null or (coalesce(cb.benefit_count, 0) > 0) = (p_args->>'has_benefits')::boolean)
        and (nullif(p_args->>'has_sponsor','') is null or (ad.sponsor is not null) = (p_args->>'has_sponsor')::boolean)
        and (nullif(p_args->>'has_close_date','') is null or (s.application_close_date is not null) = (p_args->>'has_close_date')::boolean)
        and (nullif(p_args->>'detail_read','') is null or (v3.scholarship_id is not null) = (p_args->>'detail_read')::boolean)$n$],
  -- (e) the sorts
  array[$o$        lower(name),id
      limit v_limit offset v_offset) q$o$,
        $n$        case when v_sort='award_type' and v_dir='asc' then coalesce(award_type,'zz') end asc,
        case when v_sort='award_type' and v_dir='desc' then coalesce(award_type,'') end desc,
        case when v_sort='sponsor' and v_dir='asc' then lower(coalesce(sponsor,'zz')) end asc,
        case when v_sort='sponsor' and v_dir='desc' then lower(coalesce(sponsor,'')) end desc,
        case when v_sort='nationality' and v_dir='asc' then nationality_status end asc,
        case when v_sort='nationality' and v_dir='desc' then nationality_status end desc,
        case when v_sort='method' and v_dir='asc' then coalesce(application_method,'zz') end asc,
        case when v_sort='method' and v_dir='desc' then coalesce(application_method,'') end desc,
        lower(name),id
      limit v_limit offset v_offset) q$n$],
  -- (f) a readable list of benefits for the rows on the page
  array[$o$        'description_excerpt',$o$,
        $n$        'benefits_label',(select string_agg(replace(cv.coverage_type,'_',' ') || case when cv.percentage is not null then ' ' || trim(to_char(cv.percentage,'FM990.##')) || '%'
                                                     when cv.amount is not null then ' ' || coalesce(cv.currency_code || ' ', '') || trim(to_char(cv.amount,'FM999,999,999')) else '' end, ', ' order by cv.id)
                           from scholarship.coverage cv where cv.scholarship_id = o.id and cv.notes like 'sch-extract-v3:%'),
        'description_excerpt',$n$]
], array[1, 1, 1, 1, 1, 1]);
