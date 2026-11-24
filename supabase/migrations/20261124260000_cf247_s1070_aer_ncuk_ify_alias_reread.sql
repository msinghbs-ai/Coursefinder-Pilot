-- CF-247 s1070 (S2-AER, brief 24 Nov 2026 16:50 AEDT, item 1: "Resolve the 21 mapping gaps": exact values, reusable fixes, existing alias mechanisms, no inferred equivalence).
-- Measured live 24 Nov 2026 16:55 (rolled-back read-back): the 21 pending gate_incomplete items that drop rows as unknown_country or unknown_qualification hold 12 distinct values.
--   Only one is an alias gap of a qualification the platform already holds: "Northern Consortium UK International Foundation Year (NCUK IFY)" (Top Education Institute, 2 rows) is printed
--   where a country goes; ref.aer_qualifications NCUK_IFY has the aliases "...foundation year", "ncuk ify" and "ncuk international foundation year ncuk ify" but not this exact long form with the
--   abbreviation. Nothing is inferred: it is the same qualification name as the page prints it.
--   Left as they are (not mapping gaps; mapping them would infer equivalence): scope words with an unrecognised qualification ("International", "General", "ALL", "INT", "Overseas (general)",
--   "International (general)", "International equivalent", "Generic Qualifications": the global-scope tokens already exist, the qualification is the missing part), regions ("Europe",
--   "Pacific Islands": no country named) and 46 rows with a blank country at 8 providers (reader output, handed to the territorial reader owners).
-- Changes:
-- 1. Appends that one alias to ref.aer_qualifications NCUK_IFY (idempotent; no other qualification may hold it).
-- 2. Reads the Top Education Institute source again with the existing governed re-read (public.admin_entry_matrix_reread, stored copy, one read by the pinned entry model, no Firecrawl) so its
--    dropped rows are verified with the new alias. Every admission rule (evidence, quotes, confidence, host rules, locks) still applies; nothing is admitted here.
-- G1: no job. G2: nothing numeric in code. G3: no consumer object (75/48). Manual locks untouched. Nothing dropped or deleted.
-- Replaces: nothing
-- Retires: nothing
set local lock_timeout = '5s';  -- fixed: lock wait for the qualification row

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if not exists (select 1 from ref.aer_qualifications where code = 'NCUK_IFY') then raise exception 'guard: NCUK_IFY is not held'; end if;
end $g$;

create temp table s1070_locks on commit drop as select count(*) n from pipeline.manual_locks;

do $a$
declare v_alias text := 'northern consortium uk international foundation year ncuk ify'; v_type text;
begin
  select udt_name into v_type from information_schema.columns where table_schema = 'ref' and table_name = 'aer_qualifications' and column_name = 'aliases';
  if exists (select 1 from ref.aer_qualifications q where q.code <> 'NCUK_IFY' and q.aliases::text ilike '%' || v_alias || '%') then
    raise exception 'guard: another qualification already holds the alias';
  end if;
  if v_type = 'jsonb' then
    update ref.aer_qualifications set aliases = aliases || to_jsonb(v_alias) where code = 'NCUK_IFY' and not (aliases ? v_alias);
  else
    update ref.aer_qualifications set aliases = array_append(aliases, v_alias) where code = 'NCUK_IFY' and not (v_alias = any (aliases));
  end if;
end $a$;

do $r$
declare v jsonb; ids uuid[];
begin
  select array_agg(distinct s.source_id) into ids from pipeline.entry_matrix_runs s join pipeline.layer4_review_items li on li.id = s.review_item_id
   where li.status = 'pending' and li.entity_id::text like 'c8a3391d%' and li.claimed_at is null and li.assigned_to is null;
  if ids is null then raise notice 'reread: no unclaimed pending source for the provider'; return; end if;
  v := public.admin_entry_matrix_reread(ids, 'S2-AER s1070: NCUK IFY long-form alias added; earlier read dropped its rows as unknown_country; read again from the stored copy in place of its waiting item (no Firecrawl)');
  raise notice 'reread: % sources: %', cardinality(ids), v;
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if not exists (select 1 from ref.aer_qualifications where code = 'NCUK_IFY' and aliases::text ilike '%northern consortium uk international foundation year ncuk ify%') then raise exception 'post-check: alias missing'; end if;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'post-check: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1070_locks) then raise exception 'post-check: manual locks changed'; end if;
end $c$;
