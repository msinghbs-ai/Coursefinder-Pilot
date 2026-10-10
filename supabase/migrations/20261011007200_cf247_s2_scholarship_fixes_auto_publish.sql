-- CF-247 v2.15.239 (S2 and S4): scholarship fixes found by the Curtin review (11 Oct 2026). Platform Admin decisions: "Link all intl
-- courses, marked" and "Auto-publish, list for morning review".
--  1. Course links: a faculty or school the reader cannot match to a field (often a site-wide mention such as Curtin's "WA School of
--     Mines") no longer stops the links; the levels the page states decide. A page that names no level, field or course places no
--     restriction: the scholarship links to all of the provider's active courses open to international students, marked on the
--     page record as course_links_all.
--  2. One scholarship, one record: semester or year editions and register copies of the same scholarship ("Semester 2 - 2026 - Curtin
--     Global Future Leaders Scholarship ($10K)") are held with the reason "another edition of this scholarship is listed"; the
--     provider's own, evergreen, most recently updated record is the one that can be published.
--  3. Automatic publishing (setting auto_publish, on/off, Layer 4): every hour, scholarships that pass every check are published as a
--     batch named "auto-publish <date>", listed for review on Layer 4 Review > Scholarship publishing.
--  4. Data: course links re-applied for pages held by the faculty rule or naming no restriction; pages with no value read again by
--     reader v0.6.3 (academic-result percentages such as "CWA of 95%" are no longer read as award values); value text that starts
--     mid-word is cleared or trimmed to a whole sentence.
-- md5-checked before and after. Nothing is dropped or deleted.
do $guard$
declare v_expected jsonb := jsonb_build_object('security.scholarship_sweep_apply_v1(uuid)', '1dfa8ba05fd210fe83209f56e751e943', 'security.scholarship_publishability_v1()', 'dcf4351f9a3dbe3d8c6be09993681dcb');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'live % differs from the definition this change replaces', v_sig;
    end if;
  end loop;
end $guard$;

-- 2. The series key: the scholarship's name without an edition ("Semester 2 - 2026 -", "2027 - Semester 1 -", "($10K)").
create or replace function security.scholarship_series_key_v1(p_name text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select btrim(regexp_replace(regexp_replace(regexp_replace(lower(coalesce(p_name, '')),
           '^\s*(\d{4}\s*[-:]\s*)?((semester|sem|trimester|term|intake)\s*\d+\s*[-:]?\s*)?(\d{4}\s*[-:]\s*)?', ''),
           '\s*\((a?\$|aud)?\s*[\d,.]+\s*k?\)\s*$', ''), '\s+', ' ', 'g'))
$function$;
revoke all on function security.scholarship_series_key_v1(text) from public, anon, authenticated;

-- 3. Automatic publishing, on/off from the scholarship settings (Layer 4). Each run is one publication batch named auto-publish.
insert into pipeline.scholarship_layer_settings(key, layer, label, help, value, min_value, max_value, unit, updated_at, reason)
values ('auto_publish', 4, 'Publish scholarships that pass every check automatically',
        'Every hour, scholarships that pass every publishing check are published as one batch named "auto-publish". Each batch is listed on Layer 4 Review > Scholarship publishing for review; withdraw any that is wrong. 1 = on, 0 = off.',
        1, 0, 1, 'on/off', now(), 'Platform Admin decision 11 Oct 2026: "Auto-publish, list for morning review"')
on conflict (key) do nothing;

create or replace function security.scholarship_auto_publish_v1()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
begin
  if security.scholarship_setting('auto_publish', 0) < 1 then return jsonb_build_object('skipped', 'auto_publish is off'); end if;
  return security.scholarship_publish_batch_v1('auto-publish ' || to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), true);
end $function$;
revoke all on function security.scholarship_auto_publish_v1() from public, anon, authenticated;
select cron.schedule('scholarship-auto-publish', '29 * * * *', 'select security.scholarship_auto_publish_v1()');

CREATE OR REPLACE FUNCTION security.scholarship_sweep_apply_v1(p_scholarship_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare pg record; s record; v_codes text[]; v_fields text[]; v_old uuid[]; v_new uuid[]; v_changes text[]:='{}'; v_src uuid; f jsonb;
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

  if s.application_close_date is null and (f->'deadline'->>'date') is not null and (f->'deadline'->>'date')::date >= current_date then
    update scholarship.scholarships set application_close_date=(f->'deadline'->>'date')::date, updated_at=now() where id=s.id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'application_close_date',null,f->'deadline',pg.evidence_id);
    v_changes:=v_changes||'application_close_date'::text;
  end if;

  -- a discovered provider page, confirmed by the reader to name this scholarship, replaces the Study Australia source
  if pg.url_source='discovered' and security.reference_url_has_use(coalesce(s.source_url,''), 'scholarship_placeholder') and not security.reference_url_has_use(coalesce(pg.final_url,pg.url), 'scholarship_placeholder')
     and coalesce((pg.name_check->>'ok')::boolean,false) then
    update scholarship.scholarships set source_url=pg.url, evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
    values (s.id,'source_url',jsonb_build_object('source_url',s.source_url,'evidence_id',s.evidence_id),jsonb_build_object('source_url',pg.url,'name_check',pg.name_check),pg.evidence_id);
    v_changes:=v_changes||'source_url'::text;
  end if;

  if not security.reference_url_has_use(coalesce(pg.final_url,pg.url), 'scholarship_placeholder') and not exists (select 1 from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url') then
    insert into scholarship.identifiers(scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
    values (s.id,'first_party_detail_url',pg.url,v_src,pg.evidence_id,true,'active') on conflict do nothing;
    v_changes:=v_changes||'first_party_url'::text;
  end if;

  -- Decision 211: eligibility criteria and award duration from the page
  v_changes:=v_changes||security.scholarship_criteria_apply_v1(s.id);

  -- v0.5.0: an English language course scholarship links only to the provider's English language courses
  if f ? 'english_course' then
    select coalesce(array_agg(c.id),'{}') into v_new
      from catalogue.courses c join ref.study_levels sl on sl.id=c.study_level_id
     where c.provider_id=s.provider_id and c.lifecycle_status='active' and sl.code='non_aqf_award' and coalesce(c.course_code,'')<>''
       and c.canonical_title ~* case f->'english_course'->>'course'
             when 'general english' then '\mgeneral english\M'
             when 'ielts preparation' then '\mielts\M'
             when 'academic english' then '(academic english|english for academic purposes|\meap\M)'
             else '(general english|academic english|english for academic purposes|\meap\M|\mielts\M|\melicos\M|english language)' end;
    select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings
     where scholarship_id=s.id and mapping_basis in ('explicit_provider_scope','sweep_level_field_scope') and not (course_id=any(v_new));
    if cardinality(v_old)>0 then
      delete from scholarship.course_mappings where scholarship_id=s.id and course_id=any(v_old) and mapping_basis in ('explicit_provider_scope','sweep_level_field_scope');
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links_removed',jsonb_build_object('courses',cardinality(v_old),'course_ids',to_jsonb(v_old)),jsonb_build_object('reason','English language course scholarship: not linked to other courses','english_course',f->'english_course'),pg.evidence_id);
      v_changes:=v_changes||'course_links_removed'::text;
    end if;
    delete from scholarship.scopes sc using pipeline.sources src where sc.source_id=src.id and src.source_type='provider_course_page_sweep' and sc.scope_type='study_level' and sc.scholarship_id=s.id;
    if cardinality(v_new)>0 then
      insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by,mapped_at,updated_at)
      select s.id, x, 'mapped', 'sweep_level_field_scope', pg.evidence_id, null, now(), now() from unnest(v_new) x
      on conflict (scholarship_id,course_id) do update set mapping_basis='sweep_level_field_scope', mapping_state='mapped', evidence_id=excluded.evidence_id, updated_at=now();
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links',null,jsonb_build_object('courses',cardinality(v_new),'english_course',f->'english_course'),pg.evidence_id);
      v_changes:=v_changes||'course_links'::text;
    end if;
    if cardinality(v_old)+cardinality(v_new)>0 then perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_old||v_new)),true); end if;
    update pipeline.scholarship_pages set applied_at=now(), apply_result=jsonb_build_object('changes',to_jsonb(v_changes),'english_course',f->'english_course') where scholarship_id=s.id;
    return jsonb_build_object('applied',true,'changes',to_jsonb(v_changes));
  end if;

  v_codes:=security.scholarship_level_codes(f->'levels');
  v_fields:=array(select jsonb_array_elements_text(coalesce(f->'fields','[]')));
  -- v2.15.239 (S2): a faculty or school the reader cannot match to a field (often a site-wide mention such as "WA School of Mines")
  -- no longer stops the course links; the levels the page states decide
  if coalesce((f->>'field_unmapped')::boolean,false) and cardinality(v_fields)=0 then
    v_changes:=v_changes||'course_links_faculty_unmatched'::text;
  end if;
  if cardinality(v_codes)>0 or cardinality(v_fields)>0 then
    select coalesce(array_agg(c.id),'{}') into v_new
      from catalogue.courses c left join ref.study_levels sl on sl.id=c.study_level_id left join ref.fields_of_study fos on fos.id=c.primary_field_id
     where c.provider_id=s.provider_id and c.lifecycle_status='active'
       and (cardinality(v_codes)=0 or sl.code=any(v_codes))
       and (cardinality(v_fields)=0 or exists (select 1 from unnest(v_fields) fp where fos.code like fp||'%'));
    if cardinality(v_new)>0 then
      select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings where scholarship_id=s.id;
      delete from scholarship.course_mappings where scholarship_id=s.id and mapping_basis in ('explicit_provider_scope','sweep_level_field_scope') and not (course_id=any(v_new));
      insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by,mapped_at,updated_at)
      select s.id, x, 'mapped', 'sweep_level_field_scope', pg.evidence_id, null, now(), now() from unnest(v_new) x
      on conflict (scholarship_id,course_id) do update set mapping_basis='sweep_level_field_scope', mapping_state='mapped', evidence_id=excluded.evidence_id, updated_at=now();
      insert into scholarship.scopes(scholarship_id,scope_type,study_level_id,include_exclude,source_id,evidence_id)
      select s.id,'study_level',sl.id,'include',v_src,pg.evidence_id from ref.study_levels sl
       where sl.code=any(v_codes) and not exists (select 1 from scholarship.scopes x where x.scholarship_id=s.id and x.scope_type='study_level' and x.study_level_id=sl.id);
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links',jsonb_build_object('courses',cardinality(v_old)),jsonb_build_object('courses',cardinality(v_new),'levels',f->'levels','fields',f->'fields'),pg.evidence_id);
      v_changes:=v_changes||'course_links'::text;
      perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_old||v_new)),true);
    end if;
  end if;

  -- v2.15.239 (S2, Platform Admin decision "Link all intl courses, marked"): a page that names no level, field or course places no
  -- restriction, so the scholarship links to all of the provider's active courses open to international students (marked
  -- course_links_all on the page record). A person's scope decision still governs through the mapping guard.
  if cardinality(v_codes)=0 and cardinality(v_fields)=0 then
    select coalesce(array_agg(c.id),'{}') into v_new from catalogue.courses c
     where c.provider_id=s.provider_id and c.lifecycle_status='active' and c.open_to_international is not false;
    if cardinality(v_new)>0 then
      select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope';
      delete from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='sweep_level_field_scope' and not (course_id=any(v_new));
      insert into scholarship.course_mappings(scholarship_id,course_id,mapping_state,mapping_basis,evidence_id,mapped_by,mapped_at,updated_at)
      select s.id, x, 'mapped', 'sweep_level_field_scope', pg.evidence_id, null, now(), now() from unnest(v_new) x
      on conflict (scholarship_id,course_id) do update set mapping_state='mapped', evidence_id=excluded.evidence_id, updated_at=now()
       where scholarship.course_mappings.mapping_basis='sweep_level_field_scope';
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id)
      values (s.id,'course_links',jsonb_build_object('courses',cardinality(v_old)),jsonb_build_object('courses',cardinality(v_new),'rule','all courses open to international students: the page names no level, field or course'),pg.evidence_id);
      v_changes:=v_changes||'course_links_all'::text;
      perform search.refresh_course_enrichment_scoped_v1(array(select distinct unnest(v_old||v_new)),true);
    end if;
  end if;
  update pipeline.scholarship_pages set applied_at=now(), apply_result=jsonb_build_object('changes',to_jsonb(v_changes)) where scholarship_id=s.id;
  return jsonb_build_object('applied',true,'changes',to_jsonb(v_changes));
