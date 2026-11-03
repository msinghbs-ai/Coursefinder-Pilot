CREATE OR REPLACE FUNCTION security.layer4_tuition_apply_impl(p_actor uuid, p_item_id uuid, p_value jsonb, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'search', 'ref'
AS $function$
declare v_item pipeline.layer4_review_items%rowtype; v_code text; v_source uuid; v_amount numeric; v_cur text; v_basis text; v_year int; v_aud text; v_key text; v_fee uuid;
begin
  select * into v_item from pipeline.layer4_review_items where id=p_item_id;
  if v_item.entity_type<>'course' then raise exception 'tuition decisions apply to courses only'; end if;
  -- Plain Approve: use the item's proposed value, otherwise the AI's answer on the Layer 3 result.
  if p_value is null or jsonb_typeof(p_value)<>'object' then
    p_value := coalesce(case when jsonb_typeof(v_item.proposed_value)='object' then v_item.proposed_value end,
      (select case when jsonb_typeof(i.candidate_value)='object' then i.candidate_value end from pipeline.layer3_interpretations i where i.id=v_item.layer3_interpretation_id));
  end if;
  if p_value is null or jsonb_typeof(p_value)<>'object' then raise exception 'there is no fee to approve; use Edit and approve to enter it'; end if;
  v_amount := nullif(p_value->>'amount','')::numeric;
  v_cur := upper(nullif(btrim(coalesce(p_value->>'currency_code',p_value->>'currency')),''));
  v_basis := lower(nullif(btrim(p_value->>'basis'),''));
  v_year := nullif(p_value->>'fee_year','')::int;
  v_aud := lower(coalesce(nullif(btrim(p_value->>'audience'),''),'international'));
  if v_amount is null or v_amount<=0 then raise exception 'fee amount must be greater than 0'; end if;
  if v_cur not in ('AUD','NZD','CAD') then raise exception 'currency must be AUD, NZD or CAD'; end if;
  if v_basis not in ('annual','indicative_annual','per_year_explicit') then raise exception 'fee must be charged per year to approve (basis annual or indicative_annual)'; end if;
  if v_year is not null and (v_year<2024 or v_year>2030) then raise exception 'fee year must be between 2024 and 2030'; end if;
  if v_aud<>'international' then raise exception 'only international tuition fees are recorded here'; end if;
  select course_code into v_code from catalogue.courses where id=v_item.entity_id;
  if v_code is null then raise exception 'course code unavailable'; end if;
  select source_id into v_source from pipeline.evidence_artifacts where id=v_item.evidence_id;
  if v_source is null then raise exception 'the review item has no Evidence source'; end if;
  v_key := lower(upper(btrim(v_code))||':'||v_aud||':'||coalesce(v_year::text,'current')||':'||v_basis);
  insert into catalogue.course_fees(course_id,fee_year,audience,fee_type,amount,currency_code,basis,notes,source_id,evidence_id,confidence,campus_id,source_fee_key,status,last_verified_at,source_snapshot_at,updated_at)
  values (v_item.entity_id,v_year,v_aud,'provider_current_tuition',v_amount,v_cur,v_basis,
          format('CF-247 Layer 4 human decision; review item %s; %s',v_item.id,left(trim(p_reason),200)),
          v_source,v_item.evidence_id,1,null,v_key,'active',now(),now(),now())
  on conflict(course_id,source_id,source_fee_key) where source_id is not null and source_fee_key is not null
  do update set amount=excluded.amount,currency_code=excluded.currency_code,basis=excluded.basis,fee_year=excluded.fee_year,
                notes=excluded.notes,evidence_id=excluded.evidence_id,confidence=1,status='active',last_verified_at=now(),updated_at=now()
  returning id into v_fee;
  perform search.refresh_course_enrichment_scoped_v1(array[v_item.entity_id], true);
  return jsonb_build_object('course_fee_id',v_fee,'fee_key',v_key,'search_refreshed',true);
end $function$
