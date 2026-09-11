begin;

-- CF-093 forward-only finalizer: keep Preview binding aligned with the discovery worker.
-- Dotted-numeric hosts are accepted only in canonical decimal IPv4 form. This is
-- deliberately fail-closed relative to WHATWG legacy-octal forms.
create or replace function security.scheduler_workflow_https_host_v1(p_url text)
returns text
language plpgsql
immutable
security invoker
set search_path=''
as $function$
declare
  v_url text:=nullif(trim(coalesce(p_url,'')),'');
  v_match text[];
  v_port integer;
  v_parts text[];
  v_part text;
  v_octet integer;
begin
  if v_url is null or v_url ~ '[[:space:]]' then return null; end if;
  v_match:=regexp_match(v_url,'^https://([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?(?:[/?#].*)?$','i');
  if v_match is null then return null; end if;
  if v_match[1] is null or v_match[1] ~ '\.\.' or v_match[1] ~ '(^[.-]|[.-]$)' then return null; end if;
  if v_match[1] ~ '^[0-9.]+$' then
    v_parts:=regexp_split_to_array(v_match[1],'\.');
    if coalesce(array_length(v_parts,1),0)<>4 then return null; end if;
    foreach v_part in array v_parts loop
      if v_part !~ '^(0|[1-9][0-9]{0,2})$' then return null; end if;
      begin v_octet:=v_part::integer; exception when others then return null; end;
      if v_octet<0 or v_octet>255 then return null; end if;
    end loop;
  end if;
  if v_match[2] is not null then
    begin v_port:=v_match[2]::integer; exception when others then return null; end;
    if v_port<0 or v_port>65535 then return null; end if;
  end if;
  return lower(v_match[1]);
end
$function$;
revoke all on function security.scheduler_workflow_https_host_v1(text) from public,anon,authenticated;

-- Bind discovery Preview to all live course inputs used to expand a
-- first_party_search {query}. Any code/title change therefore invalidates the token.
create or replace function security.scheduler_workflow_scope_snapshot_v2(
  p_country_code text,
  p_scope_type text,
  p_scope_id uuid default null
) returns jsonb
language sql
stable
security definer
set search_path=''
as $function$
  with scoped_base as materialized (
    select sc.profile_id,sc.course_id,sc.source_url,lp.current_version_id,pv.configuration,
           c.course_code,c.canonical_title,c.display_title
    from public.layer2_scope_courses(upper(p_country_code),lower(p_scope_type),p_scope_id) sc
    join pipeline.layer2_source_profiles lp on lp.id=sc.profile_id
    join pipeline.layer2_source_profile_versions pv on pv.id=lp.current_version_id
    join catalogue.courses c on c.id=sc.course_id
  ), scoped as materialized (
    select profile_id,course_id,source_url,current_version_id,course_code,canonical_title,display_title,
      case when source_url is null then
        case
          when lower(coalesce(configuration#>>'{discovery_strategy,type}',''))='first_party_search'
               and nullif(trim(coalesce(configuration#>>'{discovery_strategy,search_url_template}','')),'') is not null
            then trim(configuration#>>'{discovery_strategy,search_url_template}')
          when nullif(trim(coalesce(configuration#>>'{discovery_strategy,catalogue_url}','')),'') is not null
            then trim(configuration#>>'{discovery_strategy,catalogue_url}')
          else nullif(trim(coalesce(configuration->>'discovery_url','')),'')
        end
      else null end as discovery_target
    from scoped_base
  ), profile_ids as (
    select coalesce(array_agg(distinct profile_id order by profile_id),'{}'::uuid[]) ids from scoped
  ), counts as (
    select count(*) filter (where source_url is not null)::integer queueable_count,
           count(*) filter (where source_url is null)::integer needs_discovery_count,
           count(*)::integer scoped_course_count,
           coalesce(md5(string_agg(
             profile_id::text||':'||current_version_id::text||':'||course_id::text||':'||
             case when source_url is not null then source_url else
               '<discover:'||coalesce(discovery_target,'')||
               ':query-inputs:'||coalesce(course_code,'')||':'||coalesce(canonical_title,'')||':'||coalesce(display_title,'')||'>'
             end,
             '|' order by profile_id,current_version_id,course_id,
             coalesce(source_url,
               '<discover:'||coalesce(discovery_target,'')||
               ':query-inputs:'||coalesce(course_code,'')||':'||coalesce(canonical_title,'')||':'||coalesce(display_title,'')||'>')
           )),md5('')) scope_fingerprint
    from scoped
  )
  select jsonb_build_object(
    'profile_ids',to_jsonb(profile_ids.ids),
    'queueable_count',counts.queueable_count,
    'needs_discovery_count',counts.needs_discovery_count,
    'scoped_course_count',counts.scoped_course_count,
    'scope_fingerprint',counts.scope_fingerprint
  )
  from profile_ids cross join counts
$function$;
revoke all on function security.scheduler_workflow_scope_snapshot_v2(text,text,uuid) from public,anon,authenticated;

commit;
