-- CF-115 — structured Scholarship award values and auditable Course financial calculations.

alter table scholarship.scholarships
  add column if not exists award_value_type text,
  add column if not exists award_percentage numeric(7,4),
  add column if not exists award_amount numeric(14,2),
  add column if not exists award_currency_code char(3),
  add column if not exists award_applies_to_fee_type text,
  add column if not exists award_fee_basis text,
  add column if not exists award_duration_basis text;

alter table scholarship.scholarships drop constraint if exists scholarships_award_value_type_check;
alter table scholarship.scholarships add constraint scholarships_award_value_type_check check (award_value_type is null or award_value_type in ('percentage','fixed_amount','text_only'));
alter table scholarship.scholarships drop constraint if exists scholarships_award_percentage_check;
alter table scholarship.scholarships add constraint scholarships_award_percentage_check check (award_percentage is null or (award_percentage > 0 and award_percentage <= 100));

comment on column scholarship.scholarships.award_percentage is 'Published scholarship percentage, e.g. 20 means 20%. Never inferred from a monetary value.';
comment on column scholarship.scholarships.award_applies_to_fee_type is 'Exact catalogue.course_fees.fee_type used only when verified by first-party evidence.';
comment on column scholarship.scholarships.award_fee_basis is 'Expected Course fee basis for deterministic calculation. Null means calculation unresolved.';
comment on column scholarship.scholarships.award_duration_basis is 'Duration semantics such as first_year, annual_while_eligible, or full_course.';

update scholarship.scholarships
set award_value_type='percentage', award_percentage=(regexp_match(trim(award_value_text),'^([0-9]+(?:\.[0-9]+)?)%$'))[1]::numeric
where award_value_type is null and award_value_text ~ '^\s*[0-9]+(?:\.[0-9]+)?%\s*$';
update scholarship.scholarships set award_value_type='text_only' where award_value_type is null and award_value_text is not null;

create table if not exists scholarship.course_financial_calculations (
  id uuid primary key default gen_random_uuid(), mapping_id uuid not null references scholarship.course_mappings(id) on delete cascade,
  scholarship_id uuid not null references scholarship.scholarships(id) on delete cascade, course_id uuid not null references catalogue.courses(id) on delete cascade,
  course_fee_id uuid references catalogue.course_fees(id) on delete set null, calculation_status text not null,
  award_value_type text, award_percentage numeric(7,4), award_amount numeric(14,2), currency_code char(3), fee_amount numeric(14,2),
  fee_type text, fee_basis text, fee_year integer, scholarship_saving_amount numeric(14,2), net_fee_amount numeric(14,2),
  calculation_formula text, calculation_reason text, scholarship_evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  fee_evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null, calculated_at timestamptz not null default now(), metadata jsonb not null default '{}'::jsonb,
  unique(mapping_id)
);
alter table scholarship.course_financial_calculations enable row level security;
revoke all on scholarship.course_financial_calculations from public, anon, authenticated;
grant select,insert,update,delete on scholarship.course_financial_calculations to service_role;
alter table scholarship.course_financial_calculations drop constraint if exists course_financial_calculations_status_check;
alter table scholarship.course_financial_calculations add constraint course_financial_calculations_status_check check (calculation_status in ('calculated','award_not_structured','award_scope_unresolved','fee_not_found','fee_ambiguous','currency_mismatch','not_applicable'));
create index if not exists course_financial_calculations_course_idx on scholarship.course_financial_calculations(course_id,calculation_status);
create index if not exists course_financial_calculations_scholarship_idx on scholarship.course_financial_calculations(scholarship_id,calculation_status);