end $function$;

CREATE OR REPLACE FUNCTION security.scholarship_publishability_v1()
 RETURNS TABLE(scholarship_id uuid, publishable boolean, missing text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline'
AS $function$
  select s.id,
         cardinality(m.missing)=0,
         m.missing
    from scholarship.scholarships s
    left join pipeline.scholarship_pages sp on sp.scholarship_id=s.id and sp.read_status='read'
    cross join lateral (select array_remove(array[
        case when s.lifecycle_status<>'active' then 'not active' end,
        case when coalesce(s.source_url,'')='' or security.reference_url_has_use(s.source_url, 'scholarship_placeholder') then 'no provider page' end,
        case when coalesce(s.audience,'') !~* 'international' then 'not for international students' end,
        case when sp.facts is not null and not security.scholarship_from_record_register(s.id) and coalesce(sp.facts->>'eligibility_excerpt','') ~* '(australian citizen|permanent resident|domestic student|new zealand citizen|canadian citizen)'
                  and coalesce(sp.facts->>'eligibility_excerpt','') !~* 'international' then 'provider page limits it to citizens and residents' end,
        case when sp.facts is not null and sp.facts->>'international'='false' and not security.scholarship_from_record_register(s.id) then 'provider page does not mention international students' end,
        case when not ((s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) or exists (select 1 from scholarship.award_tiers t where t.scholarship_id=s.id and t.tier_code like 'page_tier_%') or (security.scholarship_from_record_register(s.id) and exists (select 1 from scholarship.coverage cv where cv.scholarship_id=s.id and cv.coverage_type='tuition_fees' and cv.percentage=100))) then 'no stated award value' end,
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
        case when not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped') then 'no linked course' end,
        case when exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped')
              and not exists (select 1 from scholarship.course_mappings cm where cm.scholarship_id=s.id and cm.mapping_state='mapped' and cm.mapping_basis<>'explicit_provider_scope')
              and s.name ~* '(engineer|undergrad|postgrad|research|ph\.?d|doctor|master|bachelor|honours|diploma|law|medic|nurs|business|commerce|science|arts|information tech|computing|education|design|music|health|pharm|faculty|school of|college of|mba)'
             then 'course link broader than the scholarship' end,
        -- v2.15.239 (S2): one scholarship, one record; the provider's own, evergreen, most recently updated edition is the one listed
        case when exists (select 1 from scholarship.scholarships o where o.provider_id=s.provider_id and o.id<>s.id and o.lifecycle_status='active'
                    and security.scholarship_series_key_v1(o.name)=security.scholarship_series_key_v1(s.name)
                    and (security.reference_url_has_use(coalesce(o.source_url,''),'scholarship_placeholder')::int, (security.scholarship_series_key_v1(o.name)<>lower(btrim(o.name)))::int, -extract(epoch from o.updated_at), o.id::text)
                      < (security.reference_url_has_use(coalesce(s.source_url,''),'scholarship_placeholder')::int, (security.scholarship_series_key_v1(s.name)<>lower(btrim(s.name)))::int, -extract(epoch from s.updated_at), s.id::text))
             then 'another edition of this scholarship is listed' end,
        case when greatest(s.updated_at,(select e.captured_at from pipeline.evidence_artifacts e where e.id=s.evidence_id)) < now()-interval '12 months' then 'not verified in 12 months' end
      ], null) missing) m
$function$;

-- 4. Data: links re-applied, values read again, value text cleaned
do $data$
declare r record; n_apply int := 0; n_reread int; n_clear int; n_trim int;
begin
  for r in select sp.scholarship_id from pipeline.scholarship_pages sp join scholarship.scholarships s on s.id = sp.scholarship_id and s.lifecycle_status = 'active'
            where sp.read_status = 'read' and not sp.facts ? 'english_course'
              and (sp.apply_result->'changes' ? 'course_links_need_review'
                   or (jsonb_array_length(coalesce(sp.facts->'levels', '[]'::jsonb)) = 0 and jsonb_array_length(coalesce(sp.facts->'fields', '[]'::jsonb)) = 0)) loop
    perform security.scholarship_sweep_apply_v1(r.scholarship_id); n_apply := n_apply + 1;
  end loop;
  update pipeline.scholarship_pages sp set next_read_at = now()
    from scholarship.scholarships s
   where s.id = sp.scholarship_id and s.lifecycle_status = 'active' and sp.read_status = 'read'
     and coalesce(sp.facts->'value'->>'type', 'none') in ('ambiguous', 'none')
     and not (s.award_value_type in ('percentage', 'fixed_amount') and coalesce(s.award_percentage, s.award_amount) is not null);
  get diagnostics n_reread = row_count;
  update scholarship.scholarships s set award_value_text = null, updated_at = now()
   where s.lifecycle_status = 'active' and s.award_value_text ~ '^[a-z]'
     and not (s.award_value_type in ('percentage', 'fixed_amount') and coalesce(s.award_percentage, s.award_amount) is not null);
  get diagnostics n_clear = row_count;
  update scholarship.scholarships s set award_value_text = substring(s.award_value_text from '\.\s+(.*)$'), updated_at = now()
   where s.lifecycle_status = 'active' and s.award_value_text ~ '^[a-z]' and length(coalesce(substring(s.award_value_text from '\.\s+(.*)$'), '')) >= 25;
  get diagnostics n_trim = row_count;
  -- the pages queued above are read faster tonight: 40 a run (the setting's maximum) instead of 20; set back on Layer 2 > Scholarships
  update pipeline.scholarship_layer_settings set value = 40, updated_at = now(), reason = 'CF-247 v2.15.239 (11 Oct 2026): pages queued to read again after the value-reading fix'
   where key = 'read_limit' and value < 40;
  raise notice 'links re-applied %, pages queued to read again %, value texts cleared %, trimmed %', n_apply, n_reread, n_clear, n_trim;
end $data$;

do $post$
declare v_expected jsonb := jsonb_build_object('security.scholarship_sweep_apply_v1(uuid)', 'a59a894e38f84c2058e5c1a3ff7cee81', 'security.scholarship_publishability_v1()', '46ed54fc88e1cf2c5ed4e559c0c6caa8');
  v_sig text;
begin
  for v_sig in select jsonb_object_keys(v_expected) loop
    if md5(replace(pg_get_functiondef(v_sig::regprocedure), E'\r', '')) <> v_expected->>v_sig then
      raise exception 'CF-247 v2.15.239 post-check: % not as intended', v_sig;
    end if;
  end loop;
end $post$;

do $post2$
begin
  if security.scholarship_series_key_v1('Semester 2 - 2026 - Curtin Global Future Leaders Scholarship ($10K)') <> 'curtin global future leaders scholarship'
     or security.scholarship_series_key_v1('2027 - Semester 1 - Curtin Humanitarian Scholarship (Future Students)') <> 'curtin humanitarian scholarship (future students)'
     or security.scholarship_series_key_v1('Curtin Global Merit Scholarship') <> 'curtin global merit scholarship'
     or not exists (select 1 from cron.job where jobname = 'scholarship-auto-publish' and active)
     or not exists (select 1 from pipeline.scholarship_layer_settings where key = 'auto_publish') then
    raise exception 'CF-247 v2.15.239 post-check: new objects not as intended';
  end if;
end $post2$;
