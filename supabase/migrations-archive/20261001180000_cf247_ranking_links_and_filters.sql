-- CF-247 (Decision 208): QS and THE rankings — filters by country, state and provider; ranked universities linked to
-- providers, kept linked automatically for every country.
-- Found on 1 Oct 2026: QS and THE institutions are linked to providers only once, when an edition is imported (exact
-- name and country). A provider added later (a new country such as New Zealand or Canada, or a renamed university) is
-- never linked to the editions already held, and there was no way for a person to link one. Unlinked in catalogue
-- countries: Australia 5, New Zealand 3, Canada 19 publisher names.
--
-- Linking rules (security.ranking_link_auto_v1, job ranking-link every hour, and after each change):
--   1. the publisher's name equals one provider's name in the same country (letters and digits compared);
--   2. or equals one provider alias in the same country;
--   3. or, after dropping a leading "The", anything in brackets and anything after "|", equals one provider's name or
--      alias in the same country AND that provider is already linked under the same name from the other ranking or
--      another edition (two independent sources agree).
--   Anything else is never linked automatically: up to three providers sharing most words are offered to a person
--   (ranking.provider_mappings status 'candidate'), who links or rejects them (Curator and above).
-- A link applies to every edition of that publisher institution, and the publisher's name is kept as a provider alias
-- (alias type <system>_publisher_name), so the next edition links at import. A link is never changed automatically.

-- Name key: lower case, accents dropped, no leading "The", nothing in brackets or after "|", letters and digits only.
create or replace function security.ranking_name_key(p text) returns text
language sql immutable set search_path = '' as $fn$
  select regexp_replace(regexp_replace(regexp_replace(translate(lower(split_part(coalesce(p, ''), '|', 1)), 'àáâãäåāçćčèéêëēěìíîïīñńòóôõöøōùúûüūýÿžšœæ’', 'aaaaaaaccceeeeeeiiiiinnooooooouuuuuyyzsoa'''), '\([^)]*\)', '', 'g'), '^\s*the\s+', ''), '[^a-z0-9]+', '', 'g')
$fn$;

-- Country of a publisher's country text (name, ISO alpha-2 or alpha-3).
create or replace function security.ranking_country_id(p text) returns uuid
language sql stable security definer set search_path = '' as $fn$
  select c.id from ref.countries c
   where lower(c.name) = lower(btrim(p)) or lower(c.iso_alpha2::text) = lower(btrim(p)) or lower(c.iso_alpha3::text) = lower(btrim(p))
   order by (lower(c.name) = lower(btrim(p))) desc limit 1
$fn$;

-- Words used to offer candidates (common words left out).
create or replace function security.ranking_name_words(p text) returns text[]
language sql immutable set search_path = '' as $fn$
  select coalesce(array_agg(distinct w), '{}') from regexp_split_to_table(regexp_replace(translate(lower(split_part(coalesce(p, ''), '|', 1)), 'àáâãäåāçćčèéêëēěìíîïīñńòóôõöøōùúûüūýÿžšœæ’', 'aaaaaaaccceeeeeeiiiiinnooooooouuuuuyyzsoa'''), '[^a-z0-9]+', ' ', 'g'), '\s+') w
   where length(w) > 1 and w not in ('the','of','and','at','in','for','university','universit','universite','college','institute','institut','de','du','des','la','le','les','et','school','inc','ltd','limited','campus','including')
$fn$;

