-- CF-247 (11 Oct 2026, Platform Admin): scholarships read through the scraper only, with the whole extraction and evidence journey
-- recorded, and no Study Australia or other national register. Platform Admin decisions of 11 Oct 2026:
--  - no direct read or fallback for scholarship pages; robots.txt is not consulted for scholarship pages; a page that cannot be
--    scraped waits and is tried again (worker coverage-sweep v0.18.0);
--  - a page that names no course, level or field is not linked to courses (the link-to-all rule of v2.15.239 is removed) and a
--    scholarship with no linked course can be published;
--  - application open and close dates (next closing round) and study start are read from the page, each with its sentence;
--  - Study Australia is removed as a comparison and as a source: scholarships that have their own provider page read and
--    name-checked are kept as provider-page records (register identifiers set inactive, source set to the provider page reader);
--    the others are set inactive (not deleted); register candidates are rejected; legacy register, ETL, AI-run, scope and
--    country-watch jobs are unscheduled; discovery candidates are read through the scraper with no daily cap (cap 60,000).
-- Course links now come from the evidence in this order: courses the page names (course code or title), English language
-- courses, the levels and fields the page states, else none; each link keeps its proof. Links made by a person are not changed.
-- md5-checked before and after. Nothing is dropped; no rows are deleted by this file (stale links are removed by the reader
-- itself as each page is read again). Removing retired job rows and settings is a separate paste file for the Platform Admin.
do $guard$
declare v_expected jsonb := '{"security.scholarship_sweep_apply_v1(uuid)": "a59a894e38f84c2058e5c1a3ff7cee81", "security.scholarship_publishability_v1()": "cf9a16265eddeef41995b10eff7fbf3b", "public.admin_scholarship_record_read(uuid)": "8e23b487daea103dd7130612c1091a4c", "public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)": "7bb4eaf48d0d35cf22f56d83dd32e58e", "security.scholarship_coverage_row_v1(uuid)": "305254eac269fbbc3ddbc3061630f8aa", "public.admin_scholarship_coverage_provider(uuid)": "ef42a176dab2248147ce6161bffefe2f", "security.scholarship_audience_read_v1()": "f69d2187172a690ee677b89a0efc642d", "security.scholarship_nationality_read_v1()": "8257992c232f72080ecf9edde1d7b9b8", "public.website_edge_scholarship_search_v1(jsonb,integer,integer)": "a97c1ab33ca8ec9b4d85570a29e78eb1", "api.website_v2_scholarship_item(uuid)": "06dd99e2d2c3a4e559afbef04b4f9f3c"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 1. Columns for the new facts (nothing removed)
alter table scholarship.scholarships add column if not exists application_open_precision text, add column if not exists application_close_precision text,
  add column if not exists study_start_label text, add column if not exists study_start_date date;
alter table scholarship.course_mappings add column if not exists proof jsonb;
comment on column scholarship.course_mappings.proof is 'Why the course is linked: kind (course_code, course_title, levels_fields, english_course), what the page named, and the sentence it was read from (CF-247, 11 Oct 2026).';
comment on column scholarship.scholarships.study_start_label is 'The intake or study start the scholarship is for, as the provider page states it (CF-247, 11 Oct 2026).';

-- 2. Publishing checks for all scholarships or a few (the record screen asks for one)
CREATE OR REPLACE FUNCTION security.scholarship_publishability_for_v1(p_ids uuid[])
 RETURNS TABLE(scholarship_id uuid, publishable boolean, missing text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'
AS $function$
  -- 11 Oct 2026: one set of publishing checks for all scholarships (p_ids null) or a few (a record screen); no register
  -- (Study Australia) exemptions; a scholarship with no linked course can be published
  select s.id,
         cardinality(m.missing)=0,
         m.missing
    from scholarship.scholarships s
    left join pipeline.scholarship_pages sp on sp.scholarship_id=s.id and sp.read_status='read'
    left join (select q.id, row_number() over (partition by q.provider_id, q.k order by q.placeholder, q.edition, q.past_year, q.ts desc, q.id::text) rn
                 from (select s0.id, s0.provider_id, security.scholarship_series_key_v1(s0.name) k,
                              0 placeholder,
                              (s0.name ~* '^\s*(\d{4}\s*[-:]|(semester|sem|trimester|term|intake)\s*\d)')::int edition,
                              (coalesce(substring(s0.name from '(20\d\d)')::int, 9999) < extract(year from now())::int)::int past_year,
                              s0.updated_at ts
                         from scholarship.scholarships s0 where s0.lifecycle_status='active'
                          and (p_ids is null or s0.provider_id in (select s1.provider_id from scholarship.scholarships s1 where s1.id = any(p_ids)))) q) ed on ed.id=s.id
    cross join lateral (select array_remove(array[
        case when s.lifecycle_status<>'active' then 'not active' end,
        case when coalesce(s.source_url,'')='' then 'no provider page' end,
        case when coalesce(s.audience,'') !~* 'international' then 'not for international students' end,
        case when sp.facts is not null and coalesce(sp.facts->>'eligibility_excerpt','') ~* '(australian citizen|permanent resident|domestic student|new zealand citizen|canadian citizen)'
                  and coalesce(sp.facts->>'eligibility_excerpt','') !~* 'international' then 'provider page limits it to citizens and residents' end,
        case when sp.facts is not null and sp.facts->>'international'='false' then 'provider page does not mention international students' end,
        case when not ((s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) or exists (select 1 from scholarship.award_tiers t where t.scholarship_id=s.id and t.tier_code like 'page_tier_%')) then 'no stated award value' end,
        case when exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type'
                                and cr.value_json->>'by'='scholarship_sweep' and cr.value_codes='{domestic}')
              and not exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type'
                                and coalesce(cr.value_json->>'by','')<>'scholarship_sweep' and 'international'=any(cr.value_codes))
             then 'eligibility lists domestic students only' end,
        case when s.evidence_id is null then 'no evidence' end,
        case when exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id=s.id and h.released_at is null) then 'held after hand-check' end,
        case when sp.facts is not null and coalesce((sp.facts->>'not_offered')::boolean,false) then 'not currently offered (provider page)' end,
        case when sp.facts ? 'english_course' and exists (select 1 from scholarship.course_mappings cm join catalogue.courses c on c.id=cm.course_id
                   left join ref.study_levels sl on sl.id=c.study_level_id where cm.scholarship_id=s.id and cm.mapping_state='mapped' and coalesce(sl.code,'')<>'non_aqf_award')
             then 'English language course linked to other courses' end,
        -- 11 Oct 2026 (Platform Admin): a scholarship not linked to a course is valid and can be published
        case when exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped')
              and not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped' and cm.mapping_basis<>'explicit_provider_scope')
              and s.name ~* '(engineer|undergrad|postgrad|research|ph\.?d|doctor|master|bachelor|honours|diploma|law|medic|nurs|business|commerce|science|arts|information tech|computing|education|design|music|health|pharm|faculty|school of|college of|mba)'
             then 'course link broader than the scholarship' end,
        -- v2.15.239 (S2): one scholarship, one record; the provider's own, evergreen, current edition is the one listed
        -- (v2.15.241: ranked once per scholarship, not compared pair by pair, so the check stays fast)
        case when ed.rn > 1 then 'another edition of this scholarship is listed' end,
        case when greatest(s.updated_at,(select e.captured_at from pipeline.evidence_artifacts e where e.id=s.evidence_id)) < now()-interval '12 months' then 'not verified in 12 months' end
      ], null) missing) m
   where p_ids is null or s.id = any(p_ids)
