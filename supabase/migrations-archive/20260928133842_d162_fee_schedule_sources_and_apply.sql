-- CF-247 Decision 162 step 2: provider international fee schedules as qualified Layer 2 fee sources.
-- 1. One source per provider schedule (source_type provider_fee_schedule) and its qualification for the
--    international_fee domain only, bound by the exact CRICOS course code inside the provider (dry runs on
--    28 Sep 2026: Federation 73/73 bound; Western Sydney UG 73/76, PG 66/68; no same-year conflicts).
-- 2. svc_fee_schedule_apply: writes each bound row through the governed svc_coursefacts_apply_record path
--    (evidence, source record, Layer 4 block check), basis 'annual', fee year of the schedule. Duplicate codes
--    with different amounts are skipped as conflicts; a same-year different amount is never overwritten;
--    a newer fee year already current is left alone; an older-year provider tuition is superseded
--    (one current tuition, Decision 132). Search enrichment is refreshed for changed courses.

insert into pipeline.sources(source_type,system_id,provider_id,country_id,url,label,trust_rank,status,metadata)
select 'provider_fee_schedule', s.system_id, s.provider_id, s.country_id, x.url, x.label, 95, 'active',
       jsonb_build_object('facts',jsonb_build_array('international_fee'),'provider_cricos',x.cricos,'course_identity','exact CRICOS course code within the provider','decision','Decision 162')
  from (values ('00103D','https://www.federation.edu.au/international/fees','Federation University Australia international tuition fee schedule'),
               ('00917K','https://www.westernsydney.edu.au/international/applying/fees-and-costs/cost-of-tuition','Western Sydney University international tuition fee schedules')) x(cricos,url,label)
  join lateral (select s0.* from pipeline.sources s0 where s0.source_type='provider_course_page' and s0.metadata->>'provider_cricos'='00103D' limit 1) s on true
 where not exists (select 1 from pipeline.sources e where e.source_type='provider_fee_schedule' and e.metadata->>'provider_cricos'=x.cricos);
update pipeline.sources s set provider_id=(select pr.provider_id from catalogue.provider_registrations pr where upper(pr.registration_code)=s.metadata->>'provider_cricos' and lower(pr.registration_scheme)='cricos' limit 1)
 where s.source_type='provider_fee_schedule';

insert into pipeline.course_fact_source_qualifications(source_id,country_id,source_key,source_class,authority_name,provider_cricos,admitted_domains,mapping_strategy,evidence_strategy,qualification_status,notes,metadata)
select s.id, s.country_id, 'au_'||lower(s.metadata->>'provider_cricos')||'_intl_fee_schedule','provider_first_party',
       split_part(s.label,' international',1), s.metadata->>'provider_cricos', array['international_fee'],
       'exact CRICOS course code printed in the provider schedule, within the provider (Decision 149)',
       'schedule file retained as evidence with its SHA-256; one row per course; annual fee for one full-time year',
       'qualified','Decision 162 step 2: deterministic fee-schedule parser; dry run 28 Sep 2026 with no same-year conflicts',
       jsonb_build_object('gate','Decision-162-fee-schedule','qualified_at',now(),'apply_admitted',true,'search_admitted',true,'identity_authority',false,'change_control_ref','CF-CHG-20260915-247')
  from pipeline.sources s
 where s.source_type='provider_fee_schedule'
   and not exists (select 1 from pipeline.course_fact_source_qualifications q where q.source_id=s.id);

