# FEE-20261108 paste 3 of 3: supersede 53 pending fee checks that repeat a question a person already answered (IQ-00040)

PASTE FILE, same rules as paste 1. A person's decision is not changed; items are only closed as `superseded` with the reason, exactly as `security.layer4_tuition_settle_v1` closes duplicates (Decision 224).
Measured 8 Nov 2026 ~03:30 UTC: 53 pending `provider_current_tuition_validation` items (of 136) were created after a person decided the same course AND propose the same amount (52 follow a rejection, 1 an approval/edit),
decided within the last 90 days (`fees.decision_memory_days`). Item id hash `6ad6722331a096c89d7457daddf5e565`. The other 3 pending items created after a decision propose a different amount and stay.
Run after migration 20261108111000 is live and `fees.respect_decisions_on` is switched on, so that no new repeat is raised. Not part of IQ-00020's 27 (those wait for a decision and are untouched).

```sql
begin;
do $paste$
declare v_n int; v_h text;
begin
  create temporary table _rep on commit drop as
  with d as (select distinct on (entity_id) entity_id, id did, decided_at, status, proposed_value
               from pipeline.layer4_review_items where field_code = 'provider_current_tuition_validation' and status in ('rejected', 'approved', 'edited_approved') order by entity_id, decided_at desc)
  select n.id, n.entity_id, d.did, d.status dstatus, d.decided_at from d join pipeline.layer4_review_items n on n.entity_id = d.entity_id
   where n.field_code = 'provider_current_tuition_validation' and n.status = 'pending' and n.created_at > d.decided_at
     and (n.proposed_value->>'amount')::numeric = (d.proposed_value->>'amount')::numeric and d.decided_at > now() - interval '90 days';
  select count(*), md5(string_agg(id::text, ',' order by id)) into v_n, v_h from _rep;
  if v_n <> 53 or v_h <> '6ad6722331a096c89d7457daddf5e565' then raise exception 'guard: % items, hash %; expected 53 as measured on 8 Nov 2026; nothing changed', v_n, v_h; end if;
  update pipeline.layer4_review_items r set status = 'superseded', decided_at = now(),
         layer3_state = coalesce(r.layer3_state, '{}'::jsonb) || jsonb_build_object('superseded', jsonb_build_object(
           'reason', 'A person already ruled on this figure for this course (' || t.dstatus || ' ' || to_char(t.decided_at, 'DD Mon YYYY') || '); the question is not asked again.',
           'ruling_item', t.did, 'at', now(), 'ref', 'IQ-00040, FEE-20261108'))
    from _rep t where t.id = r.id and r.status = 'pending';
  get diagnostics v_n = row_count;
  if v_n <> 53 then raise exception 'superseded %, expected 53; rolled back', v_n; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'supersede_repeat_paste', 'pipeline.layer4_review_items (53 fee checks)', jsonb_build_object('issue', 'IQ-00040', 'items', 53, 'ids_md5', '6ad6722331a096c89d7457daddf5e565'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b'::uuid);
end $paste$;
commit;
```

Read-back: pending `provider_current_tuition_validation` goes 136 -> 83. Rollback: `update ... set status = 'pending', decided_at = null` for items whose `layer3_state->'superseded'->>'ref' = 'IQ-00040, FEE-20261108'`.
