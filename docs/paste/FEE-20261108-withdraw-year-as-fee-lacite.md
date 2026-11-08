# FEE-20261108 paste 1 of 3: withdraw the 65 La Cité collégiale "fees" that are a calendar year, and stop the pattern

PASTE FILE. Run by hand by the Controller or Platform Admin in the SQL editor of `fxcwkweaxjtknorudmwp` (NOT `coursefinder-demo`). Not applied by any migration.
Nothing is deleted. Rollback is the second block, from the before-state recorded in `pipeline.admin_control_events` (batch `FEE-20261108-LACITE`).

## What it fixes (live read-only, 8 Nov 2026 ~03:30 UTC)

- 65 active `provider_current_tuition` rows of La Cité collégiale (provider `5675f806-596a-4982-bd4a-f068e013f974`, CA, international, annual, source "University adapter reading of the course page").
  64 have amount = fee year (CAD 2,022 for 2022, 2,026 for 2026, 2,027 for 2027 ...); 1 is CAD 1,991 (Hygiène dentaire 01175). All written 18 Oct 05:40 UTC.
- Cause: the adapter's `fee` pattern is `Frais d'études.*?\b(\d{3,4}(?:,\d{3})*(?:\.\d{2})?)\b`; it takes the first 3-4 digit number after the label, which is the study year.
  `pipeline.uni_adapters` for this provider has `admit_fields = {delivery, fee}`, `read_cycle_days` null: the rows were never read again.
  3 further rows of the provider are already `unverified` (CAD 2,027): the fee floor (20261023026000) catches the pattern on a re-read, so the pattern is still wrong today.
- Consumers: `api.website_v2_tuition` returns `{amount: 2027, currency: CAD, basis: annual, source: provider_current}` for 53 of these courses (the API only drops amounts under 1,000).
  Zoho reads the same fee through `zoho_edge_*`. After this paste the courses hold no provider fee, so consumers fall back to the registered/other fee or to null (no fabricated price).
- 0 manual locks on these courses. The paste recomputes any scholarship saving built on these fees (as the IQ-00111 paste did).

## Guards (the block refuses and changes nothing unless all hold)

1. exactly 65 rows match; id/amount/year/notes hash = `7245d69736814b5156c22ac60e224624`;
2. no manual lock on these courses; 3. the adapter row exists with `fee` in `admit_fields`.

```sql
begin;
do $paste$
declare
  v_n int; v_h text; r record;
  v_provider uuid := '5675f806-596a-4982-bd4a-f068e013f974';
  v_reason text := 'Withdrawn 8 Nov 2026 (FEE lane, plausibility): the adapter read the study year as the fee. ';