$function$
;
revoke all on function security.scholarship_publishability_for_v1(uuid[]) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.scholarship_sweep_apply_v1(p_scholarship_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare pg record; s record; v_codes text[]; v_fields text[]; v_old uuid[]; v_new uuid[]; v_changes text[]:='{}'; v_src uuid; f jsonb;
  v_d jsonb; v_date date; v_prec text; v_basis text; v_links jsonb; v_del uuid[]; v_add uuid[]; v_unmatched jsonb := '[]'::jsonb;
  v_managed text[] := array['sweep_level_field_scope','page_named_course','explicit_provider_scope','explicit_course_scope'];
begin
  select * into pg from pipeline.scholarship_pages where scholarship_id=p_scholarship_id;
  select * into s from scholarship.scholarships where id=p_scholarship_id for update;
  if pg.read_status is distinct from 'read' or pg.facts is null or s.id is null then return jsonb_build_object('applied',false); end if;
  f:=pg.facts; v_src:=security.coverage_sweep_source(s.provider_id);

  if not (s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) then
    if f->'value'->>'type'='percentage' and (f->'value'->>'percentage')::numeric between 5 and 100 then
      update scholarship.scholarships set award_value_type='percentage', award_percentage=(f->'value'->>'percentage')::numeric,
             award_applies_to_fee_type=coalesce(award_applies_to_fee_type,'tuition_fee'), award_value_text=coalesce(award_value_text,left(f->'value'->>'context',400)),
             evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'award_value',jsonb_build_object('type',s.award_value_type,'text',s.award_value_text),f->'value',pg.evidence_id);
      v_changes:=v_changes||'award_value'::text;
    elsif f->'value'->>'type'='fixed_amount' and (f->'value'->>'amount')::numeric > 0 then
      update scholarship.scholarships set award_value_type='fixed_amount', award_amount=(f->'value'->>'amount')::numeric, award_currency_code=scholarship.provider_currency(s.provider_id),
             award_value_text=coalesce(award_value_text,left(f->'value'->>'context',400)), evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'award_value',jsonb_build_object('type',s.award_value_type,'text',s.award_value_text),f->'value',pg.evidence_id);
      v_changes:=v_changes||'award_value'::text;
    end if;
  end if;

  -- v0.7.0 (11 Oct 2026): application open and close dates (the next closing round) and study start, from the page,
  -- each with its sentence kept in the page facts. A value entered by hand (manual lock) is left as it is.
  if f ? 'dates' then
    v_d := f->'dates'->'close';
    if v_d is not null and v_d <> 'null'::jsonb and not exists (select 1 from pipeline.manual_locks k where k.entity='scholarship' and k.entity_id=s.id and k.field='application_close_date') then
      v_date := coalesce((v_d->>'date')::date, ((v_d->>'month')||'-01')::date + interval '1 month' - interval '1 day'); v_prec := coalesce(v_d->>'precision','day');
      if s.application_close_date is distinct from v_date or s.application_close_precision is distinct from v_prec then
        update scholarship.scholarships set application_close_date=v_date, application_close_precision=v_prec, updated_at=now() where id=s.id;
        insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
        values (s.id,'application_close_date',to_jsonb(s.application_close_date),v_d,pg.evidence_id);
        v_changes:=v_changes||'application_close_date'::text;
      end if;
    end if;
    v_d := f->'dates'->'open';
    if v_d is not null and v_d <> 'null'::jsonb and not exists (select 1 from pipeline.manual_locks k where k.entity='scholarship' and k.entity_id=s.id and k.field='application_open_date') then
      v_date := coalesce((v_d->>'date')::date, ((v_d->>'month')||'-01')::date); v_prec := coalesce(v_d->>'precision','day');
      if s.application_open_date is distinct from v_date or s.application_open_precision is distinct from v_prec then
        update scholarship.scholarships set application_open_date=v_date, application_open_precision=v_prec, updated_at=now() where id=s.id;
        insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
        values (s.id,'application_open_date',to_jsonb(s.application_open_date),v_d,pg.evidence_id);
        v_changes:=v_changes||'application_open_date'::text;
      end if;
    end if;
    v_d := f->'study_start';
    if v_d is not null and v_d <> 'null'::jsonb and not exists (select 1 from pipeline.manual_locks k where k.entity='scholarship' and k.entity_id=s.id and k.field='study_start') then
      if s.study_start_label is distinct from (v_d->>'label') or s.study_start_date is distinct from (v_d->>'date')::date then
        update scholarship.scholarships set study_start_label=v_d->>'label', study_start_date=(v_d->>'date')::date, updated_at=now() where id=s.id;
        insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
        values (s.id,'study_start',jsonb_build_object('label',s.study_start_label,'date',s.study_start_date),v_d,pg.evidence_id);
        v_changes:=v_changes||'study_start'::text;
      end if;
    end if;
  elsif s.application_close_date is null and (f->'deadline'->>'date') is not null and (f->'deadline'->>'date')::date >= current_date then
    update scholarship.scholarships set application_close_date=(f->'deadline'->>'date')::date, updated_at=now() where id=s.id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'application_close_date',null,f->'deadline',pg.evidence_id);
    v_changes:=v_changes||'application_close_date'::text;
  end if;

  -- the provider page this record was read from (11 Oct 2026: no register placeholder addresses any more)
  if not exists (select 1 from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url') then
    insert into scholarship.identifiers(scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
    values (s.id,'first_party_detail_url',pg.url,v_src,pg.evidence_id,true,'active') on conflict do nothing;
    v_changes:=v_changes||'first_party_url'::text;
  end if;

  -- Decision 211: eligibility criteria and award duration from the page
  v_changes:=v_changes||security.scholarship_criteria_apply_v1(s.id);

  -- Course links from the evidence (11 Oct 2026, Platform Admin). In order:
  --  1. courses the page names (course code, or a course title matching one of the provider's own courses);
  --  2. else an English language course scholarship: the provider's English language courses;
  --  3. else the study levels and fields the page states (each link keeps the sentence they were read from);
  --  4. else none: a scholarship that names no course, level or field is not linked to courses (and can still be published).
  -- Every link carries its proof. Links made or decided by a person are never touched; search is refreshed only when links change.
  create temporary table if not exists _sch_links(course_id uuid primary key, proof jsonb) on commit drop;
  truncate _sch_links;
  if jsonb_typeof(f->'named_courses') = 'object' then
    insert into _sch_links(course_id, proof)
    select distinct on (c.id) c.id, jsonb_build_object('kind', x.kind, 'named', x.named, 'text', x.txt)
      from catalogue.courses c
      join (select 'course_code' kind, nc->>'code' named, nc->>'text' txt, null::text norm from jsonb_array_elements(coalesce(f->'named_courses'->'codes','[]')) nc
            union all
            select 'course_title', nc->>'title', nc->>'text', regexp_replace(lower(nc->>'title'), '[^a-z0-9]+', '', 'g') from jsonb_array_elements(coalesce(f->'named_courses'->'titles','[]')) nc) x
        on (x.kind = 'course_code' and upper(coalesce(c.course_code,'')) = upper(x.named))
        or (x.kind = 'course_title' and length(x.norm) >= 8 and x.norm in (regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '', 'g'), regexp_replace(lower(coalesce(c.display_title,'')), '[^a-z0-9]+', '', 'g')))
     where c.provider_id = s.provider_id and c.lifecycle_status = 'active'
     order by c.id, (x.kind = 'course_code') desc;
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_unmatched from (
      select jsonb_build_object('code', nc->>'code') x from jsonb_array_elements(coalesce(f->'named_courses'->'codes','[]')) nc
       where not exists (select 1 from catalogue.courses c where c.provider_id = s.provider_id and upper(coalesce(c.course_code,'')) = upper(nc->>'code'))
      union all
      select jsonb_build_object('title', nc->>'title') from jsonb_array_elements(coalesce(f->'named_courses'->'titles','[]')) nc
       where not exists (select 1 from catalogue.courses c where c.provider_id = s.provider_id and c.lifecycle_status = 'active'
                          and regexp_replace(lower(nc->>'title'), '[^a-z0-9]+', '', 'g') in (regexp_replace(lower(c.canonical_title), '[^a-z0-9]+', '', 'g'), regexp_replace(lower(coalesce(c.display_title,'')), '[^a-z0-9]+', '', 'g')))) z;
  end if;
  if exists (select 1 from _sch_links) then
    v_basis := 'page_named_course';
  elsif f ? 'english_course' then
    v_basis := 'sweep_level_field_scope';
    insert into _sch_links(course_id, proof)
    select c.id, jsonb_build_object('kind','english_course','named',f->'english_course'->>'course','text','English language course scholarship: linked to the provider''s English language courses')
      from catalogue.courses c join ref.study_levels sl on sl.id=c.study_level_id
     where c.provider_id=s.provider_id and c.lifecycle_status='active' and sl.code='non_aqf_award' and coalesce(c.course_code,'')<>''
       and c.canonical_title ~* case f->'english_course'->>'course'
             when 'general english' then '\mgeneral english\M'
             when 'ielts preparation' then '\mielts\M'
             when 'academic english' then '(academic english|english for academic purposes|\meap\M)'
             else '(general english|academic english|english for academic purposes|\meap\M|\mielts\M|\melicos\M|english language)' end;
  else
    v_codes:=security.scholarship_level_codes(f->'levels');
    v_fields:=array(select jsonb_array_elements_text(coalesce(f->'fields','[]')));
    if cardinality(v_codes)>0 or cardinality(v_fields)>0 then
      v_basis := 'sweep_level_field_scope';
      insert into _sch_links(course_id, proof)
      select c.id, jsonb_build_object('kind','levels_fields','levels',f->'levels','fields',f->'fields',
                     'text', concat_ws(' | ', case when cardinality(v_codes)>0 then f->>'levels_text' end, case when cardinality(v_fields)>0 then f->>'fields_text' end))
        from catalogue.courses c left join ref.study_levels sl on sl.id=c.study_level_id left join ref.fields_of_study fos on fos.id=c.primary_field_id
       where c.provider_id=s.provider_id and c.lifecycle_status='active'
         and (cardinality(v_codes)=0 or sl.code=any(v_codes))
         and (cardinality(v_fields)=0 or exists (select 1 from unnest(v_fields) fp where fos.code like fp||'%'));
    else
      v_changes:=v_changes||'no_course_named'::text;
    end if;
  end if;
  select coalesce(array_agg(m.course_id),'{}') into v_del from scholarship.course_mappings m
   where m.scholarship_id=s.id and m.mapped_by is null and m.mapping_basis=any(v_managed) and not exists (select 1 from _sch_links l where l.course_id=m.course_id);
  select coalesce(array_agg(l.course_id),'{}') into v_add from _sch_links l
   where not exists (select 1 from scholarship.course_mappings m where m.scholarship_id=s.id and m.course_id=l.course_id and m.mapping_state='mapped');
  if cardinality(v_del)>0 then
    delete from scholarship.course_mappings where scholarship_id=s.id and course_id=any(v_del) and mapped_by is null and mapping_basis=any(v_managed);
  end if;
  insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by,mapped_at,updated_at,proof)
  select s.id, l.course_id, 'mapped', v_basis, pg.evidence_id, null, now(), now(), l.proof from _sch_links l
  on conflict (scholarship_id,course_id) do update set mapping_basis=excluded.mapping_basis, mapping_state='mapped', evidence_id=excluded.evidence_id, proof=excluded.proof, updated_at=now()
   where scholarship.course_mappings.mapped_by is null and scholarship.course_mappings.mapping_basis=any(v_managed)
     and (scholarship.course_mappings.proof is distinct from excluded.proof or scholarship.course_mappings.mapping_basis is distinct from excluded.mapping_basis
          or scholarship.course_mappings.evidence_id is distinct from excluded.evidence_id or scholarship.course_mappings.mapping_state <> 'mapped');
  -- the study-level scope rows of this reader follow the page's levels
  delete from scholarship.scopes sc using pipeline.sources src where sc.source_id=src.id and src.source_type='provider_course_page_sweep' and sc.scope_type='study_level' and sc.scholarship_id=s.id
     and not (sc.study_level_id in (select sl.id from ref.study_levels sl where sl.code=any(coalesce(v_codes,'{}'))));
  if cardinality(coalesce(v_codes,'{}'))>0 then
    insert into scholarship.scopes(scholarship_id,scope_type,study_level_id,include_exclude,source_id,evidence_id)
    select s.id,'study_level',sl.id,'include',v_src,pg.evidence_id from ref.study_levels sl
     where sl.code=any(v_codes) and not exists (select 1 from scholarship.scopes x where x.scholarship_id=s.id and x.scope_type='study_level' and x.study_level_id=sl.id);
  end if;
  v_links := jsonb_build_object('basis', coalesce(v_basis,'none'), 'courses', (select count(*) from _sch_links), 'added', cardinality(v_add), 'removed', cardinality(v_del), 'named_not_matched', v_unmatched);
  if cardinality(v_add)+cardinality(v_del)>0 then
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
    values (s.id,'course_links',jsonb_build_object('removed',cardinality(v_del)),v_links,pg.evidence_id);
    v_changes:=v_changes||'course_links'::text;
    perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_add||v_del)),true);
  end if;
  update pipeline.scholarship_pages set applied_at=now(), apply_result=jsonb_build_object('changes',to_jsonb(v_changes),'links',v_links,'extractor',f->>'extractor') where scholarship_id=s.id;
  return jsonb_build_object('applied',true,'changes',to_jsonb(v_changes),'links',v_links);
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_publishability_v1()
 RETURNS TABLE(scholarship_id uuid, publishable boolean, missing text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'
AS $function$
  select * from security.scholarship_publishability_for_v1(null)
$function$;

CREATE OR REPLACE FUNCTION public.admin_scholarship_record_read(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return (
    -- 11 Oct 2026: publishing checks for this scholarship only (was every scholarship, about 3.6 s); the evidence journey added
    with pub as (select * from security.scholarship_publishability_for_v1(array[p_id]) x where x.scholarship_id = p_id),
    pg as (select * from pipeline.scholarship_pages sp where sp.scholarship_id = p_id),
    ev as (select e.* from pipeline.evidence_artifacts e where e.id = (select pg.evidence_id from pg))
    select jsonb_build_object(
      'id', s.id, 'name', s.name, 'provider_id', s.provider_id, 'provider', coalesce(pr.display_name, pr.canonical_name),
      'can_edit', v_rank >= 3,
      'status', case when s.lifecycle_status <> 'active' then 'inactive' when s.publication_status = 'published' then 'published' when coalesce((select publishable from pub), false) then 'ready' else 'held' end,
      'held_reasons', coalesce((select missing from pub), '{}'::text[]),
      'publication_status', s.publication_status, 'lifecycle_status', s.lifecycle_status,
      'value_label', scholarship.value_label(s.id), 'page_words', s.award_value_text,
      'award_amount', s.award_amount, 'award_percentage', s.award_percentage, 'award_value_type', s.award_value_type, 'is_maximum', s.award_value_is_maximum,
      'tiers', (select coalesce(jsonb_agg(jsonb_build_object('label', t.label, 'percentage', t.percentage, 'amount', t.amount, 'currency', t.currency_code) order by t.display_order), '[]'::jsonb) from scholarship.award_tiers t where t.scholarship_id = s.id),
      'audience', s.audience,
      'audience_phrase', (select coalesce(a.phrase_both, nullif(concat_ws(' + ', a.phrase_international, a.phrase_domestic), '')) from scholarship.audience_readings a where a.scholarship_id = s.id),
      'nationalities', s.nationalities,
      'nationality_phrases', (select r.phrases from scholarship.nationality_readings r where r.scholarship_id = s.id),
      'nationality_terms', (select jsonb_agg(jsonb_build_object('code', t.code, 'name', split_part(t.names, '|', 1)) order by t.region, split_part(t.names, '|', 1)) from ref.nationality_terms t),
      'duration_basis', s.award_duration_basis,
      'application_required', s.application_required, 'application_open_date', s.application_open_date, 'application_close_date', s.application_close_date,
      'application_open_precision', s.application_open_precision, 'application_close_precision', s.application_close_precision,
      'study_start_label', s.study_start_label, 'study_start_date', s.study_start_date,
      'page', s.source_url,
      'page_read_at', (select sp.read_at from pipeline.scholarship_pages sp where sp.scholarship_id = s.id),
      'courses', (select count(*) from scholarship.course_mappings m where m.scholarship_id = s.id and m.mapping_state = 'mapped'),
      'course_list', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'level', x.level, 'code', x.course_code, 'basis', x.mapping_basis, 'proof', x.proof, 'by_hand', x.mapped_by is not null) order by x.so, x.title), '[]'::jsonb)
                        from (select co.id, coalesce(co.display_title, co.canonical_title) title, sl.name level, coalesce(sl.sort_order, 99) so, co.course_code, m.mapping_basis, m.proof, m.mapped_by
                                from scholarship.course_mappings m join catalogue.courses co on co.id = m.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                               where m.scholarship_id = s.id and m.mapping_state = 'mapped' and co.lifecycle_status = 'active'
                               order by coalesce(sl.sort_order, 99), coalesce(co.display_title, co.canonical_title) limit 200) x),
      'course_levels', (select coalesce(jsonb_agg(jsonb_build_object('level', y.level, 'courses', y.n) order by y.so), '[]'::jsonb)
                          from (select coalesce(sl.name, 'Other') level, min(coalesce(sl.sort_order, 99)) so, count(*) n
                                  from scholarship.course_mappings m join catalogue.courses co on co.id = m.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                                 where m.scholarship_id = s.id and m.mapping_state = 'mapped' and co.lifecycle_status = 'active' group by 1) y),
      'criteria', (select coalesce(jsonb_agg(to_jsonb(cr) order by cr.criterion_type), '[]'::jsonb) from scholarship.criteria cr where cr.scholarship_id = s.id and cr.status = 'active'),
      -- the evidence journey: provider page, scraper read, saved copy, what was read from it and what it changed
      'evidence', (select jsonb_build_object(
          'url', pg.url, 'final_url', pg.final_url, 'found_by', pg.url_source, 'read_status', pg.read_status, 'fetched_via', pg.fetched_via,
          'http_status', pg.http_status, 'read_at', pg.read_at, 'next_read_at', pg.next_read_at, 'attempts', pg.attempts,
          'credits', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'sch_scrape' and u.url = pg.url),
          'saved', (select jsonb_build_object('evidence_id', ev.id, 'captured_at', ev.captured_at, 'version', ev.capture_version, 'hash', ev.content_hash, 'path', ev.storage_path) from ev),
          'versions', (select count(*) from pipeline.evidence_artifacts e2 where e2.evidence_group_key = 'scholarship:' || p_id),
          'extractor', pg.facts->>'extractor', 'name_check', pg.name_check,
          'facts', case when pg.facts is null then null else jsonb_build_object(
              'value', pg.facts->'value', 'dates', pg.facts->'dates', 'deadline', pg.facts->'deadline', 'study_start', pg.facts->'study_start',
              'levels', pg.facts->'levels', 'levels_text', pg.facts->'levels_text', 'fields', pg.facts->'fields', 'fields_text', pg.facts->'fields_text',
              'faculties', pg.facts->'faculties', 'named_courses', pg.facts->'named_courses', 'international', pg.facts->'international',
              'not_offered', pg.facts->'not_offered', 'page_title', pg.facts->'page_title') end,
          'applied_at', pg.applied_at, 'apply_result', pg.apply_result,
          'changes', (select coalesce(jsonb_agg(jsonb_build_object('at', c.changed_at, 'field', c.field, 'before', c.before_value, 'after', c.after_value) order by c.changed_at desc), '[]'::jsonb)
                        from (select * from pipeline.scholarship_sweep_changes c where c.scholarship_id = p_id order by c.changed_at desc limit 12) c))
        from pg),
      'locks', (select coalesce(jsonb_object_agg(k.field, k.mode), '{}'::jsonb) from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id),
      'history', (select coalesce(jsonb_agg(jsonb_build_object('at', h.at, 'field', h.field, 'action', h.action, 'reason', h.reason) order by h.at desc), '[]'::jsonb)
                    from (select * from pipeline.manual_edit_log l where l.entity = 'scholarship' and l.entity_id = s.id order by l.at desc limit 10) h))
    from scholarship.scholarships s left join catalogue.providers pr on pr.id = s.provider_id where s.id = p_id);
