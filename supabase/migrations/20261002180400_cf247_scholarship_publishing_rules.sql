-- CF-247 (Decision 212, 2 Oct 2026): scholarship publishing rules after Decision 211.
-- Platform Admin answers (2 Oct, multiple choice):
--   * domestic-only scholarships: "Add publishing check" - a scholarship whose provider page lists domestic students only
--     is not published (the daily review withdraws one already published); a Platform Admin can confirm that
--     international students can apply when the reading is wrong (Scholarships › Publishing › Domestic only);
--   * "up to" values: "Publish as 'Up to'" - one stated maximum amount or percentage is recorded and shown as "Up to ...",
--     and never used to work out a fee saving;
--   * fee savings: "Fix" - a percentage off tuition fees is worked out per year from the provider's annual international
--     tuition fee for the course (the latest year, or the scholarship's year when it states one).
-- Measured before: 251 scholarships read as domestic only (18 ready to publish, 1 published); 76 held back only by a single
-- "up to" value; 503 fee-saving rows, all unresolved (the scholarship and fee records used different words).
-- Every function edit is behind an md5 guard. No rows deleted.

-- 1. "up to" values
alter table scholarship.scholarships add column if not exists award_value_is_maximum boolean not null default false;
comment on column scholarship.scholarships.award_value_is_maximum is
  'Decision 212: the stated value is a maximum ("up to"); shown as "Up to ..." and never used for a fee saving.';

do $m$
declare s text; d text; v text;
  o text := E'  return v_changes;\nend';
  n text := $n$  -- Decision 212: one stated maximum ("up to $5,000", "up to 50%") is recorded as a maximum, only where the record has no value
  declare v_val jsonb := pg.facts->'value'; na int; np int; amt numeric; pct numeric;
  begin
    if not (s.award_value_type in ('percentage','fixed_amount') and coalesce(s.award_percentage, s.award_amount) is not null)
       and v_val->>'type' = 'ambiguous' and coalesce((v_val->>'up_to')::boolean, false) and not coalesce((v_val->>'foreign_currency')::boolean, false) then
      na := jsonb_array_length(case when jsonb_typeof(v_val->'amounts') = 'array' then v_val->'amounts' else '[]' end);
      np := jsonb_array_length(case when jsonb_typeof(v_val->'percentages') = 'array' then v_val->'percentages' else '[]' end);
      amt := case when na = 1 and np = 0 then (v_val->'amounts'->>0)::numeric end;
      pct := case when np = 1 and na = 0 then (v_val->'percentages'->>0)::numeric end;
      if amt between 500 and 200000 then
        update scholarship.scholarships set award_value_type = 'fixed_amount', award_amount = amt, award_currency_code = 'AUD', award_value_is_maximum = true,
               award_value_text = coalesce(award_value_text, 'Up to A$' || to_char(amt, 'FM999,999,999')), evidence_id = pg.evidence_id, updated_at = now()
         where id = s.id;
      elsif pct between 5 and 100 then
        update scholarship.scholarships set award_value_type = 'percentage', award_percentage = pct, award_value_is_maximum = true,
               award_applies_to_fee_type = case when coalesce(pg.facts->'award_scope'->'applies_to', '[]') ? 'tuition_fee' then coalesce(award_applies_to_fee_type, 'tuition_fee') else award_applies_to_fee_type end,
               award_value_text = coalesce(award_value_text, 'Up to ' || pct::text || '%' || case when coalesce(pg.facts->'award_scope'->'applies_to', '[]') ? 'tuition_fee' then ' of tuition fees' else '' end),
               evidence_id = pg.evidence_id, updated_at = now()
         where id = s.id;
      end if;
      if amt between 500 and 200000 or pct between 5 and 100 then
        insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
        values (s.id, 'award_value_maximum', jsonb_build_object('type', s.award_value_type, 'text', s.award_value_text), v_val, pg.evidence_id);
        v_changes := v_changes || 'award_value_maximum'::text;
      end if;
    end if;
  exception when others then null; -- a value locked by hand is left as it is
  end;

  return v_changes;
end$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'scholarship_criteria_apply_v1';
  v := md5(s);
  if v is distinct from '7a890c3c293159532a7dee6a660ddc8c' then raise exception 'scholarship_criteria_apply_v1 changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'final return not found once'; end if;
  execute replace(d, o, n);
end $m$;

-- 2. domestic-only scholarships are not published unless a person confirms international students can apply
do $p$
declare s text; d text; v text;
  o text := $o$        case when s.evidence_id is null then 'no evidence' end,$o$;
  n text := $n$        case when exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type'
                                and cr.value_json->>'by'='scholarship_sweep' and cr.value_codes='{domestic}')
              and not exists (select 1 from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type'
                                and coalesce(cr.value_json->>'by','')<>'scholarship_sweep' and 'international'=any(cr.value_codes))
             then 'eligibility lists domestic students only' end,
        case when s.evidence_id is null then 'no evidence' end,$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'scholarship_publishability_v1';
  v := md5(s);
  if v is distinct from 'a287876beb1ce510cb7026b5b2edfb47' then raise exception 'scholarship_publishability_v1 changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'evidence check not found once'; end if;
  execute replace(d, o, n);