-- Link one publisher institution to a provider: the mapping, every edition's observations, the equivalent-provider
-- links and the alias for future imports. Refuses a second, different link.
create or replace function security.ranking_link_apply_v1(p_pub uuid, p_provider uuid, p_method text, p_note text, p_actor uuid) returns int
language plpgsql security definer set search_path = '' as $fn$
declare v_pi ranking.publisher_institutions%rowtype; v_sys text; v_cur uuid; v_equiv uuid[]; v_n int := 0; o record; v_pid uuid;
begin
  select * into v_pi from ranking.publisher_institutions where id = p_pub;
  if v_pi.id is null then raise exception 'publisher institution not found'; end if;
  select code into v_sys from ranking.systems where id = v_pi.system_id;
  select provider_id into v_cur from ranking.provider_mappings where publisher_institution_id = p_pub and status = 'accepted' and valid_to is null;
  if v_cur is not null and v_cur <> p_provider then raise exception 'already linked to another provider'; end if;
  if v_cur is null then
    update ranking.provider_mappings set status = 'superseded' where publisher_institution_id = p_pub and status = 'candidate';
    insert into ranking.provider_mappings(publisher_institution_id, provider_id, mapping_method, confidence, status, reviewed_by, reviewed_at, note)
    values (p_pub, p_provider, p_method, 1.0, 'accepted', p_actor, now(), p_note);
  end if;
  v_equiv := public.svc_statistical_equivalent_provider_ids(p_provider);
  for o in select id from ranking.observations where publisher_institution_id = p_pub and provider_id is null loop
    update ranking.observations set provider_id = p_provider where id = o.id;
    foreach v_pid in array v_equiv loop
      insert into ranking.observation_provider_links(observation_id, provider_id, link_method, is_primary)
      values (o.id, v_pid, case when v_pid = p_provider then 'primary_' || p_method else 'equivalent_exact_name_or_identifier' end, v_pid = p_provider)
      on conflict do nothing;
    end loop;
    v_n := v_n + 1;
  end loop;
  insert into catalogue.provider_aliases(provider_id, alias, alias_type)
  values (p_provider, v_pi.institution_name, v_sys || '_publisher_name')
  on conflict (provider_id, alias, coalesce(locale, '')) do nothing;
  return v_n;
end $fn$;
revoke all on function security.ranking_link_apply_v1(uuid, uuid, text, text, uuid) from public, anon, authenticated;

-- Automatic linking for every country that has providers in the catalogue; candidates for the rest.
create or replace function security.ranking_link_auto_v1() returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare u record; v_ids uuid[]; v_linked int := 0; v_obs int := 0; v_cand int := 0; v_k int; v_method text;
begin
  for u in
    select pi.id, pi.institution_name, s.code sys, security.ranking_country_id(pi.country_text) cid,
           lower(regexp_replace(pi.institution_name, '[^A-Za-z0-9]+', '', 'g')) compact, security.ranking_name_key(pi.institution_name) nkey
      from ranking.publisher_institutions pi join ranking.systems s on s.id = pi.system_id
     where not exists (select 1 from ranking.provider_mappings m where m.publisher_institution_id = pi.id and m.status = 'accepted' and m.valid_to is null)
       and exists (select 1 from catalogue.providers p where p.country_id = security.ranking_country_id(pi.country_text) and p.lifecycle_status = 'active')
  loop
    v_method := null;
    -- 1. exact name
    select array_agg(p.id) into v_ids from catalogue.providers p
     where p.country_id = u.cid and p.lifecycle_status = 'active'
       and lower(regexp_replace(coalesce(p.display_name, p.canonical_name), '[^A-Za-z0-9]+', '', 'g')) = u.compact;
    if cardinality(v_ids) = 1 then v_method := 'exact_canonical_name_country'; end if;
    -- 2. exact alias
    if v_method is null then
      select array_agg(distinct p.id) into v_ids from catalogue.provider_aliases a join catalogue.providers p on p.id = a.provider_id
       where p.country_id = u.cid and p.lifecycle_status = 'active' and a.valid_to is null
         and lower(regexp_replace(a.alias, '[^A-Za-z0-9]+', '', 'g')) = u.compact;
      if cardinality(v_ids) = 1 then v_method := 'accepted_alias_country'; end if;
    end if;
    -- 3. name key, confirmed by an existing link under the same key
    if v_method is null and u.nkey <> '' then
      select array_agg(distinct x.id) into v_ids from (
        select p.id from catalogue.providers p where p.country_id = u.cid and p.lifecycle_status = 'active'
           and security.ranking_name_key(coalesce(p.display_name, p.canonical_name)) = u.nkey
        union
        select p.id from catalogue.provider_aliases a join catalogue.providers p on p.id = a.provider_id
         where p.country_id = u.cid and p.lifecycle_status = 'active' and a.valid_to is null and security.ranking_name_key(a.alias) = u.nkey) x;
      if cardinality(v_ids) = 1 and exists (
           select 1 from ranking.publisher_institutions o join ranking.provider_mappings m on m.publisher_institution_id = o.id
            where o.id <> u.id and m.status = 'accepted' and m.valid_to is null and m.provider_id = v_ids[1]
              and security.ranking_name_key(o.institution_name) = u.nkey) then
        v_method := 'name_key_confirmed';
      end if;
    end if;
    if v_method is not null then
      v_obs := v_obs + security.ranking_link_apply_v1(u.id, v_ids[1], v_method, 'Linked automatically (Decision 208 rules)', null);
      v_linked := v_linked + 1;
    else
      -- candidates for a person: providers in the same country sharing most words (at least half of all words)
      insert into ranking.provider_mappings(publisher_institution_id, provider_id, mapping_method, confidence, status, note)
      select u.id, c.id, 'suggested_shared_words', round(c.score, 2), 'candidate', 'Offered for a person to check'
        from (select p.id, (select count(*) from unnest(security.ranking_name_words(u.institution_name)) w where w = any(security.ranking_name_words(coalesce(p.display_name, p.canonical_name))))::numeric
                     / greatest(1, (select count(distinct w) from unnest(security.ranking_name_words(u.institution_name) || security.ranking_name_words(coalesce(p.display_name, p.canonical_name))) w)) score
                from catalogue.providers p where p.country_id = u.cid and p.lifecycle_status = 'active'
                 and security.ranking_name_words(coalesce(p.display_name, p.canonical_name)) && security.ranking_name_words(u.institution_name)) c
       where c.score >= 0.5
         and not exists (select 1 from ranking.provider_mappings m where m.publisher_institution_id = u.id and m.provider_id = c.id)
       order by c.score desc limit 3;
      get diagnostics v_k = row_count;
      v_cand := v_cand + v_k;
    end if;
  end loop;
  return jsonb_build_object('linked', v_linked, 'observations_linked', v_obs, 'candidates_added', v_cand, 'ran_at', now());
