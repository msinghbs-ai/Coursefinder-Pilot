-- CF-247 StudySearch usability remediation UR-04 (Platform Admin mandate 1 Nov 2026 11:48, Tranche B; review
-- admin docs/platform/nz-enrichment-brief/2026-11-01-role-guides-usability-operability-review.md; record §36).
-- Why: Layer 4 › Review shows at most 200 items of a kind (AER 993, Adapter has nothing ready 315), with no way to reach the rest; the list
--   was ordered by kind order and created time only, without a tie-breaker, and an offset page shifts when an item is decided.
-- What: public.admin_layer4_inbox 'items' (md5-guarded edit) orders by (kind order, created, kind, ref), (kind, ref) being unique, and takes
--   an optional position after_o / after_at / after_kind / after_ref: the page continues after that item, so a decision or a new arrival
--   never hides or repeats an item. Each item carries its kind order ('o'); the reply carries 'before' (items ahead of the page).
--   The page size stays at most 200 (not raised). The UI keeps the position for the browser tab and resumes it after a destination screen.
-- Dry run (rolled back, as a Platform Admin): AER traversed in 5 pages of 200: 993 items reached, 993 distinct, equal to the kind count; 397 ms.
-- Rollback: re-apply the previous definition (md5 ff6e116b); the UI ignores 'before' when absent.
-- Replaces: public.admin_layer4_inbox (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API untouched (G3).

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_once('public.admin_layer4_inbox(text,jsonb)', 'ff6e116bf052c972a59b7a71bdb1fbf4', '48a52717d398c14de6920f18667068a0', array[
 array[$o$'created_at', z.created_at, 'late', z.created_at < now() - make_interval(days => v_target), 'detail', z.detail) order by z.o, z.created_at)$o$,
       $n$'created_at', z.created_at, 'late', z.created_at < now() - make_interval(days => v_target), 'detail', z.detail, 'o', z.o) order by z.o, z.created_at, z.kind, z.ref)$n$],
 array[$o$from (select * from x order by o, created_at limit v_lim offset v_off) z), '[]'::jsonb)));$o$,
       $n$from (select * from x
                      -- UR-04 (1 Nov 2026): a stable position (kind order, created, kind, ref) so every item is reached once, oldest first
                      where not (p_args ? 'after_ref')
                         or (x.o, x.created_at, x.kind, x.ref) > ((p_args->>'after_o')::int, (p_args->>'after_at')::timestamptz, p_args->>'after_kind', p_args->>'after_ref')
                      order by o, created_at, kind, ref limit v_lim offset v_off) z), '[]'::jsonb),
          'before', (select count(*) from x where p_args ? 'after_ref'
                       and (x.o, x.created_at, x.kind, x.ref) <= ((p_args->>'after_o')::int, (p_args->>'after_at')::timestamptz, p_args->>'after_kind', p_args->>'after_ref'))));$n$]],
 array[1, 1]);
