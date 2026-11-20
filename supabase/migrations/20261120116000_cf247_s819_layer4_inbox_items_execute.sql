-- CF-247 s819 (Platform Admin 20 Nov 2026 09:55 AEDT, chat S1-Build): Layer 4 decisions under 300 ms. After s813/s814 went live, every decision
-- was timed again live in a rolled-back run (20 Nov 2026 11:44 AEDT, as the Platform Admin, one item per kind, the best of two warm calls):
-- Held scholarship 989 to 1,326 ms, Entry requirements 830 to 1,028 ms, descriptions 608 to 678 ms, the rest 370 to 805 ms. By function time,
-- 85% of a Held scholarship decision was security.layer4_inbox_items_v2: every decision reads its item twice (the detail, then whether it still
-- waits), about 280 ms each when warm.
-- The cause is planning, not reading: the function is a SQL function with its own search_path, so it is never inlined and every call plans the
-- whole union of item sources with its arguments unknown. Nothing can be pruned ("p_kind is null or z.k = p_kind" is decided row by row), so a
-- keyed read for one held scholarship still scans the review items, the onboarding history and the holds. Read with its arguments known, the
-- same text takes about 25 ms to run and 35 ms to plan.
-- Change: the same query text, run by PL/pgSQL EXECUTE with the four arguments passed as parameters ($1 to $4). EXECUTE plans each call with
-- the values known, so the sources a call cannot return are left out. The query text is the live text, read and md5-checked here, with only the
-- argument names replaced; no row, column, filter or order changes.
-- Measured in a rolled-back run (11:52 AEDT): keyed read 278 to 288 ms → 64 to 69 ms; the full Inbox read 6,875 ms → 1,618 ms; the same rows
-- (md5 of every row) for the full read, a 400-item keyed read across every kind and one university's read.
-- Parity before writing (read live 20 Nov 2026 11:40 AEDT): head 20261120120000, 2,212 rows; main at #1415. Number inside the S1-Build range
-- (20261120111000 to 20261120119000, Platform Admin plan 20 Nov 10:48).
-- G3: no consumer object changes (security.layer4_inbox_items_v2 is internal to the admin Layer 4 Inbox). G2: no operational value. No spend.
-- Replaces: the planned-per-call SQL body of security.layer4_inbox_items_v2 (same query text, run with its arguments known).
-- Retires: nothing.

do $$
declare
  v_sig regprocedure := 'security.layer4_inbox_items_v2(uuid,text,text[],boolean)'::regprocedure;
  v_def text := replace(pg_get_functiondef('security.layer4_inbox_items_v2(uuid,text,text[],boolean)'::regprocedure), chr(13), '');
  v_src text;
  v_lang text;
