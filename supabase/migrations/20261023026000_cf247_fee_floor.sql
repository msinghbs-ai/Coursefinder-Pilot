-- CF-247 (23 Oct 2026). NZ enrichment brief, Release 1 item 4 (Platform Admin decisions C3 and C4 at 20:42; F2 at 20:56).
-- An international fee on an annual basis below the country's floor is quarantined: the row is kept with status unverified (an existing
-- status the website never returns) and a Layer 4
-- item carries the reason; it is not shown until a person decides. Never rejected, never dropped. The floor is a column per country on
-- pipeline.coverage_admission_countries (NZ 8,000 NZD, AU 8,000 AUD, CA 8,000 CAD), shown and changed on Settings › Pipeline settings.
-- The check runs where every fee is admitted (security.coverage_apply_course_v1), so the adapter path, the AI fee reader and the fee
-- schedule actions are all covered; the AI fee reader also records the outcome as review so its figures stay right.
-- C4: the 22 NZ rows below NZ$8,000 (all adapter-read, each the course's only fee row): 20 withdrawn to review, 2 kept live and flagged.
-- F2: NZ-only; the 109 AU and 66 CA rows below the floor stay live until read again (open item O6). Basis check at build: 0 active
-- international fees have a null basis; a null basis is not treated as annual by the floor.
-- Replaces: nothing (security.coverage_apply_course_v1, public.svc_fee_ai_record, public.admin_pipeline_settings_read and
--           public.admin_pipeline_settings_write edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

-- 1 the floor per country ---------------------------------------------------------------------------------------------------------
alter table pipeline.coverage_admission_countries add column min_annual_international numeric check (min_annual_international > 0);
comment on column pipeline.coverage_admission_countries.min_annual_international is 'Floor for an international fee on an annual basis, in the country''s currency; below it the fee is quarantined to Layer 4 (NZ brief C3, 23 Oct 2026). Null: no floor.';
update pipeline.coverage_admission_countries a set min_annual_international = 8000, updated_at = now()
  from ref.countries k where k.id = a.country_id and k.iso_alpha2 in ('NZ', 'AU', 'CA');
insert into pipeline.admin_control_events(area, action, target, detail, actor) values
 ('settings', 'change', 'fee.floor', jsonb_build_object('NZ', 8000, 'AU', 8000, 'CA', 8000, 'reason', 'Platform Admin 23 Oct 2026 20:42: NZ brief C3, quarantine floors (migration 20261023026000)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');

create or replace function security.fee_below_floor_v1(p_course_id uuid, p_amount numeric, p_basis text) returns numeric
 language sql stable security definer set search_path to '' as $f$
  -- the floor when the fee is below it (annual or indicative-annual basis only; a null basis is never checked), else null
  select a.min_annual_international
    from catalogue.courses c join catalogue.providers p on p.id = c.provider_id
    join pipeline.coverage_admission_countries a on a.country_id = p.country_id
   where c.id = p_course_id and p_basis in ('annual', 'indicative_annual') and a.min_annual_international is not null and p_amount < a.min_annual_international
$f$;
revoke execute on function security.fee_below_floor_v1(uuid, numeric, text) from public, anon, authenticated;

-- 2 where every fee is admitted: below the floor, the row is kept as review and a Layer 4 item carries the reason --------------------
select pg_temp.edit_once('security.coverage_apply_course_v1(uuid,uuid,uuid,text,text,jsonb)', '0f3beaac5ed5d4f2ded8a125f569cdfc', array[
  array[$o$declare c record; r jsonb; v_test uuid; v_key text; v_links int := 0; v_intakes int := 0; v_english int := 0; v_fees int := 0; v_cur text;$o$,
        $n$declare c record; r jsonb; v_test uuid; v_key text; v_links int := 0; v_intakes int := 0; v_english int := 0; v_fees int := 0; v_cur text; v_floor numeric;$n$],
  array[$o$    if nullif(p_payload->>'fee_amount', '')::numeric is null or (p_payload->>'fee_amount')::numeric <= 0 then raise exception 'positive fee amount required'; end if;
    insert into catalogue.course_fees($o$,
        $n$    if nullif(p_payload->>'fee_amount', '')::numeric is null or (p_payload->>'fee_amount')::numeric <= 0 then raise exception 'positive fee amount required'; end if;
    -- 23 Oct 2026 (NZ brief C3): below the country floor the fee is quarantined (status review, Layer 4 item), never admitted silently
    v_floor := security.fee_below_floor_v1(p_course_id, (p_payload->>'fee_amount')::numeric, nullif(btrim(p_payload->>'fee_basis'), ''));
    insert into catalogue.course_fees($n$],
  array[$o$            'active', now(), now(), now())
    on conflict (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null
    do update set amount = excluded.amount, currency_code = excluded.currency_code, basis = excluded.basis, fee_year = excluded.fee_year,
                  evidence_id = excluded.evidence_id, confidence = 1, status = 'active', last_verified_at = now(), source_snapshot_at = now(), updated_at = now();
    v_fees := 1;$o$,
        $n$            case when v_floor is not null then 'unverified' else 'active' end, now(), now(), now())
    on conflict (course_id, source_id, source_fee_key) where source_id is not null and source_fee_key is not null
    do update set amount = excluded.amount, currency_code = excluded.currency_code, basis = excluded.basis, fee_year = excluded.fee_year,
                  evidence_id = excluded.evidence_id, confidence = 1, status = case when v_floor is not null then 'unverified' else 'active' end, last_verified_at = now(), source_snapshot_at = now(), updated_at = now();
    if v_floor is not null then
      if not exists (select 1 from pipeline.layer4_review_items l where l.entity_type = 'course' and l.entity_id = p_course_id and l.field_code = 'provider_current_tuition' and l.status = 'pending') then
        insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
        values ('course', p_course_id, 'provider_current_tuition', p_evidence_id, null,
                jsonb_build_object('amount', (p_payload->>'fee_amount')::numeric, 'currency', v_cur, 'basis', nullif(btrim(p_payload->>'fee_basis'), ''), 'page', p_url),
                jsonb_build_object('page', p_url, 'source', 'fee floor', 'state', 'quarantined'), '{}'::jsonb, 'pending',
                'international fee below the country floor (' || v_cur || ' ' || to_char(v_floor, 'FM999,999,999') || ' a year): ' || v_cur || ' ' || to_char((p_payload->>'fee_amount')::numeric, 'FM999,999,999.00'),
                'CF-CHG-20260915-247 NZ brief C3');
      end if;
      v_fees := 0;
    else
      v_fees := 1;
    end if;$n$],
  array[$o$'english_applied', v_english, 'fees_applied', v_fees);$o$,
        $n$'english_applied', v_english, 'fees_applied', v_fees, 'fee_quarantined', v_floor is not null);$n$]]);

-- 3 the AI fee reader records a below-floor fee as review (the apply above keeps the row quarantined either way)
select pg_temp.edit_once('public.svc_fee_ai_record(uuid,jsonb,numeric,text)', '87f3a16a63d691b3195ee1ab857fe7c7', array[
  array[$o$        when c.conf >= v_min_conf and coalesce(c.sim, 0) >= v_min_sim and (v_median is null or c.yearly between v_median / v_ratio and v_median * v_ratio)$o$,
        $n$        when security.fee_below_floor_v1(c.course_id, c.yearly, coalesce(c.basis, 'annual')) is not null then 'review'  -- 23 Oct 2026 (NZ brief C3): below the country floor
        when c.conf >= v_min_conf and coalesce(c.sim, 0) >= v_min_sim and (v_median is null or c.yearly between v_median / v_ratio and v_median * v_ratio)$n$],
  array[$o$        else 'review' end;
      if v_outcome = 'admitted' then$o$,
        $n$        else 'review' end;
      if v_outcome = 'review' and security.fee_below_floor_v1(c.course_id, c.yearly, coalesce(c.basis, 'annual')) is not null then
        v_note := v_note || '; international fee below the country floor (' || v_cur || ' ' || to_char(security.fee_below_floor_v1(c.course_id, c.yearly, coalesce(c.basis, 'annual')), 'FM999,999,999') || ' a year)';
      end if;
      if v_outcome = 'admitted' then$n$]]);

-- 4 Settings › Pipeline settings: the floor on the country row, changed with a reason (logged) -----------------------------------------
select pg_temp.edit_once('public.admin_pipeline_settings_read()', '6a192ef1a9dda96193847745663c3539', array[
  array[$o$jsonb_build_object('active', c.active, 'currency', c.currency_code, 'identities', c.identities, 'approved_ref', c.approved_ref))$o$,
        $n$jsonb_build_object('active', c.active, 'currency', c.currency_code, 'identities', c.identities, 'approved_ref', c.approved_ref, 'min_annual_international', c.min_annual_international))$n$]]);
