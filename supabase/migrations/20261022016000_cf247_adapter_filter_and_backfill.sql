-- CF-247 (22 Oct 2026). Platform Admin 11:47: "Feature - have a filter for Adapter and adapter status (admitting/testing etc) and Column
-- for Adapter status that can be ordered Create adapters for All Universities where website were found. this has been requested before."
-- Choice "All 738 with a website".
-- Found: every university already has an adapter (AU 45, NZ 8; 52 admitting, Otago testing). The 738 published providers with their own
-- website and no adapter are polytechnics, private providers and Canadian colleges (CA 424, NZ 279, AU 35); 536 never entered onboarding,
-- 190 stopped there (too few course pages, one proposal failed), 12 are finding course pages now.
--   1 security.provider_adapter_status_v1(provider): admitting, testing, building, off or none (as the Adapter column shows).
--   2 security.admin_providers_page_v2: admin_providers_page with p_adapter (any, admitting, testing, building, off, none), the
--     adapter_status column and sort 'adapter' (admitting, testing, building, off, none); security.admin_catalogue_page calls it with
--     p_args->>'adapter'. The old function stays until nothing calls it (marked retiring).
--   3 Onboarding for the 738: the 536 never onboarded are queued (source backfill, larger first); the 190 stopped are queued again. Onboarding
--     finds their course pages and builds the adapter (at most onboarding max_active at once, the adapter AI allowance a day); a provider
--     whose site lists too few course pages stops again with that reason.
-- Replaces: security.admin_catalogue_page (calls admin_providers_page_v2); security.admin_providers_page → security.admin_providers_page_v2. md5-guarded.
-- Retires: security.admin_providers_page (replaced by admin_providers_page_v2)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
begin
  if md5(pg_get_functiondef('security.admin_providers_page(integer,integer,text,text,text,text,text,text,text,text)'::regprocedure)) <> 'bb66c64c1854f8cf2617c2ea7f119b82'
     or md5(pg_get_functiondef('security.admin_catalogue_page(text,jsonb)'::regprocedure)) <> 'e3aa4969b87e63b661e460e828d0cb1a' then
    raise exception 'live admin_providers_page or admin_catalogue_page differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

create or replace function security.provider_adapter_status_v1(p_provider uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select 'building' from pipeline.adapter_autobuilds b where b.provider_id = p_provider and b.status not in ('done', 'failed', 'stopped') limit 1),
    (select case when not u.enabled then 'off' when u.admit then 'admitting' else 'testing' end from pipeline.uni_adapters u where u.provider_id = p_provider),
    'none')
$$;
comment on function security.provider_adapter_status_v1(uuid) is 'CF-247 22 Oct 2026: a provider''s adapter status for the Providers list: building, admitting, testing, off or none.';
revoke all on function security.provider_adapter_status_v1(uuid) from public;

-- 2 the v2 page: made from the live definition (renamed, adapter filter, column and sort); the old one is left as it is
select pg_temp.edit_once('security.admin_providers_page(integer,integer,text,text,text,text,text,text,text,text)', 'bb66c64c1854f8cf2617c2ea7f119b82', array[
  [$o$FUNCTION security.admin_providers_page(p_limit integer DEFAULT 50,$o$, $n$FUNCTION security.admin_providers_page_v2(p_limit integer DEFAULT 50,$n$],
  [$o$p_university_group text DEFAULT NULL::text)$o$, $n$p_university_group text DEFAULT NULL::text, p_adapter text DEFAULT NULL::text)$n$],
  [$o$        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,$o$,
   $n$        (select count(*)::bigint from catalogue.courses cr where cr.provider_id=p.id) course_count,
        -- 22 Oct 2026 (Platform Admin 11:47): adapter status for the Adapter filter and column
        security.provider_adapter_status_v1(p.id) adapter_status,$n$],
  [$o$    ), numbered as (
      select *,count(*) over()::bigint total_count from base$o$,
   $n$    ), filtered as (
      select * from base
       where nullif(trim(coalesce(p_adapter,'')),'') is null
          or (p_adapter = 'any' and adapter_status <> 'none')
          or adapter_status = p_adapter
    ), numbered as (
      select *,count(*) over()::bigint total_count from filtered$n$],
  [$o$        case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,$o$,
   $n$        case when v_sort='adapter' and v_dir='asc' then array_position(array['admitting','testing','building','off','none'], adapter_status) end asc,
        case when v_sort='adapter' and v_dir='desc' then array_position(array['admitting','testing','building','off','none'], adapter_status) end desc,
        case when v_sort='verified' and v_dir='asc' then last_verified_at end asc nulls first,$n$]]);
comment on function security.admin_providers_page_v2(integer,integer,text,text,text,text,text,text,text,text,text) is 'CF-247 22 Oct 2026: Providers list page with the Adapter filter (p_adapter), adapter_status and sort adapter; replaces security.admin_providers_page.';
revoke all on function security.admin_providers_page_v2(integer,integer,text,text,text,text,text,text,text,text,text) from public;

select pg_temp.edit_once('security.admin_catalogue_page(text,jsonb)', 'e3aa4969b87e63b661e460e828d0cb1a', array[
  [$o$return security.admin_providers_page(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),coalesce(nullif(p_args->>'sort',''),'provider'),v_dir,nullif(p_args->>'university_group',''));$o$,
   $n$return security.admin_providers_page_v2(v_limit,v_offset,nullif(p_args->>'query',''),nullif(p_args->>'country_code',''),nullif(p_args->>'subdivision_code',''),nullif(p_args->>'lifecycle_status',''),nullif(p_args->>'publication_status',''),coalesce(nullif(p_args->>'sort',''),'provider'),v_dir,nullif(p_args->>'university_group',''),nullif(p_args->>'adapter',''));$n$]]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.admin_providers_page_v2', 'Catalogue', 'Providers list page with the Adapter filter and column', 'active', array['security.admin_providers_page'], '20261022016000'),
 ('function', 'security.provider_adapter_status_v1', 'Catalogue', 'Adapter status of a provider', 'active', '{}', '20261022016000')
on conflict (kind, name) do nothing;
update pipeline.component_register set status = 'retiring', replaced_by = 'security.admin_providers_page_v2', retire_after = current_date + 14, updated_at = now()
 where kind = 'function' and name = 'security.admin_providers_page';

-- 3 onboarding for every published provider with its own website and no adapter
insert into pipeline.provider_onboarding(provider_id, source, reason, priority)
select p.id, 'backfill', 'Platform Admin 22 Oct 2026 11:47 "Create adapters for All ... where website were found" (choice "All 738 with a website")',
       (select least(count(*), 99999)::int from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
  from catalogue.providers p
 where p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.website), '') is not null
   and not security.third_party_host_v1(p.website)
   and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = p.id)
   and not exists (select 1 from pipeline.provider_onboarding o where o.provider_id = p.id)
on conflict do nothing;
update pipeline.provider_onboarding o set status = 'queued', stop_reason = null, attempts = 0, job_id = null, step_started_at = null,
       note = 'Queued again: Platform Admin 22 Oct 2026 11:47 "Create adapters for All ... where website were found"', updated_at = now()
  from catalogue.providers p
 where p.id = o.provider_id and o.status = 'stopped'
   and p.lifecycle_status = 'active' and p.publication_status = 'published' and nullif(btrim(p.website), '') is not null
   and not security.third_party_host_v1(p.website)
   and not exists (select 1 from pipeline.uni_adapters a where a.provider_id = p.id);
