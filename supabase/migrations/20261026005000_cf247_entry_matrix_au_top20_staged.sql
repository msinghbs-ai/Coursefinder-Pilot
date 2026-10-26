-- CF-247 AU completion week, step 6 (Platform Admin 26 Oct 2026 17:01: "Entry-matrix reader (Track C): switch staged for the AU top-20,
-- off until I confirm tomorrow."). Record: admin docs/platform/ui-audit/2026-10-26-au-completion-week.md.
-- 1 Setting entry.providers: the providers whose entry-requirements pages are read; an empty list means every provider in
--   entry.countries. Staged with the AU top 20 of the Track C verification (ENTRY-REQUIREMENTS-IMPLEMENTATION.md Part 1: the Group of
--   Eight plus the 12 largest other universities by published active courses; the live ranking on 26 Oct gives the same 20).
-- 2 security.entry_matrix_enabled_v1 honours entry.providers (md5-guarded edit). Every entry-matrix path (attach, enqueue, fire, fetch,
--   next, use-stored) goes through this one check, so nothing else changes.
-- Nothing is switched on: entry.matrix_enabled stays 0 and job entry-matrix-read stays inactive until the Platform Admin confirms
-- (then: entry.matrix_enabled 1 and the job active, both logged).
-- Replaces: nothing (security.entry_matrix_enabled_v1 edited in place, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.providers', 'Entry matrices: providers', 'Providers whose entry-requirements pages are read (provider ids). Empty: every provider in Entry matrices: countries.', 'list',
  '["22657140-1cb0-4fa7-91df-90518ea8b35b", "68022bdf-43e8-44b3-ac14-e9eed9f71e83", "543b87b8-f0dd-4bc7-80d6-76252cfaabec", "de2201a1-69ee-40ff-b6aa-0e54e535e6c0",
    "de6d32b0-f91b-4dd0-a3da-a542f1aba5f2", "e47a940d-186f-4a17-bb22-2b794b73248c", "e55396d2-869a-46ef-9d17-841c7eab1313", "9109fe0c-9f44-4e2d-a136-eb00dec24701",
    "9d22a19e-c3f7-4012-b738-17bc0b481e7f", "8e1adb6c-e069-43db-9584-bd054255e702", "0a42da16-8df1-4439-a929-4dfdd04b6d83", "188103a5-1aba-4f99-bd3e-0416659086d3",
    "1822b40a-8b13-44dc-8c37-106ae31bb447", "349da14b-66b1-4c57-9dfd-6f9c36412432", "982fb12f-41ed-4358-9d1b-d7422b3089dd", "62e61a02-9fcb-4c5e-bb11-1c43bed6eee6",
    "1719c3ba-1ddf-483e-935e-c750124ba99c", "36086f5e-9fe0-4878-aa40-1897a7d8cb24", "2c4f515c-c146-4e90-ba8a-294130aa1f40", "bac82321-ded7-4e10-a71d-b18f3ae4d1c7"]'::jsonb,
  null, null, 'providers', 902, 'Entry requirements', 'security.entry_matrix_enabled_v1',
  'CF-247 AU completion week step 6, Platform Admin 26 Oct 2026 17:01: staged for the AU top 20 (Group of Eight + 12 largest other universities), reader off until confirmed')
on conflict (toolset_key, key) do nothing;

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

select pg_temp.edit_n('security.entry_matrix_enabled_v1(uuid)', 'a238a2c24f19f8dd9fa1bb6435d8ca75', array[
  array[$o$     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider)$o$,
        $n$     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider)
     -- AU completion week step 6 (26 Oct 2026): only the providers in entry.providers, when that list is not empty
     and (jsonb_array_length(coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb)) = 0
          or coalesce(security.toolset_setting('pipeline', 'entry.providers'), '[]'::jsonb) ? p_provider::text)$n$]], array[1]);
