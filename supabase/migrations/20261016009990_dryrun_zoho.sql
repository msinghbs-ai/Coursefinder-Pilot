-- CF-247 (23 Oct 2026). The course source finder's test runs used 126 list-page scrapes; the spend ledger counted each as 5 units because
-- purposes named fcx_ are priced as AI-extraction scrapes, though a list page is a plain page scrape billed at 1 credit (731 units recorded
-- for about 227 credits billed). Worker v0.40.4 records these scrapes as list_scrape; this puts list_scrape in the page reads group
-- with the other plain scrapes, so it keeps the same daily share.
-- Replaces: security.fc_purpose_group_v1 (replaced in full; adds list_scrape to the reads group)
-- Retires: nothing
create or replace function security.fc_purpose_group_v1(p text)
returns text language sql immutable set search_path = '' as $function$
  select case when p = 'course_link_search' then 'course_search'
              when p like 'sch\_%' then 'scholarships'
              when p in ('central_map', 'central_scrape') or p like 'provider\_facts%' then 'central'
              when p in ('scrape', 'fc_read', 'fc_probe', 'site_hint', 'adapter_builder', 'list_scrape') or p like 'fcx\_%' then 'reads'
              else 'other' end
$function$;

select 'list_scrape counted as a page read' ok;

do $t$ begin raise exception 'DRYRUN OK %', jsonb_build_object('list_scrape', security.fc_purpose_group_v1('list_scrape'), 'fcx', security.fc_purpose_group_v1('fcx_course_list'), 'scrape', security.fc_purpose_group_v1('scrape'), 'sch', security.fc_purpose_group_v1('sch_map'), 'other', security.fc_purpose_group_v1('map')); end $t$;