select pg_temp.edit_once('public.admin_pipeline_settings_write(text,jsonb)', '35e8ff42fa934f0e9b46c9a5b0b5e543', array[
  array[$o$    else raise exception 'unknown setting %', p_key;$o$,
        $n$    -- 23 Oct 2026 (NZ brief C3): the international fee floor per country, in its currency; null switches the floor off
    when 'fee.floor' then
      if p_value->>'value' is not null and ((p_value->>'value')::numeric <= 0 or (p_value->>'value')::numeric > 200000) then raise exception 'between 1 and 200,000, or empty for no floor'; end if;
      update pipeline.coverage_admission_countries c
         set min_annual_international = nullif(p_value->>'value', '')::numeric, updated_at = now(),
             approved_ref = c.approved_ref || format('; Settings page, Platform Admin %s (fee floor: %s)', to_char(now() at time zone 'Australia/Melbourne', 'DD Mon YYYY HH24:MI'), coalesce(p_value->>'value', 'none'))
        from ref.countries k where k.id = c.country_id and k.iso_alpha2 = p_value->>'country';
      if not found then raise exception 'country % not found', p_value->>'country'; end if;
    else raise exception 'unknown setting %', p_key;$n$]]);

-- 5 C4: the 22 NZ rows below NZ$8,000 -----------------------------------------------------------------------------------------------
create temp table _floor on commit drop as
select f.id, f.course_id, p.canonical_name provider, c.canonical_title course, f.amount, f.evidence_id, f.currency_code
  from catalogue.course_fees f join catalogue.courses c on c.id = f.course_id join catalogue.providers p on p.id = c.provider_id
  join ref.countries k on k.id = p.country_id
 where k.iso_alpha2 = 'NZ' and f.audience = 'international' and f.status = 'active' and f.basis = 'annual' and f.amount < 8000;