begin
  create temporary table _lc on commit drop as
  select f.* from catalogue.course_fees f join catalogue.courses c on c.id = f.course_id
   where c.provider_id = v_provider and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.basis = 'annual'
     and f.notes like 'University adapter reading of the course page%';
  select count(*), md5(string_agg(id::text || ':' || amount::text || ':' || fee_year::text || ':' || md5(notes), ',' order by id)) into v_n, v_h from _lc;
  if v_n <> 65 or v_h <> '7245d69736814b5156c22ac60e224624' then raise exception 'guard: % rows, hash %; expected 65 rows as measured on 8 Nov 2026; nothing changed', v_n, v_h; end if;
  select count(*) into v_n from pipeline.manual_locks m join _lc t on t.course_id = m.entity_id where m.entity = 'course';
  if v_n <> 0 then raise exception 'guard: % manual locks; nothing changed', v_n; end if;
  if not exists (select 1 from pipeline.uni_adapters a where a.provider_id = v_provider and 'fee' = any(a.admit_fields)) then raise exception 'guard: adapter does not admit fee; nothing changed'; end if;

  for r in select * from _lc loop
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('fees', 'withdraw_paste', 'catalogue.course_fees ' || left(r.id::text, 8),
            jsonb_build_object('batch', 'FEE-20261108-LACITE', 'reason', 'amount is the fee year or a part of one', 'before', to_jsonb(r)), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  select 'fees', 'adapter_admit_paste', 'pipeline.uni_adapters ' || left(a.provider_id::text, 8),
         jsonb_build_object('batch', 'FEE-20261108-LACITE', 'before_admit_fields', to_jsonb(a.admit_fields), 'before_admit_changed_at', a.admit_changed_at), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid
    from pipeline.uni_adapters a where a.provider_id = v_provider;

  update catalogue.course_fees f set status = 'inactive', valid_to = current_date, updated_at = now(), notes = coalesce(f.notes, '') || ' | ' || v_reason
    from _lc t where t.id = f.id and f.status = 'active';
  get diagnostics v_n = row_count;
  if v_n <> 65 then raise exception 'withdrew %, expected 65; rolled back', v_n; end if;
  -- stop the pattern from writing again: the adapter keeps reading delivery, not the fee (the pattern needs a person's fix before fee is admitted again)
  update pipeline.uni_adapters set admit_fields = array_remove(admit_fields, 'fee'), admit_changed_at = now(), updated_at = now(),
         reason = 'FEE lane 8 Nov 2026: fee pattern reads the study year, not the fee (Frais d''études)', updated_by = '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid
   where provider_id = v_provider;

  for r in select course_id from _lc loop perform scholarship.refresh_course_financial_calculations(r.course_id, null); end loop;
  select count(*) into v_n from scholarship.course_financial_calculations fc join _lc t on t.id = fc.course_fee_id;
  if v_n <> 0 then raise exception 'read-back: % scholarship savings still use a withdrawn fee; rolled back', v_n; end if;
  insert into search.refresh_requests(requested_by) values ('FEE-20261108 La Cité year-as-fee');
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'withdraw_paste', 'catalogue.course_fees (65 La Cité adapter rows)', jsonb_build_object('batch', 'FEE-20261108-LACITE', 'fees', 65, 'adapter', 'fee removed from admit_fields'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $paste$;
commit;
```

## Read-back (after the next search refresh, about 10 minutes)

```sql
select count(*) from catalogue.course_fees f join catalogue.courses c on c.id = f.course_id
 where c.provider_id = '5675f806-596a-4982-bd4a-f068e013f974' and f.status = 'active' and f.fee_type = 'provider_current_tuition' and f.amount = trunc(f.amount) and f.amount between 1990 and 2040;  -- expect 0
select count(*) from search.course_documents d join catalogue.courses c on c.id = d.course_id
 where c.provider_id = '5675f806-596a-4982-bd4a-f068e013f974' and d.provider_tuition_options::text ~ '"amount": 20[0-9][0-9]';   -- expect 0
select security.fee_plausibility_check_v1()->'counts'->'fee_amount_is_a_year'->>'count';  -- expect null (no such fee left); run after migration 20261108110000 is live
```

## Rollback

```sql
begin;
do $rb$
declare v_n int;
begin
  select count(*) into v_n from pipeline.admin_control_events e where e.detail->>'batch' = 'FEE-20261108-LACITE' and e.detail ? 'before';
  if v_n <> 65 then raise exception 'guard: % recorded rows, expected 65', v_n; end if;
  update catalogue.course_fees f set status = e.detail->'before'->>'status', valid_to = (e.detail->'before'->>'valid_to')::date, notes = e.detail->'before'->>'notes', updated_at = now()
    from pipeline.admin_control_events e where e.detail->>'batch' = 'FEE-20261108-LACITE' and e.detail ? 'before' and f.id = (e.detail->'before'->>'id')::uuid and f.status = 'inactive';
  get diagnostics v_n = row_count;
  if v_n <> 65 then raise exception 'restored %, expected 65', v_n; end if;
  update pipeline.uni_adapters a set admit_fields = array(select jsonb_array_elements_text(e.detail->'before_admit_fields')), admit_changed_at = (e.detail->>'before_admit_changed_at')::timestamptz, updated_at = now()
    from pipeline.admin_control_events e where e.detail->>'batch' = 'FEE-20261108-LACITE' and e.action = 'adapter_admit_paste' and a.provider_id = '5675f806-596a-4982-bd4a-f068e013f974';
  insert into search.refresh_requests(requested_by) values ('FEE-20261108 La Cité rollback');
end $rb$;
commit;
```

Needs a person afterwards (not in this paste): a corrected `fee` pattern for La Cité's course pages (the tuition is a labelled CAD amount, not the first number after "Frais d'études"), then `fee` back in `admit_fields`. Until then La Cité has no provider fee (genuinely not read), which is the correct "not held".
