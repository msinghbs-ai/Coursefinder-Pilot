-- CF-247 S1-RM-Design s890 (Platform Admin 20 Nov 2026 22:54 and 23:07 AEDT, chat S1-RM-Design): Victoria University's second registration keeps its
-- courses and takes the university's description, so its description hold closes.
-- What was read live (20 Nov 2026 22:59-23:14 AEDT, rolled-back dry runs only, no interactive query; head 20261120200000):
--   Victoria University CRICOS 00124K (bac82321): 279 active courses, the recorded owner of vu.edu.au (pipeline.provider_host_owners, s766), description
--     admitted 19 Nov (read 291d4f7d, item a6aec80c).
--   Victoria University CRICOS 02475D (0f5373c8, vu.edu.au/international): a separate registration for the Sydney City Centre and Brisbane campuses,
--     35 active international courses with their own CRICOS course codes, no description, no manual lock. Its only description read (3559c277,
--     9 Nov) is held on provider_host_conflict because 00124K owns the host; it is listed under Held universities: open for writing.
--   UTS (9d22a19e): the description was approved in Layer 4 Review (item 9e1d3b89) and is live; nothing waits. Nothing is changed for UTS.
-- The Platform Admin's decision (23:07, after the record was shown not to be a copy): keep both records and give 02475D the parent's description.
-- What this change does:
--   1 Applies the decision through the screen's own path, as the Platform Admin: public.admin_layer4_inbox description_open_held, then decide
--     edit_approve with the text of 00124K's live description and no manual lock (the lock count stays 7,585). The decision is audited as human input
--     and listed in Human Edits & Periodic Audit. Rehearsed rolled back 23:14 (run 44734083037): admitted, item resolved, locks 7,585.
--   2 Fixes what the rehearsal showed: a university opened for writing from a held reading kept that reading held after its text was admitted,
--     because the reading was not linked to the new item. security.layer4_description_human_admit_v1 now also admits the reading the item names
--     (proposed_value read_id) and links it to the item, so the following statement, which supersedes the provider's other admitted readings, keeps it.
--     md5-guarded edit (c332bdfe, read live 23:14); no other line changes.
-- Not changed: 02475D stays active and published with its 35 courses (no lifecycle event, no archive, no re-parenting); the host owner record; UTS;
-- the consumer API (G3 75 functions and 48 relations, read before and after); the manual locks (7,585 before and after); no AI or Firecrawl call.
-- Numbering: spec s890 (s884-s886 are S1-ELR's in an open pull request); migration 20261120231000, above the live head 20261120200000 and
-- 20261120220000 in the open pull request #1439.
-- G1: no job. G2: no value. Spend: none. Nothing dropped or deleted.
-- Replaces: the reading update inside security.layer4_description_human_admit_v1 (it also matches the reading the item names).
-- Retires: nothing.
set local lock_timeout = '5s';

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'guard: the manual locks are not 7,585 before this change'; end if;
  if md5(replace(pg_get_functiondef('security.layer4_description_human_admit_v1(uuid,uuid,jsonb,text)'::regprocedure), chr(13), '')) <> 'c332bdfe60b67b8ce57f6e5e24709fe4' then
    raise exception 'pre-check: security.layer4_description_human_admit_v1 changed since it was read';
  end if;
end $g$;

-- 2 the reading the item names is admitted with the item's text ------------------------------------------------------------------------------
do $e$
declare v_def text := pg_get_functiondef('security.layer4_description_human_admit_v1(uuid,uuid,jsonb,text)'::regprocedure);
        v_old constant text := 'where review_item_id = i.id and state in (''proposed'', ''held'');';
        v_new constant text := 'where (review_item_id = i.id or id = nullif(i.proposed_value->>''read_id'', '''')::uuid) and provider_id = i.entity_id and state in (''proposed'', ''held'');  -- s890: a reading opened for writing is linked by read_id';
        v_old2 constant text := 'jsonb_build_object(''admission_source'', ''human_input''), updated_at = now()';
        v_new2 constant text := 'jsonb_build_object(''admission_source'', ''human_input''), updated_at = now(), review_item_id = i.id';
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'guard: the reading update is not found exactly once'; end if;
  if (length(v_def) - length(replace(v_def, v_old2, ''))) / length(v_old2) <> 1 then raise exception 'guard: the reading admission is not found exactly once'; end if;
  -- the admitted reading is linked to its item, so the next statement (which supersedes other admitted readings) keeps it
  execute replace(replace(v_def, v_old, v_new), v_old2, v_new2);
end $e$;

-- 1 the Platform Admin's decision for CRICOS 02475D ---------------------------------------------------------------------------------------------
do $d$
declare c_admin constant uuid := '63ba56cb-48d4-4169-98c2-7c4d1f72925b';   -- the Platform Admin who decided (20 Nov 2026 23:07 AEDT)
        c_vu2 constant uuid := '0f5373c8-d724-4303-9267-739530a5ce53';      -- Victoria University, CRICOS 02475D
        c_vu1 constant uuid := 'bac82321-ded7-4e10-a71d-b18f3ae4d1c7';      -- Victoria University, CRICOS 00124K
        c_read constant uuid := '3559c277-63c9-42b8-a404-71edc2576960';     -- 02475D's held reading
        v_text text; v_open jsonb; v_dec jsonb; v_courses int;
begin
  if not exists (select 1 from security.user_roles ur join security.roles ro on ro.code = ur.role_code
                  where ur.user_id = c_admin and ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now())) then
    raise exception 'guard: the deciding Platform Admin no longer holds the role';
  end if;
  if not exists (select 1 from catalogue.providers p where p.id = c_vu2 and p.stable_key = 'provider:cricos:02475d' and p.lifecycle_status = 'active'
                  and p.publication_status = 'published' and nullif(btrim(p.description), '') is null) then
    raise exception 'guard: CRICOS 02475D is not the active record with no description that was read';
  end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = c_vu2) then raise exception 'guard: 02475D has a manual lock'; end if;
  if not exists (select 1 from pipeline.provider_description_reads r where r.id = c_read and r.provider_id = c_vu2 and r.state = 'held') then
    raise exception 'guard: 02475D''s held reading is not as read';
  end if;
  if not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = c_vu1 and r.state = 'admitted') then
    raise exception 'guard: 00124K has no admitted description reading';
  end if;
  select nullif(btrim(p.description), '') into v_text from catalogue.providers p where p.id = c_vu1 and p.stable_key = 'provider:cricos:00124k' and p.lifecycle_status = 'active';
  if v_text is null then raise exception 'guard: 00124K has no description to give'; end if;
  select count(*) into v_courses from catalogue.courses c where c.provider_id = c_vu2 and c.lifecycle_status = 'active';

  perform set_config('request.jwt.claims', jsonb_build_object('sub', c_admin, 'role', 'authenticated')::text, true);
  v_open := public.admin_layer4_inbox('description_open_held', jsonb_build_object('provider_id', c_vu2));
  v_dec := public.admin_layer4_inbox('decide', jsonb_build_object('kind', 'provider_description', 'ref', v_open->>'item_id', 'choice', 'edit_approve',
             'value', v_text, 'set_manual_lock', false,
             'reason', 'Platform Admin 20 Nov 2026 23:07 AEDT (chat S1-RM-Design, s890): keep CRICOS 02475D (Sydney City Centre and Brisbane) with its courses and give it the description of Victoria University CRICOS 00124K'));
  perform set_config('request.jwt.claims', '', true);

  if coalesce((v_dec->>'ok')::boolean, false) is not true then raise exception 'post-check: the decision was not applied: %', v_dec; end if;
  if (select description from catalogue.providers where id = c_vu2) is distinct from v_text then raise exception 'post-check: 02475D''s description is not the parent''s'; end if;
  if (select state from pipeline.provider_description_reads where id = c_read) <> 'admitted' then raise exception 'post-check: 02475D''s reading is still held'; end if;
  if exists (select 1 from pipeline.layer4_review_items i where i.entity_id = c_vu2 and i.field_code = 'provider_description' and i.status = 'pending') then
    raise exception 'post-check: a description item still waits for 02475D';
  end if;
  if (select count(*) from catalogue.courses c where c.provider_id = c_vu2 and c.lifecycle_status = 'active') <> v_courses then raise exception 'post-check: 02475D''s active courses changed'; end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer4', 'rule_execute', 's890-vu-02475d-parent-description',
          jsonb_build_object('provider_id', c_vu2, 'from_provider_id', c_vu1, 'item_id', v_open->>'item_id', 'read_id', c_read, 'courses_kept', v_courses,
                             'manual_lock', false, 'decided', 'Platform Admin 20 Nov 2026 23:07 AEDT'), c_admin);
end $d$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> 7585 then raise exception 'post-check: manual locks changed'; end if;
end $p$;
