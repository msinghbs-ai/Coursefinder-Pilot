-- CF-247 Destination open-licence publishing: the approvals stand when the edition cannot yet be published (S2-Build; Platform Admin
-- 18 Nov 2026 13:07 and 14:23).
--
-- What was read live (18 Nov 2026 14:42 AEDT): the first run of target destination-open-licence-publish failed with "duplicate key value
-- violates unique constraint uq_destination_editions_single_published" (destination.editions: one published edition per country and domain).
-- The ABS population edition and the BOM climate edition are both Australian city_profiles editions, so the BOM edition cannot be published
-- beside ABS, and the failure rolled back the approval of its 40 climate figures too.
--
-- What it changes: the publication step is isolated. When the index refuses it, the edition stays as it is, the run records why
-- (open_licence_publish with published false and the reason), and the approved figures stand: API v3 returns a figure once it and its
-- locality are approved, whatever its edition's status, so the BOM climate averages are served with their attribution. Letting each source
-- owner have its own published edition needs the index replaced; that is a drop, so it goes to the Platform Admin as
-- admin docs/paste/PASTE-20261118-destination-editions-published-per-owner.sql. After it runs, the next hourly run publishes the edition.
-- Nothing is dropped or deleted. G3 untouched.
-- Replaces: the unguarded publication call in security.destination_open_licence_publish_v1.
-- Retires: nothing.

create or replace function pg_temp.cf_edit(p_sig regprocedure, p_md5 text, p_old text, p_new text, p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_c int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(replace(v_src, p_old, p_new)) then
    raise exception '% after the edit is not the expected body', p_sig;
  end if;
end $f$;

select pg_temp.cf_edit('security.destination_open_licence_publish_v1()'::regprocedure, '1017906fc1d2b10ddccdad511df0ce45',
  $o$      v_res := security.destination_edition_publish_v1(e.id, e.approved_by);$o$,
  $n$      begin
        v_res := security.destination_edition_publish_v1(e.id, e.approved_by);
      exception when unique_violation then
        -- 18 Nov 2026: one published edition per country and domain (uq_destination_editions_single_published); the approved rows stand
        v_res := jsonb_build_object('published', false, 'waiting', 'another source owner''s edition of this country and domain is published; the one-published-edition index allows only one until admin paste file PASTE-20261118-destination-editions-published-per-owner.sql is run');
        v_rows := 0;
      end;$n$,
  $m$exception when unique_violation then$m$);

-- run once now: the BOM climate figures are approved (the edition is published only after the paste file)
select security.destination_open_licence_publish_v1();

do $e$
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
  if (select status from destination.editions where edition_label = 'ABS Regional population 2024-25') <> 'published' then
    raise exception 'the ABS population edition must stay published';
  end if;
end $e$;
