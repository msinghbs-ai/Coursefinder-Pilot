-- CF-247 S2-BOOST-Providers (Platform Admin 19 Nov 2026 06:49: align the live provider-description prompt with the stored record; complete
-- the left-behind university descriptions). No table, column, function or job is added or changed: data only.
-- What was read live (19 Nov 06:50 to 07:20 AEDT, SELECT only):
--   * The active prompt is version 5 (md5 2784dc0f126d5e72e7817f0f769357d6). Version 4 (md5 985e2613f4970f5936de23a89122bf83), which
--     version 5 was built from, was saved from the admin screen and its text was in no checked-in file; version 5 was built in SQL by
--     20261118213000, so its full text was in no file either. Both texts are now byte-for-byte fixtures
--     (tests/fixtures/pdesc/provider-description-prompt-v4.txt and -v5.txt, spec s760).
--   * The 81 descriptions sent back to the reader by pdesc-reread-p5 have all been read again: 12 admitted, 6 proposed in Layer 4, 63 held
--     by the reader's own checks (a quote not on the page 26, a sentence its quote does not support 24). For the 63 the earlier reading sits
--     on a superseded Layer 4 item and cannot be approved there, because an approval needs the reading in state proposed.
-- 1 The prompt record: version 5 must still be the text of the fixture, or this migration says so in a notice (the Platform Admin may have
--   saved a newer version on Models & services; that is theirs to keep).
-- 2 Rule pdesc-reread-p5-restore: for each provider whose re-read was held, that still has no description, no manual lock, no pending item
--   and no open read, the superseded Layer 4 item is pending again and its own reading is proposed again, exactly as before 18 Nov 18:08.
--   Nothing is admitted by this migration: a person approves or rejects the reading, and the unchanged hourly machine settlement checks it.
-- G1: no job. G2: no operational value. G3: no consumer API object is changed.
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';

do $p$
declare v_md5 text := (select md5(system_prompt) from pipeline.provider_description_prompts where version = 5);
        v_active int := (select version from pipeline.provider_description_prompts where status = 'active');
begin
  if v_md5 is null then raise exception 'prompt version 5 is not stored; nothing applied'; end if;
  if v_md5 <> '2784dc0f126d5e72e7817f0f769357d6' then raise exception 'prompt version 5 is not the text of tests/fixtures/pdesc/provider-description-prompt-v5.txt (md5 %); a stored version is never edited in place', v_md5; end if;
  if (select md5(system_prompt) from pipeline.provider_description_prompts where version = 4) is distinct from '985e2613f4970f5936de23a89122bf83' then
    raise exception 'prompt version 4 is not the text of tests/fixtures/pdesc/provider-description-prompt-v4.txt';
  end if;
  if v_active is distinct from 5 then raise notice 'the active provider-description prompt is version %, saved after version 5; the fixture records version 5 only', v_active; end if;
end $p$;

create temp table cf_restore on commit drop as
  select i.id item_id, i.entity_id provider_id, o.id read_id
    from pipeline.layer4_review_items i
    join catalogue.providers p on p.id = i.entity_id
    join pipeline.provider_description_reads o on o.review_item_id = i.id and o.state = 'superseded' and o.rule = 'layer4_superseded'
   where i.status = 'superseded' and i.entity_type = 'provider' and i.field_code = 'provider_description'
     and i.layer2_state->>'superseded_by' = 'pdesc-reread-p5'
     and p.lifecycle_status = 'active' and nullif(btrim(p.description), '') is null
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
     and not exists (select 1 from pipeline.layer4_review_items x where x.entity_type = 'provider' and x.entity_id = p.id and x.field_code = 'provider_description' and x.status = 'pending')
     and not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = p.id and r.state in ('queued', 'reading', 'proposed'))
     and (select r.state from pipeline.provider_description_reads r
           where r.provider_id = p.id and r.checks is not null and r.created_at > i.decided_at - interval '1 minute' and r.id <> o.id
           order by r.created_at desc limit 1) = 'held';

update pipeline.provider_description_reads r
   set state = 'proposed', rule = 'missing', updated_at = now()
  from cf_restore c where r.id = c.read_id and r.state = 'superseded';

update pipeline.layer4_review_items i
   set status = 'pending', decided_at = null,
       layer2_state = coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('restored_by', 'pdesc-reread-p5-restore', 'restored_at', now(),
                        'restored_reason', 'The re-read with prompt version 5 was held by the reader; the earlier reading is back for a person (Platform Admin 19 Nov 2026 06:49)')
  from cf_restore c where i.id = c.item_id and i.status = 'superseded';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'layer4', 'rule_execute', 'pdesc-reread-p5-restore', jsonb_build_object('items_restored', (select count(*) from cf_restore)), 'c0ffee00-0000-4000-8000-000000000150'::uuid;

do $c$
begin
  if exists (select 1 from cf_restore c join pipeline.layer4_review_items i on i.id = c.item_id where i.status <> 'pending')
     or exists (select 1 from cf_restore c join pipeline.provider_description_reads r on r.id = c.read_id where r.state <> 'proposed') then
    raise exception 'post-check: a restored item is not pending with its reading proposed';
  end if;
  if exists (select 1 from pipeline.provider_description_reads r where r.state in ('queued', 'reading', 'proposed') group by r.provider_id having count(*) > 1) then
    raise exception 'post-check: a provider has two open reads';
  end if;
  if exists (select 1 from cf_restore c join catalogue.providers p on p.id = c.provider_id where nullif(btrim(p.description), '') is not null) then
    raise exception 'post-check: an item was restored for a provider that already has a description';
  end if;
  raise notice 'pdesc-reread-p5-restore: % items restored to Layer 4', (select count(*) from cf_restore);
end $c$;
