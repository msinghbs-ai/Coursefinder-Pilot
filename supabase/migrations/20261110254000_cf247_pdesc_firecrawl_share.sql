-- CF-247 F-PDESC follow-up (live, 10 Nov 2026 23:36 AEDT; Platform Admin direction 23:02 "use Firecrawl as much as needed"): with the
-- provider-description Firecrawl allowance open (20261110250000), every Firecrawl read was still refused by the shared daily budget
-- (credits_refused): purpose provider_description fell in group "other" (daily_share_other 200 credits), which discovery search (124 credits)
-- and site maps (73) use up early each day (613 "share" refusals in group other today), while the day total (4,000) had 1,434 used.
-- Now provider descriptions have their own group "pdesc" and their own daily share (Firecrawl settings > Daily budget > daily_share_pdesc,
-- 300 credits, the same as pdesc.firecrawl_reads_max a day). The day total, the monthly plan limit, the cost breakers and every other
-- group's share are unchanged. Screens that list the fixed groups (admin_progress_read, admin_enrich_fields) do not show the new group yet.
-- No consumer object (G3). Forward recovery: the inverse replacement in fc_purpose_group_v1 (md5 348bbb9e...).
-- Replaces: group "other" for purpose provider_description (now group "pdesc").
-- Retires: nothing.

do $f$
declare d text := pg_get_functiondef('security.fc_purpose_group_v1(text)'::regprocedure);
        o text := $o$  select case when p = 'course_link_search' then 'course_search'$o$;
        n text := $n$  select case when p = 'course_link_search' then 'course_search'
              when p = 'provider_description' then 'pdesc'  -- 20261110254000: provider descriptions have their own daily share$n$;
begin
  if md5(d) <> '348bbb9ec1db966755e532f23e376897' then raise exception 'fc_purpose_group_v1 is not the reviewed body (%)', md5(d); end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'fc_purpose_group_v1: anchor not found exactly once'; end if;
  execute replace(d, o, n);
  if security.fc_purpose_group_v1('provider_description') <> 'pdesc' or security.fc_purpose_group_v1('search') <> 'other' or security.fc_purpose_group_v1('sch_map') <> 'scholarships' then
    raise exception 'post-check: fc_purpose_group_v1 mapping';
  end if;
end $f$;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('firecrawl', 'daily_share_pdesc', 'Daily share: provider descriptions',
        'Firecrawl credits a day for provider About and home pages a site refused to a direct read (purpose provider_description). Inside the day total; the provider-description allowance (Pipeline settings > Provider descriptions > Firecrawl reads) also applies.',
        'number', '300'::jsonb, 0, 100000, 'credits', 661, 'Daily budget', 'security.fc_budget_left_v1; public.svc_fc_spend',
        'Platform Admin direction 10 Nov 2026 23:02 AEDT: use Firecrawl as much as needed for provider descriptions (20261110254000)')
on conflict (toolset_key, key) do nothing;

do $post$
begin
  if security.fc_setting_num_v1('daily_share_pdesc', 0) <> 300 then raise exception 'post-check: daily_share_pdesc'; end if;
end $post$;
