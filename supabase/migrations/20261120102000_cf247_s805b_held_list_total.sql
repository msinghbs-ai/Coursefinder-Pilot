-- CF-247 s805b (S1-Build live read-back of s802 to s805, 20 Nov 2026 08:10 AEDT): Layer 4 › Inbox › Held universities: open for writing said
-- "200 with no description and a held reading" when 352 are held: the total counted the page, not every match. The list now counts every
-- match and returns the page from it. Read only; nothing else changes.
-- Parity before writing (read live 08:08 AEDT): head 20261120101000, 2,204 rows.
-- G3: no consumer object changes. No spend.
-- Replaces: the page-sized total of security.human_edit_admin_v1 description_held_list (s802).
-- Retires: nothing.

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.cf_edit_def('security.human_edit_admin_v1(text,jsonb)'::regprocedure, '556463cffdf557048473e0c7e67617bb',
  array[$o$    select jsonb_build_object('items', coalesce(jsonb_agg(to_jsonb(z) order by z.name), '[]'::jsonb), 'total', count(*)) into v_out from ($o$,
        $o$       order by 2 limit v_lim offset v_off) z;$o$],
  array[$n$    with m as (  -- s805b: every match, so the total is the whole count; the page is cut from it$n$,
        $n$    )
    select jsonb_build_object('items', coalesce((select jsonb_agg(to_jsonb(z) order by z.name) from (select * from m order by name limit v_lim offset v_off) z), '[]'::jsonb),
                              'total', (select count(*) from m)) into v_out;$n$]);

-- post-check, as a signed-in Platform Admin: the total is every match and is not the page size
do $$
declare v_admin uuid; a jsonb; b jsonb; v_all int;
begin
  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  a := security.human_edit_admin_v1('description_held_list', jsonb_build_object('limit', 5));
  b := security.human_edit_admin_v1('description_held_list', jsonb_build_object('q', 'Torrens'));
  perform set_config('request.jwt.claims', '', true);
  select count(*) into v_all from catalogue.providers p join lateral (select r.state from pipeline.provider_description_reads r where r.provider_id = p.id order by r.updated_at desc limit 1) h on h.state = 'held'
   where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.description), '') is null and security.provider_description_scope_v1(p.id)
     and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = p.id and i.field_code = 'provider_description' and i.status = 'pending');
  if (a->>'total')::int <> v_all or jsonb_array_length(a->'items') <> least(5, v_all) then raise exception 'post-check: held total % (expected %), page %', a->>'total', v_all, jsonb_array_length(a->'items'); end if;
  if (b->>'total')::int < 1 then raise exception 'post-check: Torrens not found'; end if;
  perform set_config('cf.diag', format('held total %s, page %s, Torrens %s', a->>'total', jsonb_array_length(a->'items'), b->>'total'), true);
end $$;
