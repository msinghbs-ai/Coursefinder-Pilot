-- CF-247 (18 Oct 2026): Providers › Logos & assets reviewed (Platform Admin 12:43: "see if UI Providers > Logo & asset provides any
-- benefits otherwise retire and save DB space or functions/scripts").
-- Kept: the screen is the only place a person sees which universities have no logo and adds one (upload, image address or the logo
-- finder), and approved logos are what the website API sends (Decision 259). 1,995 of 3,101 providers have a logo; the logo-find job
-- runs every 10 minutes.
-- Retired: what is left of the earlier logo-discovery pipeline. The screen's counts still looked at pipeline.provider_asset_candidates
-- (582 rows, no new row since that pipeline stopped) and the operation provider_asset_context, which nothing calls any more.
-- public.layer2_hotcourses_directory_apply (the only writer of those candidates) has no caller and no job.
-- 1 security.admin_provider_asset_read: the summary and the coverage list read approved logos only (a provider has a logo or not);
--   provider_asset_context is no longer offered. Same arguments, same keys the screen uses.
-- 2 pipeline.provider_asset_candidates and public.layer2_hotcourses_directory_apply marked retiring (dropped by a paste file after
--   hygiene.retire_after_days, once nothing uses them).
-- Not touched: catalogue.provider_assets, the logo store, api.website_v2_provider_logo and everything else the website reads (Decision 266).
-- Replaces: security.admin_provider_asset_read (earlier logo-discovery counts)
-- Retires: pipeline.provider_asset_candidates; public.layer2_hotcourses_directory_apply(uuid, jsonb)
-- Nothing dropped or deleted.

do $guard$ begin
  if md5(pg_get_functiondef('security.admin_provider_asset_read(text,jsonb)'::regprocedure)) <> 'c7f5f096a9bb09eddb91beef4540bc14' then
    raise exception 'security.admin_provider_asset_read is not the definition this change replaces';
  end if;
end $guard$;

CREATE OR REPLACE FUNCTION security.admin_provider_asset_read(p_operation text, p_args jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'catalogue', 'pipeline', 'ref', 'ranking', 'auth'
AS $function$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);  -- fixed: page size bounds
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_country text:=upper(nullif(btrim(p_args->>'country_code'),''));
  v_query text:=nullif(btrim(p_args->>'query'),'');
  v_state text:=nullif(btrim(p_args->>'state'),'');
  v_codes text[]:=security.catalogue_country_codes_v1();
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'assigned StudySearch role required' using errcode='42501'; end if;

  if p_operation in ('provider_asset_summary','provider_asset_coverage') then
    return (
      with university_scope as (
        select distinct p.id provider_id,p.stable_key,coalesce(p.display_name,p.canonical_name) provider_name,p.website,p.lifecycle_status,
          c.iso_alpha2 country_code,c.name country_name
        from catalogue.providers p
        join ref.countries c on c.id=p.country_id
        join (
          select provider_id from ranking.observations where provider_id is not null
          union
          select provider_id from ranking.observation_provider_links
        ) r on r.provider_id=p.id
        where c.iso_alpha2::text = any(v_codes)
          and coalesce(p.lifecycle_status,'active')='active'
          and (v_country is null or c.iso_alpha2=v_country)
          and (v_query is null or p.canonical_name ilike '%'||v_query||'%' or coalesce(p.display_name,'') ilike '%'||v_query||'%' or coalesce(p.stable_key,'') ilike '%'||v_query||'%')
      ), base as (
        select u.*,
          pa.id primary_asset_id,pa.source_url primary_source_url,pa.evidence_id primary_evidence_id,pa.storage_path primary_storage_path,
          pa.mime_type primary_mime_type,pa.content_hash primary_content_hash,pa.verified_at primary_verified_at,
          case when pa.id is not null then 'approved' else 'missing' end coverage_state
        from university_scope u
        left join lateral (
          select x.* from catalogue.provider_assets x where x.provider_id=u.provider_id and x.is_primary and x.status='approved'
            and x.asset_type in ('logo','logo_dark','logo_light')
          order by x.verified_at desc nulls last,x.id limit 1
        ) pa on true
      ), filtered as (select * from base where p_operation='provider_asset_summary' or v_state is null or coverage_state=v_state),
      page as (
        select * from filtered order by case coverage_state when 'missing' then 1 else 2 end,
          lower(provider_name),provider_id limit v_limit offset v_offset
      )
      select case when p_operation='provider_asset_summary' then
        jsonb_build_object('scope_basis','Universities in the catalogue countries with an accepted ranking mapping',
          'country_code',v_country,'expected',(select count(*) from filtered),
          'approved',(select count(*) from filtered where coverage_state='approved'),
          'missing',(select count(*) from filtered where coverage_state='missing'))
      else jsonb_build_object('total',(select count(*) from filtered),'limit',v_limit,'offset',v_offset,
        'items',coalesce((select jsonb_agg(to_jsonb(page)) from page),'[]'::jsonb)) end
    );
  end if;
  raise exception 'unsupported provider asset read operation: %',p_operation using errcode='22023';
end
$function$;

update pipeline.component_register set status = 'retiring', retire_after = current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
       replaced_by = 'Logo finder (job logo-find) and the Logos & assets screen', updated_at = now(),
       note = coalesce(note || '; ', '') || '18 Oct 2026: earlier logo-discovery candidates; nothing reads them after 20261018060000'
 where kind = 'table' and name = 'pipeline.provider_asset_candidates';
insert into pipeline.component_register(kind, name, layer, purpose, status, replaced_by, introduced_in, retire_after, note)
values ('function', 'public.layer2_hotcourses_directory_apply', 'L2 read', 'Earlier directory import that proposed logo candidates', 'retiring',
        'Logo finder (job logo-find)', null, current_date + security.pipeline_num_v1('hygiene.retire_after_days', 14)::int,
        '18 Oct 2026: no caller and no job')
on conflict (kind, name) do update set status = 'retiring', retire_after = excluded.retire_after, replaced_by = excluded.replaced_by, note = excluded.note, updated_at = now();

do $post$
declare v_n int;
begin
  if (select count(*) from pg_proc p where p.oid = 'security.admin_provider_asset_read(text,jsonb)'::regprocedure and p.prosrc ~ 'provider_asset_candidates') > 0 then
    raise exception 'post-check: the read still names the candidates';
  end if;
  select count(*) into v_n from pg_proc p where p.prosrc ~ '\mprovider_asset_candidates\M'
     and p.proname not in ('layer2_hotcourses_directory_apply', 'layer2_provider_asset_promotion_context');
  if v_n > 0 then raise exception 'post-check: % other functions still read the candidates', v_n; end if;
  if (select count(*) from pipeline.component_register where status = 'retiring' and name in ('pipeline.provider_asset_candidates', 'public.layer2_hotcourses_directory_apply')) <> 2 then
    raise exception 'post-check: register';
  end if;
end $post$;
