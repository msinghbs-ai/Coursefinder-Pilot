# CDESC-20261108: decode HTML entities in 11 live course descriptions (PASTE FILE, for the Controller; not applied by any migration)

**Why.** 11 of the 163 course descriptions live today show the raw text `&#039;` instead of an apostrophe (for example "If you&#039;re curious..."). The Website and Zoho show these 11 as written. All 11 are University of Queensland descriptions admitted on 24 to 26 Aug 2026 by the Layer 2 adapter path (`public.layer2_apply_course_candidate`, strategy description_candidate) with no entity decoding; nothing has written a description by that path since 26 Aug. They are not reader (Layer 4) values and have no decision to preserve.

**Change.** Exactly 11 rows: `catalogue.courses.description` and the matching `pim.attribute_values.value_text` (attribute `course_description`) get `&#039;` replaced by `'`. Nothing else is touched: no other character, no other row, no lock, no lifecycle state. A search refresh is requested so the projection shows the corrected text. This changes the text a consumer reads, not the shape of any consumer API object (G3 untouched).

**Authority.** Needs the Platform Admin's approval (it edits live published values). Not a Layer 4 decision. Nothing is deleted.

**Measured read-only 8 Nov 2026 ~03:50 UTC.** 11 active courses; sorted course ids md5 `46595afa5b155eef7558a9e95a784d2b`; descriptions (ordered by id, joined by `|`) md5 `d5704cc0a9e157b80b70d5ce9bf8bd61`; 11 PIM rows; 11 search documents; 0 manual locks.

**Rollback.** The before-text is written to `pipeline.admin_control_events.detail` by the block; reverse with the second block below.

```sql
begin;
do $$
declare
  v_ids uuid[]; v_n int; v_upd int; v_pim int; v_md5 text; v_txt text; v_before jsonb;
begin
  select array_agg(id order by id), count(*), md5(string_agg(id::text, ',' order by id)), md5(string_agg(description, '|' order by id))
    into v_ids, v_n, v_md5, v_txt
    from catalogue.courses where lifecycle_status = 'active' and description ~ '&#039;';
  if v_n <> 11 or v_md5 <> '46595afa5b155eef7558a9e95a784d2b' or v_txt <> 'd5704cc0a9e157b80b70d5ce9bf8bd61' then
    raise exception 'CDESC guard: % rows, ids % / text %; nothing changed', v_n, v_md5, v_txt;
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = any(v_ids) and l.field in ('description', 'course_description', 'all')) then
    raise exception 'CDESC guard: a description is locked by hand; nothing changed';
  end if;
  select jsonb_object_agg(id, description) into v_before from catalogue.courses where id = any(v_ids);
  update catalogue.courses set description = replace(description, '&#039;', ''''), updated_at = now() where id = any(v_ids) and description ~ '&#039;';
  get diagnostics v_upd = row_count;
  if v_upd <> 11 then raise exception 'CDESC guard: updated % of 11; rolled back', v_upd; end if;
  update pim.attribute_values av set value_text = replace(av.value_text, '&#039;', ''''), updated_at = now()
    from pim.attribute_definitions ad, pim.entity_registry er, catalogue.courses c
   where ad.id = av.attribute_id and ad.code = 'course_description' and er.id = av.entity_id and er.entity_type = 'course'
     and er.stable_key = c.stable_key and c.id = any(v_ids) and av.value_text ~ '&#039;';
  get diagnostics v_pim = row_count;
  if v_pim <> 11 then raise exception 'CDESC guard: % of 11 PIM rows; rolled back', v_pim; end if;
  if exists (select 1 from catalogue.courses where id = any(v_ids) and description ~ '&#?[a-z0-9]+;') then raise exception 'CDESC guard: an entity is left; rolled back'; end if;
  insert into search.refresh_requests(requested_by) values ('CDESC 20261108 decode HTML entities in 11 live course descriptions');
  insert into pipeline.admin_control_events(area, action, target, detail)
  values ('housekeeping', 'cdesc_decode_html_entities', 'catalogue.courses.description',
          jsonb_build_object('count', v_upd, 'pim_rows', v_pim, 'ids_md5', v_md5, 'before_text_md5', v_txt, 'before', v_before, 'consumer_shape_changed', false,
                             'authority', 'Platform Admin approval (record the time here)'));
end $$;
commit;
```

**Verify after (read only).** `select count(*) from catalogue.courses where lifecycle_status='active' and description ~ '&#?[a-z0-9]+;'` = 0; `select count(*) from catalogue.courses where lifecycle_status='active' and nullif(btrim(description),'') is not null` = 163 (unchanged); after the search refresh (`search.refresh_requests` processed) `select count(*) from search.course_documents where description ~ '&#039;'` = 0; the Website API v2 course detail for one of the ids (for example 38082124-954c-46fa-a05c-18f6593cc0a4) shows "you're".

**Rollback block** (run only if the correction must be reversed; takes the before-text from the audit event):

```sql
begin;
do $$
declare e jsonb; k text;
begin
  select detail->'before' into e from pipeline.admin_control_events where action = 'cdesc_decode_html_entities' order by id desc limit 1;
  if e is null then raise exception 'no audit event to roll back'; end if;
  for k in select jsonb_object_keys(e) loop
    update catalogue.courses set description = e->>k, updated_at = now() where id = k::uuid;
    update pim.attribute_values av set value_text = e->>k, updated_at = now()
      from pim.attribute_definitions ad, pim.entity_registry er, catalogue.courses c
     where ad.id = av.attribute_id and ad.code = 'course_description' and er.id = av.entity_id and er.entity_type = 'course' and er.stable_key = c.stable_key and c.id = k::uuid;
  end loop;
  insert into search.refresh_requests(requested_by) values ('CDESC 20261108 rollback of the entity decoding');
end $$;
commit;
```