create or replace function scholarship.refresh_course_financial_calculation(p_mapping_id uuid)
returns scholarship.course_financial_calculations language plpgsql security definer
set search_path='pg_catalog','scholarship','catalogue','pipeline' as $$
declare v_map scholarship.course_mappings%rowtype; v_s scholarship.scholarships%rowtype; v_fee catalogue.course_fees%rowtype; v_fee_count integer:=0; v_status text; v_reason text; v_saving numeric(14,2); v_net numeric(14,2); v_formula text; v_result scholarship.course_financial_calculations%rowtype;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into v_map from scholarship.course_mappings where id=p_mapping_id; if not found then raise exception 'mapping not found' using errcode='22023'; end if;
 select * into v_s from scholarship.scholarships where id=v_map.scholarship_id;
 if v_s.award_value_type is distinct from 'percentage' or v_s.award_percentage is null then v_status:='award_not_structured'; v_reason:='Percentage calculation requires a structured award_percentage.';
 elsif v_s.award_applies_to_fee_type is null or v_s.award_fee_basis is null then v_status:='award_scope_unresolved'; v_reason:='Published percentage is retained, but the authoritative fee type/basis has not been verified.';
 else
  select count(*) into v_fee_count from catalogue.course_fees f where f.course_id=v_map.course_id and f.audience='international' and f.fee_type=v_s.award_applies_to_fee_type and f.basis=v_s.award_fee_basis and f.amount is not null and (v_s.academic_year is null or f.fee_year=v_s.academic_year) and coalesce(f.status,'active') not in ('inactive','retired','superseded');
  if v_fee_count=0 then v_status:='fee_not_found'; v_reason:='No Course fee row exactly matches the Scholarship fee type, basis and year.';
  elsif v_fee_count>1 then v_status:='fee_ambiguous'; v_reason:='Multiple Course fee rows match; a specific fee row must be resolved before calculation.';
  else
   select * into v_fee from catalogue.course_fees f where f.course_id=v_map.course_id and f.audience='international' and f.fee_type=v_s.award_applies_to_fee_type and f.basis=v_s.award_fee_basis and f.amount is not null and (v_s.academic_year is null or f.fee_year=v_s.academic_year) and coalesce(f.status,'active') not in ('inactive','retired','superseded') limit 1;
   if v_s.award_currency_code is not null and v_s.award_currency_code<>v_fee.currency_code then v_status:='currency_mismatch'; v_reason:='Scholarship and Course fee currencies differ.';
   else v_saving:=round(v_fee.amount*(v_s.award_percentage/100.0),2); v_net:=round(v_fee.amount-v_saving,2); v_formula:='fee_amount * (award_percentage / 100)'; v_status:='calculated'; v_reason:='Calculated from the exact governed Course fee row matching Scholarship fee type, basis and year.'; end if;
  end if;
 end if;
 insert into scholarship.course_financial_calculations(mapping_id,scholarship_id,course_id,course_fee_id,calculation_status,award_value_type,award_percentage,award_amount,currency_code,fee_amount,fee_type,fee_basis,fee_year,scholarship_saving_amount,net_fee_amount,calculation_formula,calculation_reason,scholarship_evidence_id,fee_evidence_id,calculated_at,metadata)
 values(v_map.id,v_s.id,v_map.course_id,v_fee.id,v_status,v_s.award_value_type,v_s.award_percentage,v_s.award_amount,coalesce(v_s.award_currency_code,v_fee.currency_code),v_fee.amount,v_fee.fee_type,v_fee.basis,v_fee.fee_year,v_saving,v_net,v_formula,v_reason,coalesce(v_map.evidence_id,v_s.evidence_id),v_fee.evidence_id,now(),jsonb_build_object('award_duration_basis',v_s.award_duration_basis,'academic_year',v_s.academic_year))
 on conflict(mapping_id) do update set scholarship_id=excluded.scholarship_id,course_id=excluded.course_id,course_fee_id=excluded.course_fee_id,calculation_status=excluded.calculation_status,award_value_type=excluded.award_value_type,award_percentage=excluded.award_percentage,award_amount=excluded.award_amount,currency_code=excluded.currency_code,fee_amount=excluded.fee_amount,fee_type=excluded.fee_type,fee_basis=excluded.fee_basis,fee_year=excluded.fee_year,scholarship_saving_amount=excluded.scholarship_saving_amount,net_fee_amount=excluded.net_fee_amount,calculation_formula=excluded.calculation_formula,calculation_reason=excluded.calculation_reason,scholarship_evidence_id=excluded.scholarship_evidence_id,fee_evidence_id=excluded.fee_evidence_id,calculated_at=excluded.calculated_at,metadata=excluded.metadata returning * into v_result;
 return v_result;
end $$;
revoke all on function scholarship.refresh_course_financial_calculation(uuid) from public,anon,authenticated;
grant execute on function scholarship.refresh_course_financial_calculation(uuid) to service_role;
