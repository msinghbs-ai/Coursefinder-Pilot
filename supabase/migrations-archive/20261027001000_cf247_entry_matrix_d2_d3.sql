-- CF-247 AER v1.1, RMIT D2 and D3 (Platform Admin 27 Oct 2026 04:58: "Build D1–D3 and merge under rule 9"). Record: admin
-- docs/platform/aer-v1.1-build-log.md. D1 (a band given as the page's "Not applicable") is in the worker (v0.48.4).
-- 1 D2: public.svc_entry_country_refs_v1() gives the worker the country reference list (alpha-2, alpha-3, name, official name), so an
--   equivalency page whose heading names no country (RMIT International Baccalaureate, Global Assessment Certificate) or whose table has
--   requirement-type columns (Foundation equivalencies) is held "held_unparsed" before any AI read. The record function already makes that
--   terminal (state failed, no retry) and keeps the held read in previous_results (#709). No new state or status value.
-- 2 D3: public.admin_entry_matrix_reread (md5-guarded) also takes failed runs. The earlier result is kept with its state, error and the
--   attempts it used, linked to the re-read by its position in previous_results; the run starts its own attempts again. Proposed rows and
--   pending items of the earlier result are superseded as before (a held or failed read proposed none), so nothing is proposed or admitted
--   twice.
-- Replaces: nothing (one function edited in place, md5-guarded; one function added)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (ref.countries is read, not changed).

create or replace function public.svc_entry_country_refs_v1() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('a2', trim(k.iso_alpha2::text), 'a3', trim(k.iso_alpha3::text), 'name', k.name, 'official', k.official_name) order by k.iso_alpha2), '[]'::jsonb)
            from ref.countries k);
end $$;
revoke all on function public.svc_entry_country_refs_v1() from public, anon, authenticated;
grant execute on function public.svc_entry_country_refs_v1() to service_role;
comment on function public.svc_entry_country_refs_v1() is 'CF-247 AER v1.1 D2: the country reference list the entry-matrix worker checks an equivalency page''s heading against (service role).';

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('public.admin_entry_matrix_reread(uuid[],text)', 'cec7158550b26b2b88a6a5e559384231', array[
  array[$o$where source_id = any(p_source_ids) and state = 'done' for update loop$o$,
        $n$where source_id = any(p_source_ids) and state in ('done', 'failed') for update loop  -- D3 (27 Oct 2026): a failed run can be read again too$n$],
  array[$o$'review_item_id', r.review_item_id, 'done_at', r.done_at,
             'reread_at', now(), 'reason', trim(p_reason))),$o$,
        $n$'review_item_id', r.review_item_id, 'done_at', r.done_at,
             'reread_at', now(), 'reason', trim(p_reason),
             -- D3: the earlier result's state, error and the attempts it used stay with it; earlier_index links it to what came before
             'state', r.state, 'error', r.error, 'attempts_used', r.attempts, 'earlier_index', jsonb_array_length(r.previous_results))),$n$]],
  array[1, 1]);