end $p$;

-- 2a. Platform Admin: "International students can apply" (a note is required; recorded as a person's criterion)
do $a$
declare s text; d text; v text;
  o text := $o$  else raise exception 'unknown action'; end if;$o$;
  n text := $n$  elsif p_action='confirm_international' then
    if coalesce(btrim(p_args->>'note'),'')='' then raise exception 'a note is required'; end if;
    insert into scholarship.criteria(scholarship_id,criterion_type,operator,value_codes,value_json,human_text,is_mandatory,machine_evaluable,status,confidence)
    values (v_id,'student_type','in',array['international'],jsonb_build_object('by','person','actor',auth.uid(),'decision','Decision 212'),left(btrim(p_args->>'note'),300),true,true,'active',1);
  else raise exception 'unknown action'; end if;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_scholarship_publishing_v1';
  v := md5(s);
  if v is distinct from '940e8fde94883ad072f4f1ca8d28cfe6' then raise exception 'admin_scholarship_publishing_v1 changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'unknown-action line not found once'; end if;
  execute replace(d, o, n);
end $a$;

-- 2b. Publishing read: domestic-only list and count; "Up to" values
do $r$
declare s text; d text; v text; i int;
  o1 text := $o$'held',(select count(*) from pipeline.scholarship_publication_holds where released_at is null),$o$;
  n1 text := $n$'held',(select count(*) from pipeline.scholarship_publication_holds where released_at is null),
       'domestic_only',(select count(*) from p join scholarship.scholarships s on s.id=p.scholarship_id where s.lifecycle_status='active' and 'eligibility lists domestic students only'=any(p.missing)),$n$;
  o2 text := $o$'value',case s.award_value_type$o$;
  n2 text := $n$'value',case when s.award_value_is_maximum then 'Up to ' else '' end||case s.award_value_type$n$;
  o3 text := $o$    'held',(select coalesce(jsonb_agg($o$;
  n3 text := $n$    'domestic_only',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'provider',coalesce(pr.display_name,pr.canonical_name),'page',s.source_url,
         'published',s.publication_status='published',
         'words',(select left(cr.human_text,240) from scholarship.criteria cr where cr.scholarship_id=s.id and cr.status='active' and cr.criterion_type='student_type' and cr.value_json->>'by'='scholarship_sweep' limit 1))
         order by coalesce(pr.display_name,pr.canonical_name),s.name),'[]'::jsonb)
       from p join scholarship.scholarships s on s.id=p.scholarship_id left join catalogue.providers pr on pr.id=s.provider_id
      where s.lifecycle_status='active' and 'eligibility lists domestic students only'=any(p.missing)),
    'held',(select coalesce(jsonb_agg($n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_scholarship_publishing_read_v1';
  v := md5(s);
  if v is distinct from 'a3ae9776e28279555f84a6c289aa030a' then raise exception 'admin_scholarship_publishing_read_v1 changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'held count not found once'; end if;
  if (length(d) - length(replace(d, o2, ''))) / length(o2) <> 1 then raise exception 'value expression not found once'; end if;
  if (length(d) - length(replace(d, o3, ''))) / length(o3) <> 1 then raise exception 'held list not found once'; end if;
  execute replace(replace(replace(d, o1, n1), o2, n2), o3, n3);
end $r$;

-- 2c. Website search: the value is marked as a maximum (additive field)
do $w$
declare s text; d text; v text;
  o text := $o$'amount_note',p.award_value_text,$o$;
  n text := $n$'amount_note',p.award_value_text,
      'amount_is_maximum',p.award_value_is_maximum,$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'website_edge_scholarship_search_v1';
  v := md5(s);
  if v is distinct from 'ec3b3087e53ef02f76097ed7a6bd6dd5' then raise exception 'website_edge_scholarship_search_v1 changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'amount note not found once'; end if;
  execute replace(d, o, n);
end $w$;

-- 3. fee savings: per year, from the provider's annual international tuition fee
do $c$
declare v text;
begin
  select md5(p.prosrc) into v from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'scholarship' and p.proname = 'refresh_course_financial_calculation';
  if v is distinct from '0fc45dcbde2d72d11160f5c0a9b43864' then raise exception 'refresh_course_financial_calculation changed (md5 %); not replacing', v; end if;
end $c$;

create or replace function scholarship.refresh_course_financial_calculation(p_mapping_id uuid)
 returns scholarship.course_financial_calculations
 language plpgsql security definer
 set search_path to 'pg_catalog', 'scholarship', 'catalogue', 'pipeline'
as $function$
declare
  v_map scholarship.course_mappings%rowtype;
  v_s scholarship.scholarships%rowtype;
  v_fee catalogue.course_fees%rowtype;
  v_status text;
  v_reason text;
  v_saving numeric(14,2);
  v_net numeric(14,2);
  v_formula text;
  v_result scholarship.course_financial_calculations%rowtype;
begin
  if current_user not in ('service_role','postgres') then
    raise exception 'service_role required' using errcode='42501';
  end if;
  select * into v_map from scholarship.course_mappings where id=p_mapping_id;
  if not found then raise exception 'mapping not found' using errcode='22023'; end if;
  select * into v_s from scholarship.scholarships where id=v_map.scholarship_id;

  if v_s.award_value_type is distinct from 'percentage' or v_s.award_percentage is null then
    v_status:='award_not_structured'; v_reason:='Percentage calculation requires a structured award_percentage.';
  elsif v_s.award_value_is_maximum then
    v_status:='award_not_structured'; v_reason:='The award is a maximum ("up to"); no saving is worked out.';
  elsif v_s.award_applies_to_fee_type is distinct from 'tuition_fee' then
    v_status:='award_scope_unresolved'; v_reason:='The provider page does not say the percentage is off tuition fees.';
  else
    -- Decision 212: the provider's annual international tuition fee for the course; the scholarship's year when it
    -- states one, otherwise the latest year recorded
    select f.* into v_fee from catalogue.course_fees f
     where f.course_id=v_map.course_id and f.audience='international' and f.fee_type='provider_current_tuition'
       and f.basis in ('annual','indicative_annual','current indicative annual international tuition')
       and f.amount > 0 and coalesce(f.status,'active') not in ('inactive','retired','superseded')
       and (v_s.academic_year is null or f.fee_year is null or f.fee_year=v_s.academic_year)
     order by (f.fee_year is not distinct from v_s.academic_year) desc, f.fee_year desc nulls last, f.updated_at desc nulls last
     limit 1;
    if v_fee.id is null then
      v_status:='fee_not_found'; v_reason:='No annual international tuition fee is recorded for this course.';
    elsif exists (select 1 from catalogue.course_fees f where f.course_id=v_map.course_id and f.id<>v_fee.id and f.audience='international'
                    and f.fee_type='provider_current_tuition' and f.basis in ('annual','indicative_annual','current indicative annual international tuition')
                    and f.amount > 0 and coalesce(f.status,'active') not in ('inactive','retired','superseded')
                    and f.fee_year is not distinct from v_fee.fee_year and f.amount<>v_fee.amount) then
      v_fee:=null; v_status:='fee_ambiguous'; v_reason:='More than one annual tuition fee is recorded for the same year; a person must settle which applies.';
    elsif v_s.award_currency_code is not null and v_s.award_currency_code<>v_fee.currency_code then
      v_status:='currency_mismatch'; v_reason:='Scholarship and Course fee currencies differ.';
    else
      v_saving:=round(v_fee.amount*(v_s.award_percentage/100.0),2);
      v_net:=round(v_fee.amount-v_saving,2);
      v_formula:='annual tuition fee * (award_percentage / 100), per year';
      v_status:='calculated';
      v_reason:='Per-year saving from the provider''s annual international tuition fee'||coalesce(' for '||v_fee.fee_year,'')||'.';
    end if;
  end if;

  insert into scholarship.course_financial_calculations(
    mapping_id,scholarship_id,course_id,course_fee_id,calculation_status,
    award_value_type,award_percentage,award_amount,currency_code,fee_amount,fee_type,fee_basis,fee_year,
    scholarship_saving_amount,net_fee_amount,calculation_formula,calculation_reason,
    scholarship_evidence_id,fee_evidence_id,calculated_at,metadata)
  values(
    v_map.id,v_s.id,v_map.course_id,v_fee.id,v_status,
    v_s.award_value_type,v_s.award_percentage,v_s.award_amount,coalesce(v_s.award_currency_code,v_fee.currency_code),v_fee.amount,v_fee.fee_type,
    case when v_fee.id is not null then 'annual' end,v_fee.fee_year,
    v_saving,v_net,v_formula,v_reason,coalesce(v_map.evidence_id,v_s.evidence_id),v_fee.evidence_id,now(),
    jsonb_build_object('award_duration_basis',v_s.award_duration_basis,'academic_year',v_s.academic_year,'fee_basis_recorded',v_fee.basis,'decision','Decision 212'))
  on conflict(mapping_id) do update set
    scholarship_id=excluded.scholarship_id,course_id=excluded.course_id,course_fee_id=excluded.course_fee_id,
    calculation_status=excluded.calculation_status,award_value_type=excluded.award_value_type,
    award_percentage=excluded.award_percentage,award_amount=excluded.award_amount,currency_code=excluded.currency_code,
    fee_amount=excluded.fee_amount,fee_type=excluded.fee_type,fee_basis=excluded.fee_basis,fee_year=excluded.fee_year,
    scholarship_saving_amount=excluded.scholarship_saving_amount,net_fee_amount=excluded.net_fee_amount,
    calculation_formula=excluded.calculation_formula,calculation_reason=excluded.calculation_reason,
    scholarship_evidence_id=excluded.scholarship_evidence_id,fee_evidence_id=excluded.fee_evidence_id,
    calculated_at=excluded.calculated_at,metadata=excluded.metadata
  returning * into v_result;
  return v_result;
end $function$;

-- 3a. course record: the saving says it is per year
do $s$
declare s text; d text; v text;
  o text := $o$concat('Saving ',trim(fc.currency_code::text),' ',to_char(fc.scholarship_saving_amount,'FM999G999G999G990D00')),
        concat('Net fee ',trim(fc.currency_code::text),' ',to_char(fc.net_fee_amount,'FM999G999G999G990D00')))$o$;
  n text := $n$concat('Saving ',trim(fc.currency_code::text),' ',to_char(fc.scholarship_saving_amount,'FM999G999G999G990D00'),case when fc.fee_basis='annual' then ' a year'||coalesce(' ('||fc.fee_year||' fee)','') end),
        concat('Net fee ',trim(fc.currency_code::text),' ',to_char(fc.net_fee_amount,'FM999G999G999G990D00'),case when fc.fee_basis='annual' then ' a year' end))$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_course_scholarships';
  v := md5(s);
  if v is distinct from '65fc940ff02813c2eb229c2f8f9ad7a1' then raise exception 'admin_course_scholarships changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'saving text not found once'; end if;
  execute replace(d, o, n);
end $s$;

-- 3b. savings follow fee and scholarship changes: refreshed daily (06:41 Melbourne)
select cron.schedule('scholarship-savings', '41 20 * * *', $$select scholarship.refresh_course_financial_calculations(null, null)$$);
