CREATE OR REPLACE FUNCTION security.ranking_link_auto_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$