end $function$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_read_record(p_scholarship_id uuid, p_read_status text, p_http_status integer, p_fetched_via text, p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_ev uuid; v_src uuid; v_pid uuid; v_url text; r jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.provider_id, p.url into v_pid, v_url from scholarship.scholarships s join pipeline.scholarship_pages p on p.scholarship_id=s.id where s.id=p_scholarship_id;
  if p_storage_path is not null and p_read_status='read' then
    v_src:=security.coverage_sweep_source(v_pid);
    -- unchanged page: reuse its evidence; changed page: next capture version, superseding the previous one
    select e.id into v_ev from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id and e.content_hash=p_sha256 order by e.capture_version desc limit 1;
    if v_ev is null then
      insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key,supersedes_evidence_id)
      select p_scholarship_id, v_src, 'scholarship_page', coalesce(p_final_url,v_url), p_storage_path, p_sha256, 'application/gzip',
             jsonb_build_object('worker','coverage-sweep scholarship_read','decision','Decision 139 sweep'),
             coalesce((select max(e.capture_version) from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id),0)+1,
             'scholarship:'||p_scholarship_id,
             (select e.id from pipeline.evidence_artifacts e where e.evidence_group_key='scholarship:'||p_scholarship_id order by e.capture_version desc limit 1)
      returning id into v_ev;
    end if;
  end if;
  update pipeline.scholarship_pages set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, evidence_id=case when p_read_status='read' then coalesce(v_ev,evidence_id) else evidence_id end,
         facts=case when p_read_status='read' then coalesce(p_facts,facts) else facts end,
         name_check=case when p_facts ? 'name_check' then p_facts->'name_check' else name_check end,
         -- 11 Oct 2026: pages are read through the scraper only; one waiting for the scraper (no credit or service) is tried again
         -- within the hour and does not use up its attempts; a blocked page is tried again in 2 days
         next_read_at=case when p_read_status='read' then now()+interval '90 days' when p_read_status='name_mismatch' then now()+interval '30 days'
                           when p_read_status='blocked' then now()+interval '2 days' when p_read_status='waiting_scraper' then now()+interval '1 hour' else now()+interval '6 hours' end,
         attempts=case when p_read_status='read' then 0 when p_read_status='waiting_scraper' then greatest(attempts-1,0) else attempts end
   where scholarship_id=p_scholarship_id;
  -- an admitted page that no longer meets the admission rules is withdrawn, not applied
  if p_read_status='read' and p_facts ? 'admission' and coalesce((p_facts->'admission'->>'admit')::boolean,true) is false
     and exists (select 1 from pipeline.scholarship_pages where scholarship_id=p_scholarship_id and url_source='admitted') then
    r:=security.scholarship_admission_withdraw_v1(p_scholarship_id, jsonb_build_object('reasons',p_facts->'admission'->'reasons','extractor',p_facts->>'extractor'));
  elsif p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;
  -- a discovered page that does not name the scholarship: the match is released (logged) so another page can be tried
  if p_read_status='name_mismatch' then
    update pipeline.scholarship_page_candidates c set match_basis='rejected_name_mismatch', matched_scholarship_id=null
      from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id and sp.url_source='discovered' and c.id=sp.candidate_id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value)
    select p_scholarship_id,'provider_page_rejected',jsonb_build_object('url',sp.url,'url_source',sp.url_source),p_facts->'name_check' from pipeline.scholarship_pages sp where sp.scholarship_id=p_scholarship_id;
  end if;
  return coalesce(r,jsonb_build_object('applied',false));
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_coverage_row_v1(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with m as (select * from security.scholarship_listing_match_v1(p_provider_id)),
  recs as (select s.id, s.publication_status, s.source_url from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active'),
  lp as (select * from pipeline.scholarship_listing_pages l where l.provider_id = p_provider_id and l.active),
  chk as (select c.* from pipeline.scholarship_coverage_checks c where c.provider_id = p_provider_id),
  h as (select md5(coalesce(string_agg(lower(item_name), '|' order by lower(item_name)), '')) v from m)
  select jsonb_build_object(
    'provider_id', p.id, 'name', coalesce(p.display_name, p.canonical_name), 'country', (select k.iso_alpha2 from ref.countries k where k.id = p.country_id),
    'watch', exists (select 1 from pipeline.scholarship_watch w where w.provider_id = p.id and w.active),
    'listing_pages', (select count(*) from lp where lp.source <> 'suggested'),
    'suggested_pages', (select count(*) from lp where lp.source = 'suggested'),
    'listing_read_at', (select max(lp.read_at) from lp where lp.source <> 'suggested'),
    'listed', (select count(*) from m),
    'found', (select count(*) from m where m.scholarship_id is not null),
    'published', (select count(*) from m join recs r on r.id = m.scholarship_id where r.publication_status = 'published'),
    'missing', (select count(*) from m where m.scholarship_id is null),
    'records', (select count(*) from recs),
    'records_published', (select count(*) from recs where publication_status = 'published'),
    'extra', (select count(*) from recs r where not exists (select 1 from m where m.scholarship_id = r.id)),
    'checked_at', (select checked_at from chk), 'checked_by', (select u.email from chk join auth.users u on u.id = chk.checked_by),
    'state', case when not exists (select 1 from lp where lp.source <> 'suggested') then 'no_listing'
                  when not exists (select 1 from lp where lp.status = 'read') then 'waiting'
                  when not exists (select 1 from chk) then 'to_check'
                  when (select item_hash from chk) is distinct from (select v from h) then 'changed'
                  else 'checked' end)
  from catalogue.providers p where p.id = p_provider_id
$function$;

CREATE OR REPLACE FUNCTION public.admin_scholarship_coverage_provider(p_provider_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  return (with m as (select * from security.scholarship_listing_match_v1(p_provider_id)),
  pub as (select * from security.scholarship_publishability_v1() x where x.scholarship_id in (select s.id from scholarship.scholarships s where s.provider_id = p_provider_id)),
  rec as (
    select s.id, jsonb_build_object('id', s.id, 'name', s.name, 'status', s.publication_status, 'audience', s.audience, 'source_url', s.source_url,
      'value_type', s.award_value_type, 'percentage', s.award_percentage, 'amount', s.award_amount, 'currency', s.award_currency_code, 'value_text', s.award_value_text,
      'value_is_maximum', s.award_value_is_maximum, 'closes', s.application_close_date,
      'courses', (select count(*) from scholarship.course_mappings cm where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'),
      'levels', (select coalesce(jsonb_agg(distinct sl.name), '[]'::jsonb) from scholarship.course_mappings cm join catalogue.courses c on c.id = cm.course_id
                   join ref.study_levels sl on sl.id = c.study_level_id where cm.scholarship_id = s.id and cm.mapping_state = 'mapped'),
      'all_courses', exists (select 1 from pipeline.scholarship_pages sp where sp.scholarship_id = s.id and sp.apply_result->'changes' ? 'course_links_all'),
      'publishable', coalesce((select x.publishable from pub x where x.scholarship_id = s.id), false),
      'reasons', coalesce((select to_jsonb(x.missing) from pub x where x.scholarship_id = s.id), '[]'::jsonb),
      'held', exists (select 1 from pipeline.scholarship_publication_holds h where h.scholarship_id = s.id and h.released_at is null)) j
      from scholarship.scholarships s where s.provider_id = p_provider_id and s.lifecycle_status = 'active')
  select jsonb_build_object(
    'row', security.scholarship_coverage_row_v1(p_provider_id),
    'listing_pages', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'url', l.url, 'source', l.source, 'status', l.status, 'read_at', l.read_at, 'items', jsonb_array_length(l.items), 'error', l.error) order by (l.source = 'suggested'), l.id), '[]'::jsonb)
                        from pipeline.scholarship_listing_pages l where l.provider_id = p_provider_id and l.active),
    'listed', (select coalesce(jsonb_agg(jsonb_build_object('name', m.item_name, 'url', m.item_url, 'matched_by', m.matched_by, 'record', r.j) order by (m.scholarship_id is null) desc, m.item_name), '[]'::jsonb)
                 from m left join rec r on r.id = m.scholarship_id),
    'extra', (select coalesce(jsonb_agg(r.j order by (r.j->>'status') = 'published' desc, r.j->>'name'), '[]'::jsonb) from rec r where not exists (select 1 from m where m.scholarship_id = r.id)),
    'can_manage', v_rank >= 6));
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_audience_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security'
AS $function$
declare v_changed int := 0; v_read int := 0; v_counts jsonb;
  c_intl constant text := '\m(international students?|overseas students?|student visa|subclass 500|onshore|offshore|citizens? of (india|china|sri lanka|bangladesh|indonesia|malaysia|vietnam|nepal|pakistan|philippines|thailand|cambodia|kenya|nigeria|colombia|brazil|mexico|chile|peru|hong kong|singapore|japan|korea|taiwan|turkey|saudi|uae|iran|iraq|egypt|ghana|south africa|canada|usa|united states|uk|united kingdom|germany|france|italy|spain)|from (india|china|sri lanka|bangladesh|indonesia|malaysia|vietnam|nepal|pakistan|philippines|thailand|latin america|africa|asia|europe|the americas)|full[- ]fee[- ]paying international|global excellence|international (merit|excellence|academic))\M';
  c_dom constant text := '\m(domestic students?|australian citizens?|australian permanent residents?|permanent residen(t|cy) of australia|commonwealth supported|csp|hecs|fee[- ]help|home students?|new zealand citizens?|humanitarian visa|aboriginal|torres strait|indigenous|first nations)\M';
  c_dom_nz constant text := '\m(domestic students?|new zealand citizens?|new zealand permanent residents?|permanent residen(t|cy) of new zealand|australian citizens?|home students?|fees[- ]free|studylink|student allowance|maori|māori|pasifika)\M';
  c_dom_ca constant text := '\m(domestic students?|canadian citizens?|canadian permanent residents?|permanent residents? of canada|protected persons?|indigenous|first nations|métis|metis|inuit|osap|canada student (loans?|grants?)|residents? of (british columbia|alberta|ontario|quebec|québec|manitoba|saskatchewan|nova scotia|new brunswick))\M';
  c_both constant text := '\m(all students|domestic and international|international and domestic|regardless of (citizenship|residency|nationality)|open to all)\M';