create or replace function public.svc_fee_schedule_apply(p_provider_cricos text, p_fee_year integer, p_storage_path text, p_url text, p_sha256 text, p_schedule text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','public','search' as $f$
declare v_source uuid; v_provider uuid; p_evidence_id uuid; r record; v_res jsonb; v_applied int:=0; v_super int:=0; v_skipped jsonb:='[]'::jsonb; v_courses uuid[]:=array[]::uuid[]; v_n int;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select s.id, s.provider_id into v_source, v_provider from pipeline.sources s
   where s.source_type='provider_fee_schedule' and s.metadata->>'provider_cricos'=upper(btrim(p_provider_cricos))
     and exists(select 1 from pipeline.course_fact_source_qualifications q where q.source_id=s.id and q.qualification_status='qualified' and 'international_fee'=any(q.admitted_domains));
  if v_source is null then raise exception 'no qualified fee schedule source for provider %', p_provider_cricos; end if;
  if coalesce(btrim(p_storage_path),'')='' or p_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'stored schedule file and its SHA-256 are required'; end if;
  select e.id into p_evidence_id from pipeline.evidence_artifacts e where e.source_id=v_source and e.content_hash=p_sha256 limit 1;
  if p_evidence_id is null then
    p_evidence_id:=public.svc_coursefacts_register_evidence(v_source,p_url,p_storage_path,p_sha256,'application/pdf',
      jsonb_build_object('layer',2,'kind','provider_fee_schedule','schedule',p_schedule,'fee_year',p_fee_year,'worker','fee-schedule-etl','decision','Decision 162'));
  end if;
  for r in
    with x as (select upper(btrim(e->>'course_cricos')) code, e->>'title' title, (e->>'amount')::numeric amount from jsonb_array_elements(p_rows) e),
         g as (select code, min(title) title, min(amount) amount, count(distinct amount) amounts from x group by code)
    select g.*, cr.course_id, (select jsonb_build_object('amount',f.amount,'fee_year',f.fee_year) from catalogue.course_fees f
            where f.course_id=cr.course_id and f.fee_type='provider_current_tuition' and coalesce(f.status,'active')='active' order by f.fee_year desc nulls last limit 1) cur
      from g left join catalogue.course_registrations cr on lower(cr.scheme)='cricos' and upper(btrim(cr.registration_code))=g.code
           and exists(select 1 from catalogue.courses c where c.id=cr.course_id and c.provider_id=v_provider and c.lifecycle_status='active')
  loop
    if r.course_id is null then v_skipped:=v_skipped||jsonb_build_object('code',r.code,'reason','not bound'); continue; end if;
    if r.amounts>1 then v_skipped:=v_skipped||jsonb_build_object('code',r.code,'reason','listed twice with different fees'); continue; end if;
    if r.cur is not null and (r.cur->>'fee_year')::int > p_fee_year then v_skipped:=v_skipped||jsonb_build_object('code',r.code,'reason','newer fee year already current'); continue; end if;
    if r.cur is not null and (r.cur->>'fee_year')::int = p_fee_year and (r.cur->>'amount')::numeric<>r.amount then
      v_skipped:=v_skipped||jsonb_build_object('code',r.code,'reason','same fee year, different amount (Layer 4)','schedule',r.amount,'current',r.cur); continue; end if;
    begin
    v_res:=public.svc_coursefacts_apply_record(v_source,p_evidence_id,p_provider_cricos,r.code,p_schedule||':'||r.code||':'||p_fee_year,p_url,p_sha256,
      jsonb_build_object('fee_amount',r.amount,'fee_year',p_fee_year,'fee_basis','annual','currency_code','AUD','audience','international',
        'fee_key',lower(r.code)||':international:'||p_fee_year||':annual','fee_notes','Decision 162 provider fee schedule '||p_schedule||'; annual fee for one full-time year',
        'identity_match',true,'extraction_worker','fee-schedule-etl','course_title_in_schedule',r.title),true);
    exception when others then
      v_skipped:=v_skipped||jsonb_build_object('code',r.code,'reason',left(sqlerrm,200)); continue;
    end;
    v_applied:=v_applied+1; v_courses:=v_courses||r.course_id;
    update catalogue.course_fees f set status='superseded', updated_at=now(),
           notes=coalesce(f.notes,'')||' | superseded by the '||p_fee_year||' provider fee schedule (Decision 132/162) '||to_char(now(),'YYYY-MM-DD')
     where f.course_id=r.course_id and f.fee_type='provider_current_tuition' and coalesce(f.status,'active')='active'
       and f.source_id is distinct from v_source and coalesce(f.fee_year,0)<p_fee_year;
    get diagnostics v_n=row_count; v_super:=v_super+v_n;
  end loop;
  if cardinality(v_courses)>0 then perform search.refresh_course_enrichment_scoped_v1(v_courses,true); end if;
  return jsonb_build_object('applied',v_applied,'superseded_older',v_super,'skipped',jsonb_array_length(v_skipped),'skipped_detail',v_skipped,'source_id',v_source,'evidence_id',p_evidence_id);
end $f$;
revoke all on function public.svc_fee_schedule_apply(text,integer,text,text,text,text,jsonb) from public, anon, authenticated;
grant execute on function public.svc_fee_schedule_apply(text,integer,text,text,text,text,jsonb) to service_role;
