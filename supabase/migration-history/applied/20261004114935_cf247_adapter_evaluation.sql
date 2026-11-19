-- CF-247 Decision 253 (4 Oct 2026, Platform Admin 22:43): "learn from this adapter exercise and evaluate pending unis
-- and courses for data admission". What Flinders showed, as rules the panel applies to every target university:
--   * many courses with no page: find pages first (Firecrawl search on the university site)
--   * many pages that cannot be read: the course data sits in the page itself or needs a browser, set up an adapter
--     for its page data (as for the CourseLoop handbooks)
--   * pages confirmed but intakes or English mostly missing: the general reader misses how the university prints them,
--     set up an adapter with text patterns (as for the Flinders start dates)
--   * otherwise the university is admitted as it is
-- The three shares are settings (Firecrawl, section Adapter evaluation). The figures come from the kept target figures
-- (refreshed every 5 minutes), so the evaluation loads at once.
-- No text value in this file contains a semicolon.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section) values
  ('firecrawl', 'eval_no_page_share', 'Find pages first above', 'Share of a university''s courses with no page above which its next step is to find pages.', 'number', '0.3', 0, 1, 'share', 400, 'Decision 253, Platform Admin 22:43', 'Adapter evaluation'),
  ('firecrawl', 'eval_unreadable_share', 'Adapter for page data above', 'Share of a university''s courses whose page cannot be read above which its next step is an adapter for the page data.', 'number', '0.2', 0, 1, 'share', 410, 'Decision 253, Platform Admin 22:43', 'Adapter evaluation'),
  ('firecrawl', 'eval_field_share', 'Field found on at least', 'Share of confirmed pages that must give intakes and English. Below it, the next step is an adapter with text patterns.', 'number', '0.5', 0, 1, 'share', 420, 'Decision 253, Platform Admin 22:43', 'Adapter evaluation')
on conflict (toolset_key, key) do nothing;

create or replace function public.admin_adapter_evaluation() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank(); v_np numeric; v_ur numeric; v_fs numeric;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 5 then raise exception 'Platform Admin or Operator required' using errcode = '42501'; end if;
  v_np := coalesce((security.firecrawl_setting('eval_no_page_share') #>> '{}')::numeric, 0.3);
  v_ur := coalesce((security.firecrawl_setting('eval_unreadable_share') #>> '{}')::numeric, 0.2);
  v_fs := coalesce((security.firecrawl_setting('eval_field_share') #>> '{}')::numeric, 0.5);
  return jsonb_build_object('settings', jsonb_build_object('no_page_share', v_np, 'unreadable_share', v_ur, 'field_share', v_fs),
    'universities', coalesce((select jsonb_agg(x order by (x->>'gap')::int desc) from (
      select jsonb_build_object('provider_id', c.provider_id, 'name', c.name, 'country', c.country, 'courses', s.courses, 'confirmed', s.confirmed, 'no_page', s.no_page, 'unreadable', s.unreadable,
               'intakes', s.intakes, 'english', s.english,
               'adapter', case when a.provider_id is null then 'none' when a.admit then 'admitting' when a.enabled then 'testing' else 'off' end,
               'gap', greatest(s.courses - s.intakes, 0) + greatest(s.courses - s.english, 0),
               'next', case when a.admit and a.enabled then 'admitting'
                            when s.courses > 0 and s.no_page::numeric / s.courses >= v_np then 'find_pages'
                            when s.courses > 0 and s.unreadable::numeric / s.courses >= v_ur then 'adapter_page_data'
                            when s.confirmed > 0 and s.intakes::numeric / s.confirmed < v_fs then 'adapter_intakes'
                            when s.confirmed > 0 and s.english::numeric / s.confirmed < v_fs then 'adapter_english'
                            else 'admit_as_is' end) x
      from pipeline.firecrawl_target_cache c
      cross join lateral (select coalesce((c.stats->>'courses')::int, 0) courses, coalesce((c.stats->>'confirmed')::int, 0) confirmed, coalesce((c.stats->>'no_page')::int, 0) no_page,
                                 coalesce((c.stats->>'unreadable')::int, 0) unreadable, coalesce((c.stats->>'intakes')::int, 0) intakes, coalesce((c.stats->>'english')::int, 0) english) s
      left join pipeline.uni_adapters a on a.provider_id = c.provider_id
      where c.included) q), '[]'::jsonb),
    'figures_at', (select max(c.stats_at) from pipeline.firecrawl_target_cache c));
end $f$;
revoke all on function public.admin_adapter_evaluation() from public, anon;
grant execute on function public.admin_adapter_evaluation() to authenticated;