begin
  with t as (
    select s.id, lower(coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '')) txt,
           (select k.iso_alpha2 from catalogue.providers pp join ref.countries k on k.id = pp.country_id where pp.id = s.provider_id) cc
      from scholarship.scholarships s where s.lifecycle_status = 'active'),
  r as (
    select t.id, substring(t.txt from c_intl) p_intl, substring(t.txt from case t.cc when 'NZ' then c_dom_nz when 'CA' then c_dom_ca when 'AU' then c_dom else coalesce((select '\m(' || o.domestic_terms || ')\M' from scholarship.country_onboarding o where o.country_code = t.cc and coalesce(o.domestic_terms, '') <> ''), c_dom) end) p_dom, substring(t.txt from c_both) p_both from t),
  v as (
    select r.id, case when r.p_both is not null or (r.p_intl is not null and r.p_dom is not null) then 'international_and_domestic'
                      when r.p_intl is not null then 'international' when r.p_dom is not null then 'domestic' else 'not_stated' end audience,
           r.p_intl, r.p_dom, r.p_both from r),
  up as (
    insert into scholarship.audience_readings(scholarship_id, audience, phrase_international, phrase_domestic, phrase_both, reader_version, read_at)
    select v.id, v.audience, v.p_intl, v.p_dom, v.p_both, 'scholarship-audience-v1', now() from v
    on conflict (scholarship_id) do update set audience = excluded.audience, phrase_international = excluded.phrase_international, phrase_domestic = excluded.phrase_domestic, phrase_both = excluded.phrase_both, reader_version = excluded.reader_version, read_at = now()
    returning scholarship_id)
  select count(*) into v_read from up;
  update scholarship.scholarships s set audience = a.audience, updated_at = now() from scholarship.audience_readings a where a.scholarship_id = s.id and s.lifecycle_status = 'active' and s.audience is distinct from a.audience  and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'audience');
  get diagnostics v_changed = row_count;
  select jsonb_object_agg(x.audience, x.n) into v_counts from (select a.audience, count(*) n from scholarship.audience_readings a group by 1) x;
  if v_changed > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'audience_read', 'Audience read from each scholarship''s wording', jsonb_build_object('read', v_read, 'changed', v_changed, 'counts', v_counts, 'decision', 'Decision 244'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('read', v_read, 'changed', v_changed, 'counts', v_counts);
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_nationality_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security', 'ref', 'catalogue'
AS $function$
declare v_read int := 0; v_changed int := 0; v_with int := 0;
begin
  with t as (
    select s.id, k.iso_alpha2 study_country,
           coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '') txt
      from scholarship.scholarships s left join catalogue.providers p on p.id = s.provider_id left join ref.countries k on k.id = p.country_id
     where s.lifecycle_status = 'active'
       and not exists (select 1 from scholarship.nationality_readings a where a.scholarship_id = s.id and a.reader_version = 'scholarship-nationality-v1' and a.read_at >= s.updated_at
                         and a.read_at >= coalesce((select max(c.created_at) from scholarship.criteria c where c.scholarship_id = s.id), '-infinity'::timestamptz))
     order by (select a.read_at from scholarship.nationality_readings a where a.scholarship_id = s.id) nulls first, s.id
     limit 150),
  m as (
    select t.id, x.code,
           coalesce(substring(t.txt from ('(?i)\m(?:citizens?|nationals?|passport holders?|permanent residents?|residents?|students?|applicants?|candidates?|scholars?) (?:of|from) (?:the )?(?:' || x.names || ')\M')),
                    substring(t.txt from ('(?i)\m(?:' || coalesce(nullif(x.demonyms, ''), 'ZZZZ') || ') (?:citizens?|nationals?|passport holders?|students?|applicants?|candidates?)\M')),
                    substring(t.txt from ('(?i)\m(?:' || x.names || ') (?:citizens?|nationals?|passport holders?)\M'))) phrase
      from t, ref.nationality_terms x
     where x.code <> coalesce(t.study_country, 'AU') and not (x.code = 'AU' and coalesce(t.study_country, 'AU') in ('AU', 'NZ')) and not (x.code = 'NZ' and t.study_country = 'AU')),
  r as (
    select t.id, coalesce((select array_agg(m.code order by m.code) from m where m.id = t.id and m.phrase is not null), '{}'::text[]) codes,
           coalesce((select jsonb_object_agg(m.code, m.phrase) from m where m.id = t.id and m.phrase is not null), '{}'::jsonb) phrases
      from t),
  up as (
    insert into scholarship.nationality_readings(scholarship_id, codes, phrases, reader_version, read_at)
    select r.id, r.codes, r.phrases, 'scholarship-nationality-v1', now() from r
    on conflict (scholarship_id) do update set codes = excluded.codes, phrases = excluded.phrases, reader_version = excluded.reader_version, read_at = now()
    returning scholarship_id, codes)
  select count(*), count(*) filter (where cardinality(codes) > 0) into v_read, v_with from up;
  update scholarship.scholarships s set nationalities = a.codes, updated_at = now() from scholarship.nationality_readings a where a.scholarship_id = s.id and s.lifecycle_status = 'active' and s.nationalities is distinct from a.codes  and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'nationalities');
  get diagnostics v_changed = row_count;
  if v_changed > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'nationality_read', 'Nationality read from each scholarship''s wording', jsonb_build_object('read', v_read, 'with_nationality', v_with, 'changed', v_changed, 'decision', 'Decision 246'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('read', v_read, 'with_nationality', v_with, 'changed', v_changed);
end $function$;

CREATE OR REPLACE FUNCTION public.website_edge_scholarship_search_v1(p_filters jsonb DEFAULT '{}'::jsonb, p_page integer DEFAULT 1, p_page_size integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'ref', 'security', 'api'
AS $function$
declare
  f jsonb := coalesce(p_filters,'{}'::jsonb);
  v_page int := coalesce(p_page,1);
  v_size int := coalesce(p_page_size,20);
  v_kw text := nullif(btrim(coalesce(f->>'keyword','')),'');
  v_providers text[] := api.website_text_array(f->'provider_ids');
  v_cities text[] := (select array_agg(lower(x)) from unnest(api.website_text_array(coalesce(f->'cities',f->'city'))) x);
  v_levels text[] := api.website_text_array(f->'study_level_codes');
  v_types text[] := api.website_text_array(f->'amount_types');
  v_open boolean := coalesce((f->>'open_only')::boolean,false);
  v_published boolean := coalesce((f->>'published_only')::boolean,false);
  v_groups text[] := (select array_agg(lower(regexp_replace(btrim(x),'^au_','','i'))) from unnest(api.website_text_array(coalesce(f->'university_groups',f->'university_group'))) x);
  v_not_applied text[] := '{}';
  v_result jsonb;
begin
  if v_page < 1 then raise exception 'INVALID_INPUT: page must be >= 1' using errcode='22023'; end if;
  if v_size < 1 or v_size > 50 then raise exception 'INVALID_INPUT: page_size must be 1-50' using errcode='22023'; end if;
  if api.website_text_array(f->'study_area_codes') is not null then v_not_applied := array_append(v_not_applied,'study_area_codes'); end if;
  if f ? 'min_academic_score' then v_not_applied := array_append(v_not_applied,'min_academic_score'); end if;
  if f ? 'citizenship' then v_not_applied := array_append(v_not_applied,'citizenship'); end if;

  with base as (
    select s.*, pr.stable_key provider_key, security.provider_presentable_name(coalesce(nullif(pr.display_name,''), pr.canonical_name)) provider_name,
      case when s.award_value_type='percentage' and s.award_percentage >= 100 and coalesce(s.award_applies_to_fee_type,s.award_fee_basis)='tuition_fee' then 'full_tuition'
           when s.award_value_type='percentage' and coalesce(s.award_applies_to_fee_type,s.award_fee_basis)='tuition_fee' then 'percentage_tuition'
           when s.award_value_type='percentage' then 'percentage'
           when s.award_value_type='fixed_amount' then 'fixed_amount' end as amount_type,
      case when s.application_close_date is null then 'unknown'
           when s.application_close_date < current_date then 'closed' else 'open' end as deadline_status
    from scholarship.scholarships s
    left join catalogue.providers pr on pr.id = s.provider_id
    where s.lifecycle_status = 'active'
      and not exists (select 1 from security.layer4_search_blocked_scholarships b where b.scholarship_id = s.id)
      and not exists (select 1 from security.layer4_search_blocked_providers b where b.provider_id = s.provider_id)
      and (v_kw is null or s.name ilike '%'||v_kw||'%' or pr.canonical_name ilike '%'||v_kw||'%' or pr.display_name ilike '%'||v_kw||'%'
           or exists (select 1 from scholarship.criteria c where c.scholarship_id=s.id and c.human_text ilike '%'||v_kw||'%'))
      and (v_providers is null or pr.stable_key = any(v_providers))
      and s.publication_status='published'  -- v2.15.239 (S1): published scholarships only, always
      and (v_groups is null or exists (select 1 from catalogue.provider_collection_memberships gm join ref.institution_collections gic on gic.id=gm.collection_id
            where gm.provider_id=s.provider_id and gm.status='active' and (gm.valid_to is null or gm.valid_to>=current_date)
              and gic.collection_type='university_group' and gic.status='active' and replace(gic.code,'au_','') = any(v_groups)))
      and (v_cities is null or exists (select 1 from catalogue.campuses k where k.provider_id = s.provider_id and lower(btrim(k.city)) = any(v_cities)))
      -- excluded only when a level restriction is stated and none matches
      and (v_levels is null or not exists (select 1 from scholarship.scopes sc where sc.scholarship_id=s.id and sc.study_level_id is not null and sc.include_exclude='include')
           or exists (select 1 from scholarship.scopes sc join ref.study_levels sl on sl.id=sc.study_level_id
                      where sc.scholarship_id=s.id and sc.include_exclude='include' and sl.code = any(v_levels)))
  ), filtered as (
    select * from base b
    where (not v_open or b.deadline_status <> 'closed')
      and (v_types is null or b.amount_type = any(v_types))
  ), counted as (select count(*) total from filtered),
  paged as (
    select * from filtered
    order by (deadline_status='open') desc, application_close_date nulls last, lower(name), stable_key
    limit v_size offset (v_page-1)*v_size
  )
  select jsonb_build_object(
    'contract_version','website-scholarship-search-v1',
    'total',(select total from counted),
    'page',v_page,'page_size',v_size,'sort','open_deadline_first',
    'filters_not_applied',to_jsonb(v_not_applied),
    'items',coalesce((select jsonb_agg(jsonb_build_object(
      'scholarship_id',p.stable_key,
      'reference_code',null::text, -- 11 Oct 2026: no national register codes (Study Australia retired)
      'name',p.name,
      'provider',jsonb_build_object('provider_id',p.provider_key,'name',p.provider_name,'university_groups',security.provider_university_groups(p.provider_id)),
      'campus_city',null,
      'provider_cities',coalesce((select jsonb_agg(distinct k.city order by k.city) from catalogue.campuses k where k.provider_id=p.provider_id and nullif(btrim(k.city),'') is not null),'[]'::jsonb),
      'amount_type',p.amount_type,
      'amount_value',case p.amount_type when 'fixed_amount' then p.award_amount when 'full_tuition' then 100 when 'percentage_tuition' then p.award_percentage when 'percentage' then p.award_percentage end,
      'amount_currency',case when p.amount_type='fixed_amount' then p.award_currency_code end,
      'amount_note',p.award_value_text,
      'amount_is_maximum',p.award_value_is_maximum,
      'renewable',case when p.award_duration_basis in ('annual_program_duration','program_duration') then true end,
      'coverage_duration',p.award_duration_basis,
      'study_levels',null,
      'study_area_codes',null,
      'min_academic_score',null,
      'age_min',(select c.value_number from scholarship.criteria c where c.scholarship_id=p.id and c.criterion_type='minimum_age' and c.machine_evaluable limit 1),
      'age_max',null,
      'citizenship_eligibility',null,
      'eligibility_summary',(select left(c.human_text,1200) from scholarship.criteria c where c.scholarship_id=p.id and c.criterion_type='published_eligibility_narrative' limit 1),
      'application_open_date',p.application_open_date,
      'application_deadline',p.application_close_date,
      'deadline_status',p.deadline_status,
      'deadline_is_rolling',null,
      'official_url',coalesce((select i.identifier_value from scholarship.identifiers i where i.scholarship_id=p.id and i.scheme='first_party_detail_url' order by i.is_primary desc limit 1), p.source_url),
      'official_url_source','first_party', -- 11 Oct 2026: every scholarship comes from the provider's own page
      'academic_year',p.academic_year,
      'publication_status',p.publication_status,
      'freshness',jsonb_build_object('updated_at',p.updated_at)
    ) order by (p.deadline_status='open') desc, p.application_close_date nulls last, lower(p.name), p.stable_key) from paged p),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION api.website_v2_scholarship_item(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'search', 'ref', 'security', 'api'
AS $function$
  with s as (select * from scholarship.scholarships where id = p_id and lifecycle_status = 'active' and publication_status = 'published'),  -- v2.15.239 (S1): published scholarships only, always
  p as (select pr.* from catalogue.providers pr join s on s.provider_id = pr.id),
  cr as (select c.* from scholarship.criteria c join s on c.scholarship_id = s.id where coalesce(c.status,'active') not in ('rejected','superseded','withdrawn')),
  st as (select case when bool_or('international' = any(value_codes)) and bool_or('domestic' = any(value_codes)) then 'both'
                     when bool_or('international' = any(value_codes)) then 'international'
                     when bool_or('domestic' = any(value_codes)) then 'domestic' end v from cr where criterion_type='student_type'),
  acad as (select value_number, coalesce(value_json->>'scale', value_text) scale, human_text from cr where criterion_type='academic_minimum' order by confidence desc nulls last limit 1),
  nat as (select coalesce((select codes from scholarship.nationality_readings nr join s on nr.scholarship_id=s.id),
                          (select array_agg(distinct x) from cr, unnest(cr.value_codes) x where cr.criterion_type in ('nationality','citizenship_and_residency'))) codes),
  lv as (select array_agg(distinct d.study_level_code order by d.study_level_code) levels, count(distinct m.course_id) n
         from scholarship.course_mappings m join s on m.scholarship_id=s.id join search.course_documents d on d.course_id=m.course_id where m.mapping_state='mapped'),
  areas as (select array_agg(distinct d.primary_field_code order by d.primary_field_code) codes from scholarship.course_mappings m join s on m.scholarship_id=s.id join search.course_documents d on d.course_id=m.course_id where m.mapping_state='mapped' and d.primary_field_code is not null)
  select jsonb_build_object(
    'scholarship_id', s.stable_key,
    'name', s.name,
    'official_url', s.source_url, 'official_scholarship_url', s.source_url,
    'provider', jsonb_build_object('provider_id', p.stable_key, 'name', security.provider_presentable_name(coalesce(p.display_name,p.canonical_name)),
                  'cities', (select coalesce(jsonb_agg(distinct security.place_presentable(k.city)), '[]'::jsonb) from catalogue.campuses k where k.provider_id=p.id and nullif(btrim(k.city),'') is not null),
                  'country_code', (select trim(c.iso_alpha2::text) from ref.countries c where c.id=p.country_id),
                  'logo', api.website_v2_provider_logo(p.id)),
    'university_id', p.stable_key,
    'campus_city', coalesce(security.place_presentable(p.primary_city), (select security.place_presentable(min(k.city)) from catalogue.campuses k where k.provider_id=p.id and nullif(btrim(k.city),'') is not null)),
    'scholarship_type', s.scholarship_type, 'scholarship_type_bucket', s.scholarship_type,
    'amount_value', coalesce(s.award_amount, s.award_percentage),
    'amount_type', case when s.award_value_type='fixed_amount' then 'fixed_amount'
                        when s.award_value_type='percentage' and s.award_percentage >= 100 then 'full_tuition'
                        when s.award_value_type='percentage' then 'percentage_tuition' end,
    'amount_type_detail', s.award_value_type,
    'amount_currency', s.award_currency_code,
    'amount_is_maximum', coalesce(s.award_value_is_maximum,false),
    'amount_note', s.award_value_text,
    'scholarship_percentage', s.award_percentage,
    'value_classification', case when s.award_value_type='percentage' and s.award_percentage >= 100 then 'full_tuition'
                                 when s.award_value_type='percentage' then 'partial_tuition'
                                 when s.award_value_type='fixed_amount' then 'fixed_amount' else 'not_stated' end,
    'application_open_date', s.application_open_date,
    'application_deadline', s.application_close_date, 'application_closing_date', s.application_close_date,
    'deadline_is_rolling', (coalesce(s.description,'') || ' ' || coalesce(s.award_value_text,'')) ~* '(rolling (basis|applications|intake|admission)|until (all )?(places|funds|positions) (are )?(filled|allocated)|open (all|throughout the) year|year[- ]round)',
    'current_status', case when s.application_close_date is null then 'check_provider'
                           when s.application_close_date < current_date then 'closed'
                           when s.application_open_date > current_date then 'opening_soon' else 'open' end,
    'study_levels', to_jsonb(coalesce((select levels from lv), '{}'::text[])), 'study_levels_list', to_jsonb(coalesce((select levels from lv), '{}'::text[])),
    'study_levels_source', case when (select n from lv) > 0 then 'linked_courses' end,
    'study_stages', coalesce((select jsonb_agg(distinct value_text) from cr where criterion_type='study_stage' and value_text is not null), '[]'::jsonb),
    'student_type', (select v from st),
    'study_load', (select string_agg(distinct value_text, ', ') from cr where criterion_type='study_load'),
    'study_area_codes', case when (select codes from areas) is not null then to_jsonb((select codes from areas)) end,
    'academic_minimum', (select jsonb_build_object('value', value_number, 'scale', scale, 'text', human_text) from acad),
    'min_academic_score', (select value_number from acad where upper(scale) in ('WAM','PERCENTAGE','%') and value_number between 0 and 100),
    'automatic_consideration', case when exists (select 1 from cr where criterion_type='application_method' and value_text='automatic') then true
                                    when s.application_required then false end,
    'citizenship_eligibility', to_jsonb((select codes from nat)), 'eligible_countries_list', to_jsonb((select codes from nat)),
    'gender', (select string_agg(distinct value_text, ', ') from cr where criterion_type='gender'),
    'age_min', (select min(value_number) from cr where criterion_type='minimum_age'),
    'age_max', null,
    'renewable', case when s.award_duration_basis in ('annual','annual_program_duration','program_duration','per_semester') then true
                      when s.award_duration_basis in ('one_off','first_year') then false end,
    'eligibility_summary', (select string_agg(human_text, ' ') from cr where criterion_type='published_eligibility_narrative'),
    'reference_code', null::text, -- 11 Oct 2026: no national register codes (Study Australia retired)
    'course_count', coalesce((select n from lv), 0),
    'last_verified_date', s.updated_at::date,
    'publication_status', s.publication_status)
  from s, p
$function$;

-- 3. Retire the legacy jobs: national register feeds (Study Australia, Australia Awards, Manaaki), the scope-based course links
--    they fed, the AI-run scheduler and the country watch that asked for registers. Their rows on the screens are removed by the
--    paste file; the functions stay until then.
select cron.unschedule(j.jobname) from cron.job j where j.jobname in ('coursefinder-scholarship-etl-scheduler', 'coursefinder-scholarship-maintenance',
  'coursefinder-scholarship-ai-change-scheduler', 'scholarship-country-watch', 'scholarship-scope-apply');
update pipeline.scholarship_etl_schedules set enabled = false where enabled;

-- 4. Register (Study Australia, Australia Awards, Manaaki) records
--    a) with their own provider page read and name-checked: kept as provider-page records
with keep as (
  select s.id, s.provider_id from scholarship.scholarships s
   where (exists (select 1 from scholarship.identifiers i where i.scholarship_id = s.id and i.scheme in ('study_australia_scholarship_id', 'dfat_award_scheme'))
          or s.source_id in (select src.id from pipeline.sources src where src.metadata->>'scholarship_source_key' in ('au_study_australia_scholarships', 'au_dfat_australia_awards', 'nz_mfat_manaaki')))
     and exists (select 1 from pipeline.scholarship_pages p where p.scholarship_id = s.id and p.read_status = 'read' and coalesce((p.name_check->>'ok')::boolean, false))
     and not security.reference_url_has_use(coalesce(s.source_url, ''), 'scholarship_placeholder')),
idf as (update scholarship.identifiers i set status = 'inactive' from keep k
         where i.scholarship_id = k.id and i.scheme in ('study_australia_scholarship_id', 'dfat_award_scheme') and i.status <> 'inactive' returning i.scholarship_id),
src as (update scholarship.scholarships s set source_id = security.coverage_sweep_source(k.provider_id), updated_at = now() from keep k
         where s.id = k.id and s.source_id is distinct from security.coverage_sweep_source(k.provider_id) returning s.id)
insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value)
select k.id, 'register_source_retired', jsonb_build_object('register', 'study_australia_or_national'), jsonb_build_object('kept_as', 'provider page record', 'decision', 'Platform Admin 11 Oct 2026')
  from keep k;
--    b) without their own provider page: set inactive (withdrawn if published); not deleted
with gone as (
  select s.id, s.publication_status from scholarship.scholarships s
   where s.lifecycle_status = 'active'
     and (security.reference_url_has_use(coalesce(s.source_url, ''), 'scholarship_placeholder')
          or exists (select 1 from scholarship.identifiers i where i.scholarship_id = s.id and i.scheme in ('study_australia_scholarship_id', 'dfat_award_scheme'))
          or s.source_id in (select src.id from pipeline.sources src where src.metadata->>'scholarship_source_key' in ('au_study_australia_scholarships', 'au_dfat_australia_awards', 'nz_mfat_manaaki')))
     and not exists (select 1 from pipeline.scholarship_pages p where p.scholarship_id = s.id and p.read_status = 'read' and coalesce((p.name_check->>'ok')::boolean, false))),
upd as (update scholarship.scholarships s set lifecycle_status = 'inactive', publication_status = case when s.publication_status = 'published' then 'withdrawn' else s.publication_status end, updated_at = now()
          from gone g where s.id = g.id returning s.id)
insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value)
select g.id, 'register_record_retired', jsonb_build_object('publication_status', g.publication_status), jsonb_build_object('lifecycle_status', 'inactive', 'reason', 'national register record with no provider page of its own', 'decision', 'Platform Admin 11 Oct 2026')
  from gone g;
--    c) candidates that came from a register are not read
update pipeline.scholarship_page_candidates set admit_status = 'rejected', admit_reasons = array['register_retired'], next_read_at = 'infinity'
 where source = 'register' and admit_status is null and matched_scholarship_id is null;