begin
  select l.lanname, p.prosrc into v_lang, v_src from pg_proc p join pg_language l on l.oid = p.prolang where p.oid = v_sig;
  if v_lang = 'plpgsql' and v_src like '%return query execute%' then
    raise notice 's819: security.layer4_inbox_items_v2 already runs by EXECUTE; nothing to do';
    return;
  end if;
  if md5(v_def) <> 'd19cd5e2c05a59b0c985afd87b6ce18a' then
    raise exception 'pre-check: security.layer4_inbox_items_v2 changed since it was read (definition md5 %)', md5(v_def);
  end if;
  -- the query text must not carry a dollar quote or another name that starts with an argument's name
  if v_src ~ '\$[A-Za-z_]*\$' or v_src ~ '\mp_(provider_id|kind|keys|detail)[A-Za-z0-9_]' then
    raise exception 'pre-check: the query text of security.layer4_inbox_items_v2 cannot be passed to EXECUTE as read';
  end if;
  v_src := regexp_replace(v_src, '\mp_provider_id\M', '$1', 'g');
  v_src := regexp_replace(v_src, '\mp_kind\M', '$2', 'g');
  v_src := regexp_replace(v_src, '\mp_keys\M', '$3', 'g');
  v_src := regexp_replace(v_src, '\mp_detail\M', '$4', 'g');
  execute 'create or replace function security.layer4_inbox_items_v2(p_provider_id uuid default null, p_kind text default null, p_keys text[] default null, p_detail boolean default true)
 returns table(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamp with time zone, detail jsonb)
 language plpgsql stable security definer
 set search_path to ''''
as $function$
begin
  -- CF-247 s819 (20 Nov 2026): the item query below, run by EXECUTE with the arguments as parameters, so each call is planned with its values
  -- known and the sources it cannot return are left out (a SQL function body is planned with them unknown). $1 university, $2 kind,
  -- $3 keys (''kind:ref''), $4 detail.
  return query execute ' || quote_literal(v_src) || '
    using p_provider_id, p_kind, p_keys, p_detail;
end
$function$';
end $$;

-- post-checks, as a signed-in Platform Admin: the rows are the same as the definition it replaced, and decisions are timed (rolled back)
do $$
declare v_admin uuid; v_o text := ''; v_ks text[]; v_a text; v_b text; r jsonb; it jsonb; pr text[]; t0 timestamptz; ms int; v_hs int; v_src text; v_pid uuid;
begin
  -- the replaced definition, rebuilt as a temporary SQL function from the new text, gives the reference rows
  select p.prosrc into v_src from pg_proc p where p.oid = 'security.layer4_inbox_items_v2(uuid,text,text[],boolean)'::regprocedure;
  v_src := substr(v_src, strpos(v_src, 'return query execute ') + length('return query execute '));
  v_src := substr(v_src, 1, strpos(v_src, E'\n    using p_provider_id, p_kind, p_keys, p_detail;') - 1);
  execute 'select ' || v_src into v_src;
  execute 'create function pg_temp.s819_ref(uuid, text, text[], boolean)
    returns table(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamptz, detail jsonb)
    language sql stable set search_path to '''' as ' || quote_literal(v_src);
  select md5(string_agg(x::text, '|' order by x.kind, x.ref)) into v_a from security.layer4_inbox_items_v2(null, null, null, true) x;
  select md5(string_agg(x::text, '|' order by x.kind, x.ref)) into v_b from pg_temp.s819_ref(null, null, null, true) x;
  if v_a is distinct from v_b then raise exception 'post-check: the full read differs from the replaced definition'; end if;
  select array_agg(x.kind || ':' || x.ref) into v_ks from (select i.kind, i.ref from security.layer4_inbox_items_v2(null, null, null, false) i order by md5(i.ref) limit 400) x;
  select md5(string_agg(x::text, '|' order by x.kind, x.ref)) into v_a from security.layer4_inbox_items_v2(null, null, v_ks, true) x;
  select md5(string_agg(x::text, '|' order by x.kind, x.ref)) into v_b from pg_temp.s819_ref(null, null, v_ks, true) x;
  if v_a is distinct from v_b then raise exception 'post-check: the keyed read differs from the replaced definition'; end if;
  select i.provider_id into v_pid from security.layer4_inbox_items_v2(null, null, null, false) i where i.provider_id is not null order by md5(i.ref) limit 1;
  select md5(string_agg(x::text, '|' order by x.kind, x.ref)) into v_a from security.layer4_inbox_items_v2(v_pid, null, null, false) x;
  select md5(string_agg(x::text, '|' order by x.kind, x.ref)) into v_b from pg_temp.s819_ref(v_pid, null, null, false) x;
  if v_a is distinct from v_b then raise exception 'post-check: one university''s read differs from the replaced definition'; end if;
  v_o := 'same rows: full, 400 keyed, one university; ';

  select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
   where ro.status = 'active' and ro.rank >= 6 and (ur.expires_at is null or ur.expires_at > now()) order by ur.user_id limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  foreach pr slice 1 in array array[['held_scholarship', 'not_international'], ['held_scholarship', 'publish'], ['aer_review', 'approve'],
                                    ['provider_description', 'approve'], ['course_link', 'use'], ['pages_not_found', 'release'], ['site_down', 'wait']] loop
    r := public.admin_layer4_inbox('items', jsonb_build_object('kind', pr[1], 'limit', 1)); it := r->'items'->0;
    continue when it is null;
    begin perform public.admin_layer4_inbox('decide', jsonb_build_object('kind', pr[1], 'ref', it->>'ref', 'choice', pr[2], 'reason', 'post-check warm (rolled back)')); raise exception 'cf-s819-undo';
    exception when others then null; end;
    t0 := clock_timestamp();
    begin
      r := public.admin_layer4_inbox('decide', jsonb_build_object('kind', pr[1], 'ref', it->>'ref', 'choice', pr[2], 'reason', 'post-check (rolled back)'));
      ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
      if pr[1] = 'held_scholarship' then
        if not coalesce((r->>'ok')::boolean, false) then raise exception 'post-check: held scholarship % did not apply: %', pr[2], left(r::text, 300); end if;
        v_hs := greatest(coalesce(v_hs, 0), ms);
      end if;
      v_o := v_o || pr[1] || '/' || pr[2] || ' ' || ms || 'ms; ';
      raise exception 'cf-s819-undo';
    exception when others then
      if sqlerrm like 'post-check:%' then raise; end if;
      if sqlerrm <> 'cf-s819-undo' then v_o := v_o || pr[1] || '/' || pr[2] || ' refused by its own rule (' || left(sqlerrm, 60) || '); '; end if;
    end;
  end loop;
  perform set_config('request.jwt.claims', '', true);
  if v_hs is null then raise exception 'post-check: no held scholarship was decided'; end if;
  if v_hs > 1000 then raise exception 'post-check: a held scholarship decision took % ms', v_hs; end if;
  perform set_config('cf.diag', v_o, true);
end $$;