end $fn$;
revoke all on function security.ranking_link_auto_v1() from public, anon, authenticated;

-- Reads for the ranking screens and the provider record (Viewer and above).
create or replace function security.admin_ranking_links_read(p_operation text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $fn$
declare v_rank int := security.current_role_rank(); v_system text := nullif(p_args->>'system_code', ''); v_year int := nullif(p_args->>'edition_year', '')::int;
        v_country text := nullif(p_args->>'country', ''); v_provider uuid := nullif(p_args->>'provider_id', '')::uuid; v_query text := nullif(btrim(p_args->>'query'), '');
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned CourseFinder role required' using errcode = '42501'; end if;
  if p_operation = 'ranking_filter_options' then
    return (with base as (
        select pi.country_text, o.provider_id, coalesce(p.display_name, p.canonical_name) provider_name, sd.code state_code, sd.name state_name
          from ranking.observations o join ranking.editions e on e.id = o.edition_id join ranking.systems s on s.id = e.system_id
          join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
          left join catalogue.providers p on p.id = o.provider_id left join ref.subdivisions sd on sd.id = p.subdivision_id
         where e.status = 'accepted' and (v_system is null or s.code = v_system) and (v_year is null or e.edition_year = v_year))
      select jsonb_build_object(
        'can_link', v_rank >= 3,
        'countries', coalesce((select jsonb_agg(jsonb_build_object('value', country_text, 'count', n,
                        'in_catalogue', exists (select 1 from catalogue.providers p2 where p2.country_id = security.ranking_country_id(q.country_text) and p2.lifecycle_status = 'active')) order by n desc, country_text)
                        from (select country_text, count(*) n from base where country_text is not null group by 1) q), '[]'::jsonb),
        'states', coalesce((select jsonb_agg(jsonb_build_object('value', state_code, 'label', state_name, 'count', n) order by state_name)
                        from (select state_code, state_name, count(*) n from base where state_code is not null and (v_country is null or country_text = v_country) group by 1, 2) q), '[]'::jsonb),
        'providers', coalesce((select jsonb_agg(jsonb_build_object('value', provider_id, 'label', provider_name) order by provider_name)
                        from (select distinct provider_id, provider_name from base where provider_id is not null and (v_country is null or country_text = v_country)) q), '[]'::jsonb),
        'linked', (select count(*) from base where provider_id is not null and (v_country is null or country_text = v_country)),
        'not_linked', (select count(*) from base where provider_id is null and (v_country is null or country_text = v_country)),
        'not_linked_in_catalogue_countries', (select count(*) from base b where b.provider_id is null and (v_country is null or b.country_text = v_country)
                        and exists (select 1 from catalogue.providers p2 where p2.country_id = security.ranking_country_id(b.country_text) and p2.lifecycle_status = 'active'))));
  elsif p_operation = 'ranking_link_candidates' then
    return jsonb_build_object('can_link', v_rank >= 3, 'items', coalesce((select jsonb_agg(jsonb_build_object('provider_id', m.provider_id,
             'provider_name', coalesce(p.display_name, p.canonical_name), 'state', sd.code, 'confidence', m.confidence) order by m.confidence desc)
             from ranking.provider_mappings m join catalogue.providers p on p.id = m.provider_id left join ref.subdivisions sd on sd.id = p.subdivision_id
            where m.publisher_institution_id = nullif(p_args->>'publisher_institution_id', '')::uuid and m.status = 'candidate'), '[]'::jsonb));
  elsif p_operation = 'ranking_provider_search' then
    if v_query is null or length(v_query) < 3 then return jsonb_build_object('items', '[]'::jsonb); end if;
    return jsonb_build_object('items', coalesce((select jsonb_agg(x) from (
             select jsonb_build_object('provider_id', p.id, 'provider_name', coalesce(p.display_name, p.canonical_name), 'state', sd.code) x
               from catalogue.providers p left join ref.subdivisions sd on sd.id = p.subdivision_id
              where p.lifecycle_status = 'active' and (v_country is null or p.country_id = security.ranking_country_id(v_country))
                and (coalesce(p.display_name, p.canonical_name) ilike '%' || v_query || '%'
                     or exists (select 1 from catalogue.provider_aliases a where a.provider_id = p.id and a.valid_to is null and a.alias ilike '%' || v_query || '%'))
              order by length(coalesce(p.display_name, p.canonical_name)) limit 20) q), '[]'::jsonb));
  elsif p_operation = 'provider_ranking_history' then
    return jsonb_build_object('items', coalesce((select jsonb_agg(jsonb_build_object('system_code', s.code, 'ranking_name', s.ranking_name, 'edition_year', e.edition_year,
             'rank_display', o.rank_display, 'rank_exact', o.rank_exact, 'overall_score', o.overall_score, 'publisher_name', pi.institution_name,
             'evidence_artifact_id', o.evidence_artifact_id) order by s.code, e.edition_year desc)
             from ranking.observation_provider_links l join ranking.observations o on o.id = l.observation_id
             join ranking.editions e on e.id = o.edition_id and e.status = 'accepted' join ranking.systems s on s.id = e.system_id
             join ranking.publisher_institutions pi on pi.id = o.publisher_institution_id
            where l.provider_id = v_provider), '[]'::jsonb));
  end if;
  raise exception 'unsupported ranking link read: %', p_operation using errcode = '22023';
end $fn$;
revoke all on function security.admin_ranking_links_read(text, jsonb) from public, anon, authenticated;

-- Write: link a publisher institution to a provider, or reject a candidate (Curator and above); run the rules now
-- (Pipeline Operator and above). The provider must be in the publisher's country.
create or replace function public.admin_ranking_link(p_publisher_institution_id uuid, p_action text, p_provider_id uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_rank int := security.current_role_rank(); v_cid uuid; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role required' using errcode = '42501'; end if;
  if p_action = 'run_rules' then
    if v_rank < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
    return security.ranking_link_auto_v1();
  end if;
  if p_action not in ('link', 'reject') or p_provider_id is null then raise exception 'action must be link or reject, with a provider'; end if;
  select security.ranking_country_id(country_text) into v_cid from ranking.publisher_institutions where id = p_publisher_institution_id;
  if not found then raise exception 'publisher institution not found'; end if;
  if p_action = 'reject' then
    update ranking.provider_mappings set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), note = coalesce(left(p_note, 300), note)
     where publisher_institution_id = p_publisher_institution_id and provider_id = p_provider_id and status = 'candidate';
    return jsonb_build_object('rejected', true);
  end if;
  if not exists (select 1 from catalogue.providers p where p.id = p_provider_id and p.lifecycle_status = 'active' and (v_cid is null or p.country_id = v_cid)) then
    raise exception 'the provider must be active and in the same country as the ranked university';
  end if;
  v_n := security.ranking_link_apply_v1(p_publisher_institution_id, p_provider_id, 'manual_person', left(coalesce(p_note, 'Linked by a person'), 300), auth.uid());
  return jsonb_build_object('linked', true, 'observations_linked', v_n);
end $fn$;
revoke all on function public.admin_ranking_link(uuid, text, uuid, text) from public, anon;
grant execute on function public.admin_ranking_link(uuid, text, uuid, text) to authenticated;

-- Ranking observations: filters by country, state and link; each row carries its publisher institution and state.
do $obs$
declare s text; d text; v text; ops text[][] := array[
  array[E'  v_query text:=nullif(btrim(p_args->>''query''),'''');\n',
        E'  v_query text:=nullif(btrim(p_args->>''query''),'''');\n  v_country text:=nullif(p_args->>''country'','''');\n  v_state text:=nullif(p_args->>''state'','''');\n  v_link text:=nullif(p_args->>''link'','''');\n'],
  array[E'o.overall_score,o.evidence_artifact_id\n        from ranking.observations o',
        E'o.overall_score,o.evidence_artifact_id,o.publisher_institution_id,sd.code state_code,sd.name state_name\n        from ranking.observations o'],
  array[E'left join catalogue.providers p on p.id=o.provider_id\n        where e.status=''accepted''',
        E'left join catalogue.providers p on p.id=o.provider_id\n        left join ref.subdivisions sd on sd.id=p.subdivision_id\n        where e.status=''accepted'''],
  array[E'coalesce(p.display_name,p.canonical_name) ilike ''%''||v_query||''%'')\n',
        E'coalesce(p.display_name,p.canonical_name) ilike ''%''||v_query||''%'')\n          and (v_country is null or pi.country_text=v_country)\n          and (v_state is null or sd.code=v_state)\n          and (v_link is null or (v_link=''linked'' and o.provider_id is not null) or (v_link=''not_linked'' and o.provider_id is null))\n']];
  i int;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'security' and p.proname = 'admin_ranking_read';
  v := md5(s);
  if v is distinct from '086eea02884a7a4b42a0beb00ba237be' then raise exception 'admin_ranking_read changed (md5 %); not replacing', v; end if;
  for i in 1 .. array_length(ops, 1) loop
    if (length(d) - length(replace(d, ops[i][1], ''))) / length(ops[i][1]) <> 1 then raise exception 'admin_ranking_read: change % not found once', i; end if;
    d := replace(d, ops[i][1], ops[i][2]);
  end loop;
  execute d;
end $obs$;

-- Route the new reads through public.admin_read.
do $rd$
declare s text; d text; v text;
  o text := E' if p_operation in (''ranking_summary'',''ranking_filters'',''ranking_observations'') then return security.admin_ranking_read(p_operation,p_args); end if;\n';
  n text := E' if p_operation in (''ranking_summary'',''ranking_filters'',''ranking_observations'') then return security.admin_ranking_read(p_operation,p_args); end if;\n'
         || E' if p_operation in (''ranking_filter_options'',''ranking_link_candidates'',''ranking_provider_search'',''provider_ranking_history'') then return security.admin_ranking_links_read(p_operation,p_args); end if;\n';
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'admin_read';
  v := md5(s);
  if v is distinct from 'e34209c2d0b480cf04c36ea8d6058b85' then raise exception 'admin_read changed (md5 %); not replacing', v; end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'admin_read: ranking route not found once'; end if;
  execute replace(d, o, n);
end $rd$;

-- Keep links up to date: every hour, so a new provider or country is linked to the editions already held.
select cron.unschedule(jobid) from cron.job where jobname = 'ranking-link';
select cron.schedule('ranking-link', '37 * * * *', $$select security.ranking_link_auto_v1()$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('ranking-link', 'Layer 1 register', 60, 'Link ranked universities to providers',
        'Links QS and THE universities to providers in the same country when the names agree (Decision 208 rules), for every edition held; offers close matches to a person. Never changes a link.', 5, false)
on conflict (jobname) do update set area = excluded.area, sort = excluded.sort, label = excluded.label, description = excluded.description,
       control_rank = excluded.control_rank, batch_editable = excluded.batch_editable;

select security.ranking_link_auto_v1();
