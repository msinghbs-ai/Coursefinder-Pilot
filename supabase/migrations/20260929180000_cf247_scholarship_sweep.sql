-- CF-247 scholarship sweep (Platform Admin approval 29 Sep 2026 09:56 IST: publish under Decision 139, then sweep for
-- more; direction 13:19 IST: progress the scholarship sweep). Each active scholarship's own provider page is read
-- (robots.txt respected, gzipped evidence kept) and deterministic facts are recorded: study levels, field restriction
-- (from the scholarship's name), award value, closing date, international wording, eligibility excerpt.
-- Applied only where the record lacks the fact, every change logged:
--   * award value: one clear percentage of tuition, full tuition, or one clear fixed amount (tiers/mixed are not applied);
--   * closing date: a single explicit future date;
--   * provider page kept as the first-party identifier;
--   * course links: provider's active courses at the stated levels (and in the named field), replacing provider-wide
--     links; nothing is linked when a named field cannot be matched. Search is refreshed for the courses affected.
-- Publication stays with security.scholarship_publish_batch_v1 (Decision 139), run daily under the 29 Sep approval;
-- the daily review withdraws anything that stops qualifying.
create table if not exists pipeline.scholarship_pages (
  scholarship_id uuid primary key references scholarship.scholarships(id) on delete cascade,
  url text not null, final_url text, read_status text, http_status int, fetched_via text, read_at timestamptz,
  next_read_at timestamptz not null default now(), attempts int not null default 0, leased_until timestamptz,
  evidence_id uuid, facts jsonb, applied_at timestamptz, apply_result jsonb);
create table if not exists pipeline.scholarship_sweep_changes (
  id bigint generated always as identity primary key, scholarship_id uuid not null, field text not null,
  before_value jsonb, after_value jsonb, evidence_id uuid, changed_at timestamptz not null default now());
alter table pipeline.scholarship_pages enable row level security;
alter table pipeline.scholarship_sweep_changes enable row level security;

-- level groups -> study level codes
create or replace function security.scholarship_level_codes(p_levels jsonb)
returns text[] language sql immutable as $f$
  select coalesce(array_agg(distinct c),'{}') from jsonb_array_elements_text(coalesce(p_levels,'[]')) l
  cross join lateral unnest(case l
    when 'undergraduate' then array['bachelor','bachelor_honours','associate_degree']
    when 'postgraduate_coursework' then array['masters_coursework','masters_extended','masters','graduate_certificate','graduate_diploma']
    when 'research' then array['masters_research','doctorate']
    when 'pathway' then array['diploma','advanced_diploma','certificate_iv','non_aqf_award']
    else array[]::text[] end) c
$f$;

insert into pipeline.scholarship_pages(scholarship_id,url)
select s.id, coalesce((select i.identifier_value from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url' order by i.is_primary desc limit 1), s.source_url)
  from scholarship.scholarships s
 where s.lifecycle_status='active'
   and coalesce((select i.identifier_value from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url' limit 1), s.source_url) is not null
   and coalesce((select i.identifier_value from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url' limit 1), s.source_url) !~* 'studyaustralia\.gov\.au'
on conflict do nothing;

create or replace function public.svc_scholarship_read_next(p_limit int)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','scholarship','pipeline' as $f$
declare v jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select p.scholarship_id from pipeline.scholarship_pages p join scholarship.scholarships s on s.id=p.scholarship_id and s.lifecycle_status='active'
     where p.next_read_at<=now() and coalesce(p.leased_until,'-infinity')<now() and p.attempts<5
     order by p.read_at nulls first limit greatest(1,least(coalesce(p_limit,20),40)) for update of p skip locked),
  upd as (update pipeline.scholarship_pages p set leased_until=now()+interval '10 minutes', attempts=p.attempts+1 from pick where p.scholarship_id=pick.scholarship_id
          returning p.scholarship_id, p.url)
  select coalesce(jsonb_agg(jsonb_build_object('scholarship_id',u.scholarship_id,'url',u.url,'name',s.name,'provider_id',s.provider_id)),'[]'::jsonb) into v
    from upd u join scholarship.scholarships s on s.id=u.scholarship_id;
  return v;
end $f$;
revoke all on function public.svc_scholarship_read_next(int) from public, anon, authenticated;
grant execute on function public.svc_scholarship_read_next(int) to service_role;

create or replace function security.scholarship_sweep_apply_v1(p_scholarship_id uuid)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','scholarship','catalogue','pipeline','security','search' as $f$
declare pg record; s record; v_codes text[]; v_fields text[]; v_old uuid[]; v_new uuid[]; v_changes text[]:='{}'; v_src uuid; f jsonb;
begin
  select * into pg from pipeline.scholarship_pages where scholarship_id=p_scholarship_id;
  select * into s from scholarship.scholarships where id=p_scholarship_id for update;
  if pg.read_status is distinct from 'read' or pg.facts is null or s.id is null then return jsonb_build_object('applied',false); end if;
  f:=pg.facts; v_src:=security.coverage_sweep_source(s.provider_id);

  -- award value (only when none is held)
  if not (s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage,s.award_amount) is not null) then
    if f->'value'->>'type'='percentage' and (f->'value'->>'percentage')::numeric between 5 and 100 then
      update scholarship.scholarships set award_value_type='percentage', award_percentage=(f->'value'->>'percentage')::numeric,
             award_applies_to_fee_type=coalesce(award_applies_to_fee_type,'tuition_fee'), award_value_text=coalesce(award_value_text,left(f->'value'->>'context',400)),
             evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'award_value',jsonb_build_object('type',s.award_value_type,'text',s.award_value_text),f->'value',pg.evidence_id);
      v_changes:=v_changes||'award_value'::text;
    elsif f->'value'->>'type'='fixed_amount' and (f->'value'->>'amount')::numeric > 0 then
      update scholarship.scholarships set award_value_type='fixed_amount', award_amount=(f->'value'->>'amount')::numeric, award_currency_code='AUD',
             award_value_text=coalesce(award_value_text,left(f->'value'->>'context',400)), evidence_id=pg.evidence_id, updated_at=now() where id=s.id;
      insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'award_value',jsonb_build_object('type',s.award_value_type,'text',s.award_value_text),f->'value',pg.evidence_id);
      v_changes:=v_changes||'award_value'::text;
    end if;
  end if;

  -- closing date (only when none is held, single explicit future date)
  if s.application_close_date is null and (f->'deadline'->>'date') is not null and (f->'deadline'->>'date')::date >= current_date then
    update scholarship.scholarships set application_close_date=(f->'deadline'->>'date')::date, updated_at=now() where id=s.id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id,field,before_value,after_value,evidence_id) values (s.id,'application_close_date',null,f->'deadline',pg.evidence_id);
    v_changes:=v_changes||'application_close_date'::text;
  end if;

  -- provider page as the first-party identifier
  if coalesce(pg.final_url,pg.url) !~* 'studyaustralia\.gov\.au' and not exists (select 1 from scholarship.identifiers i where i.scholarship_id=s.id and i.scheme='first_party_detail_url') then
    insert into scholarship.identifiers(scholarship_id,scheme,identifier_value,source_id,evidence_id,is_primary,status)
    values (s.id,'first_party_detail_url',pg.url,v_src,pg.evidence_id,true,'active') on conflict do nothing;
    v_changes:=v_changes||'first_party_url'::text;
  end if;

  -- course links from stated levels and the named field
  v_codes:=security.scholarship_level_codes(f->'levels');
  v_fields:=array(select jsonb_array_elements_text(coalesce(f->'fields','[]')));
  if cardinality(v_codes)>0 or cardinality(v_fields)>0 then
    select coalesce(array_agg(c.id),'{}') into v_new
      from catalogue.courses c left join ref.study_levels sl on sl.id=c.study_level_id left join ref.fields_of_study fos on fos.id=c.primary_field_id
     where c.provider_id=s.provider_id and c.lifecycle_status='active'
       and (cardinality(v_codes)=0 or sl.code=any(v_codes))
       and (cardinality(v_fields)=0 or exists (select 1 from unnest(v_fields) fp where fos.code like fp||'%'));
    if cardinality(v_new)>0 then
      select coalesce(array_agg(course_id),'{}') into v_old from scholarship.course_mappings where scholarship_id=s.id;
      delete from scholarship.course_mappings where scholarship_id=s.id and mapping_basis='explicit_provider_scope' and not (course_id=any(v_new));
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

  update pipeline.scholarship_pages set applied_at=now(), apply_result=jsonb_build_object('changes',to_jsonb(v_changes)) where scholarship_id=s.id;
  return jsonb_build_object('applied',true,'changes',to_jsonb(v_changes));
end $f$;
revoke all on function security.scholarship_sweep_apply_v1(uuid) from public, anon, authenticated;

create or replace function public.svc_scholarship_read_record(p_scholarship_id uuid, p_read_status text, p_http_status int, p_fetched_via text,
  p_final_url text, p_storage_path text, p_sha256 text, p_facts jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','scholarship','pipeline','security' as $f$
declare v_ev uuid; v_src uuid; v_pid uuid; v_url text; r jsonb;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.provider_id, p.url into v_pid, v_url from scholarship.scholarships s join pipeline.scholarship_pages p on p.scholarship_id=s.id where s.id=p_scholarship_id;
  if p_storage_path is not null then
    v_src:=security.coverage_sweep_source(v_pid);
    insert into pipeline.evidence_artifacts(entity_id,source_id,evidence_type,source_url,storage_path,content_hash,mime_type,metadata,capture_version,evidence_group_key)
    values (p_scholarship_id, v_src, 'scholarship_page', coalesce(p_final_url,v_url), p_storage_path, p_sha256, 'application/gzip',
            jsonb_build_object('worker','coverage-sweep scholarship_read','decision','Decision 139 sweep'), 1, 'scholarship:'||p_scholarship_id)
    returning id into v_ev;
  end if;
  update pipeline.scholarship_pages set read_status=p_read_status, http_status=p_http_status, fetched_via=p_fetched_via, final_url=p_final_url,
         read_at=now(), leased_until=null, evidence_id=coalesce(v_ev,evidence_id), facts=coalesce(p_facts,facts),
         next_read_at=case when p_read_status='read' then now()+interval '90 days' when p_read_status in ('robots_disallowed','blocked') then now()+interval '30 days' else now()+interval '6 hours' end,
         attempts=case when p_read_status='read' then 0 else attempts end
   where scholarship_id=p_scholarship_id;
  if p_read_status='read' then r:=security.scholarship_sweep_apply_v1(p_scholarship_id); end if;
  return coalesce(r,jsonb_build_object('applied',false));
end $f$;
revoke all on function public.svc_scholarship_read_record(uuid,text,int,text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_scholarship_read_record(uuid,text,int,text,text,text,text,jsonb) to service_role;

select cron.schedule('scholarship-read','*/5 * * * *',$$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"scholarship_read","limit":20}'::jsonb)$$);
-- Decision 139 batches are run by hand, one deliberate batch at a time (dry run, sample check, then apply); there is
-- no automatic publish job. The nightly scholarship-publication-review job still withdraws anything that stops qualifying.