do $d$ declare v int; begin
  select count(*) into v from _floor; if v <> 22 then raise exception 'expected 22 NZ rows below the floor, found %', v; end if;
end $d$;
-- keep live, flagged (2): short English-language certificates, plausible
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
select 'course', x.course_id, 'provider_current_tuition', x.evidence_id, jsonb_build_object('amount', x.amount, 'status', 'active'), jsonb_build_object('amount', x.amount, 'status', 'active'), jsonb_build_object('source', 'fee floor', 'state', 'flagged'), '{}'::jsonb, 'pending',
       'international fee below the country floor (NZD 8,000 a year); kept live and flagged: short English-language course (Platform Admin 23 Oct 2026 C4)', 'CF-CHG-20260915-247 NZ brief C4'
  from _floor x where x.provider in ('New Zealand College of Chinese Medicine Limited', 'University of Waikato');
-- withdraw to review (20): off the website until decided; restored on approval
update catalogue.course_fees f set status = 'unverified', updated_at = now()
  from _floor x where f.id = x.id and x.provider not in ('New Zealand College of Chinese Medicine Limited', 'University of Waikato');
insert into pipeline.layer4_review_items(entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, layer3_state, status, escalation_reason, change_control_ref)
select 'course', x.course_id, 'provider_current_tuition', x.evidence_id, jsonb_build_object('amount', x.amount, 'status', 'active'), jsonb_build_object('amount', x.amount, 'status', 'unverified'), jsonb_build_object('source', 'fee floor', 'state', 'withdrawn'), '{}'::jsonb, 'pending',
       'withdrawn to review: international fee below the country floor (NZD 8,000 a year): NZD ' || to_char(x.amount, 'FM999,999,999.00') || ' (Platform Admin 23 Oct 2026 C4)', 'CF-CHG-20260915-247 NZ brief C4'
  from _floor x where x.provider not in ('New Zealand College of Chinese Medicine Limited', 'University of Waikato');
insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('layer4', 'fee_floor_pass', 'NZ', jsonb_build_object('withdrawn', 20, 'kept_flagged', 2, 'reason', 'Platform Admin 23 Oct 2026 20:42: NZ brief C4 (migration 20261023026000)'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
insert into search.refresh_requests(requested_by) select 'Fee floor pass (NZ)'
 where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'Fee floor pass (NZ)');

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.fee_below_floor_v1', 'Layer 2', 'The country floor an international annual fee falls below, else null (quarantine)', 'active', '{}', '20261023026000')
on conflict (kind, name) do nothing;

select 'fee floor per country; below-floor fees quarantined; C4 pass applied' ok;