-- 5. Scraper credits for scholarship work: cap 12,000 to 60,000 (Platform Admin: discovery candidates through the scraper, no daily cap)
update pipeline.scholarship_layer_settings set value = 60000, max_value = greatest(max_value, 100000), updated_at = now(),
       reason = 'Platform Admin 11 Oct 2026: every scholarship read through the scraper, no daily cap; was 12000'
 where key = 'firecrawl_cap' and value < 60000;
update pipeline.scholarship_layer_settings set label = 'Read scholarship pages through the scraper (always on)', value = 1, min_value = 1, max_value = 1, updated_at = now(),
       help = 'Scholarship pages are always read through the scraper (Platform Admin, 11 Oct 2026); there is no direct read. This setting is kept only until it is removed.',
       reason = 'Platform Admin 11 Oct 2026: scraper only, no fallback'
 where key = 'read_via_scraper';

-- 6. Read everything again through the scraper with the new reader (v0.7.0): every active scholarship page, every listing page,
--    and discovery candidates that a direct read could not open
update pipeline.scholarship_pages p set next_read_at = now(), attempts = 0, leased_until = null
  from scholarship.scholarships s where s.id = p.scholarship_id and s.lifecycle_status = 'active';
update pipeline.scholarship_listing_pages set next_read_at = now() where active;
update pipeline.scholarship_page_candidates set next_read_at = now(), attempts = 0, leased_until = null
 where admit_status is null and matched_scholarship_id is null and source <> 'register'
   and read_status in ('blocked', 'fetch_failed', 'too_thin', 'not_html', 'robots_disallowed');

do $post$
declare v_expected jsonb := '{"security.scholarship_sweep_apply_v1(uuid)": "d64a9fafd63a24c68ac05aa95afbe555", "security.scholarship_publishability_v1()": "76ac34faa8412e1169db1cf634a8e73e", "public.admin_scholarship_record_read(uuid)": "5db3e70d026ed471b119917e1177e062", "public.svc_scholarship_read_record(uuid,text,integer,text,text,text,text,jsonb)": "29e88df71de57ebe077118c0795cbb63", "security.scholarship_coverage_row_v1(uuid)": "9d1daac45a20a180f0ac03891a479976", "public.admin_scholarship_coverage_provider(uuid)": "f985f7798729801cf172b70641947ee7", "security.scholarship_audience_read_v1()": "6896910608e5953cdb0e8b16c0a73f87", "security.scholarship_nationality_read_v1()": "666b232e6c05563987163de1796b3505", "public.website_edge_scholarship_search_v1(jsonb,integer,integer)": "cb3da54e25ae7c90c48f4e2257357fd1", "api.website_v2_scholarship_item(uuid)": "d1792cc7161101ce8c22abad70ecbd36"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
