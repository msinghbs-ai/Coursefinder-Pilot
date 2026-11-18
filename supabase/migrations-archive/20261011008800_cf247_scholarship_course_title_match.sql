-- CF-247 (11 Oct 2026): a course title a scholarship page names is matched to the provider's own course when the titles are
-- the same or, for long titles, one contains the other (Adelaide University "Master of Business Administration (Defence and
-- Space)" was not matched and the scholarship fell back to all 60 postgraduate business courses). Applies to named and excluded
-- courses alike. md5-checked before and after; nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := '{"security.scholarship_sweep_apply_v1(uuid)": "a5431127dd4c5c85ac33b5e92dcbcb02"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- A course title named on a scholarship page matches one of the provider's courses when, ignoring case, spaces and punctuation,
-- it is the same title, or (titles of 20 characters or more) one contains the other ("Master of Business Administration
-- (Defence and Space)" and "Global Executive Master of Business Administration (Defence and Space)").
create or replace function security.scholarship_course_title_match_v1(p_named text, p_canonical text, p_display text)
returns boolean language sql immutable set search_path to 'pg_catalog' as $fn$
  with n as (select regexp_replace(lower(coalesce(p_named, '')), '[^a-z0-9]+', '', 'g') named,
                    regexp_replace(lower(coalesce(p_canonical, '')), '[^a-z0-9]+', '', 'g') a,
                    regexp_replace(lower(coalesce(p_display, '')), '[^a-z0-9]+', '', 'g') b)
  select length(named) >= 8 and (named in (a, b)
         or (length(named) >= 20 and ((a <> '' and (strpos(a, named) > 0 or (length(a) >= 20 and strpos(named, a) > 0)))
                                   or (b <> '' and (strpos(b, named) > 0 or (length(b) >= 20 and strpos(named, b) > 0))))))
    from n
$fn$;
revoke all on function security.scholarship_course_title_match_v1(text, text, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION security.scholarship_sweep_apply_v1(p_scholarship_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare pg record; s record; v_codes text[]; v_fields text[]; v_old uuid[]; v_new uuid[]; v_changes text[]:='{}'; v_src uuid; f jsonb;
  v_d jsonb; v_date date; v_prec text; v_basis text; v_links jsonb; v_del uuid[]; v_add uuid[]; v_unmatched jsonb := '[]'::jsonb; v_excl uuid[] := '{}'; v_excl_text text;
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
  -- courses the page excludes ("all undergraduate degrees, excluding the Bachelor of ...") are never linked
  if jsonb_typeof(f->'named_courses'->'excluded') = 'array' then
    select coalesce(array_agg(distinct c.id), '{}') into v_excl from catalogue.courses c
      join jsonb_array_elements(f->'named_courses'->'excluded') x
        on (x ? 'code' and upper(coalesce(c.course_code,'')) = upper(x->>'code'))
        or (x ? 'title' and security.scholarship_course_title_match_v1(x->>'title', c.canonical_title, c.display_title))
     where c.provider_id = s.provider_id;
    select string_agg(distinct coalesce(x->>'title', x->>'code'), ', ') into v_excl_text from jsonb_array_elements(f->'named_courses'->'excluded') x;
  end if;
  if jsonb_typeof(f->'named_courses') = 'object' then
    insert into _sch_links(course_id, proof)
    select distinct on (c.id) c.id, jsonb_build_object('kind', x.kind, 'named', x.named, 'text', x.txt)
      from catalogue.courses c
      join (select 'course_code' kind, nc->>'code' named, nc->>'text' txt, null::text norm from jsonb_array_elements(coalesce(f->'named_courses'->'codes','[]')) nc
            union all
            select 'course_title', nc->>'title', nc->>'text', regexp_replace(lower(nc->>'title'), '[^a-z0-9]+', '', 'g') from jsonb_array_elements(coalesce(f->'named_courses'->'titles','[]')) nc) x
        on (x.kind = 'course_code' and upper(coalesce(c.course_code,'')) = upper(x.named))
        or (x.kind = 'course_title' and security.scholarship_course_title_match_v1(x.named, c.canonical_title, c.display_title))
     where c.provider_id = s.provider_id and c.lifecycle_status = 'active' and not (c.id = any(v_excl))
     order by c.id, (x.kind = 'course_code') desc;
    select coalesce(jsonb_agg(x), '[]'::jsonb) into v_unmatched from (
      select jsonb_build_object('code', nc->>'code') x from jsonb_array_elements(coalesce(f->'named_courses'->'codes','[]')) nc
       where not exists (select 1 from catalogue.courses c where c.provider_id = s.provider_id and upper(coalesce(c.course_code,'')) = upper(nc->>'code'))
      union all
      select jsonb_build_object('title', nc->>'title') from jsonb_array_elements(coalesce(f->'named_courses'->'titles','[]')) nc
       where not exists (select 1 from catalogue.courses c where c.provider_id = s.provider_id and c.lifecycle_status = 'active'
                          and security.scholarship_course_title_match_v1(nc->>'title', c.canonical_title, c.display_title))) z;
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
                     'text', concat_ws(' | ', case when cardinality(v_codes)>0 then f->>'levels_text' end, case when cardinality(v_fields)>0 then f->>'fields_text' end),
                     'excluding', v_excl_text)
        from catalogue.courses c left join ref.study_levels sl on sl.id=c.study_level_id left join ref.fields_of_study fos on fos.id=c.primary_field_id
       where c.provider_id=s.provider_id and c.lifecycle_status='active' and not (c.id = any(v_excl))
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
  v_links := jsonb_build_object('basis', coalesce(v_basis,'none'), 'courses', (select count(*) from _sch_links), 'added', cardinality(v_add), 'removed', cardinality(v_del), 'named_not_matched', v_unmatched,
                                'excluded', cardinality(v_excl), 'excluded_named', v_excl_text);
  if cardinality(v_add)+cardinality(v_del)>0 then
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
    values (s.id,'course_links',jsonb_build_object('removed',cardinality(v_del)),v_links,pg.evidence_id);
    v_changes:=v_changes||'course_links'::text;
    perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_add||v_del)),true);
  end if;
  update pipeline.scholarship_pages set applied_at=now(), apply_result=jsonb_build_object('changes',to_jsonb(v_changes),'links',v_links,'extractor',f->>'extractor') where scholarship_id=s.id;
  return jsonb_build_object('applied',true,'changes',to_jsonb(v_changes),'links',v_links);
end $function$;

-- pages already read by readers v0.7.0 and v0.7.1 are read again with v0.7.2 and this rule
update pipeline.scholarship_pages set next_read_at = now(), attempts = 0, leased_until = null
 where facts->>'extractor' in ('scholarship-sweep-v0.7.0', 'scholarship-sweep-v0.7.1');

do $post$
declare v_expected jsonb := '{"security.scholarship_sweep_apply_v1(uuid)": "7189ffebb3e5449b1af4a364731a7687"}'::jsonb;
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;
