-- IQ-00055 after the migration: the NEW definitions choose exactly what the OLD ones chose (fx_old_stored, fx_old_next from data.sql),
-- and the prefilter never skips an address the page rule passes. Each check raises on failure and says what it proved.
do $$ declare x record; n int; m int; c int; begin
  for x in select v from fx_variants order by v loop
    perform fx_variant(x.v);
    select count(*), count(*) filter (where o.stored is distinct from security.provider_description_stored_v1(o.provider_id)), count(o.stored)
      into n, m, c from fx_old_stored o where o.v = x.v;
    if m <> 0 then raise exception 'variant %: % of % providers chose a different stored copy', x.v, m, n; end if;
    raise notice 'variant %: same stored copy for % of % providers (% with a copy)', x.v, n, n, c;
    -- the prefilter is a superset of the page rule: every copy the rule passes contains "/<name>" or "/<prefix>"
    select count(*) into m from pipeline.evidence_artifacts a, pipeline.sources s
     where s.id = a.source_id and a.source_url is not null and (security.provider_description_page_v1(s.provider_id, a.source_url)->>'ok')::boolean
       -- the plain containment test, independent of the LIKE escaping the migration uses
       and not exists (select 1 from (select '/' || lower(t) w from jsonb_array_elements_text(security.toolset_setting('pipeline', 'pdesc.about_patterns')) t
                                      union all select '/' || lower(t) from jsonb_array_elements_text(security.toolset_setting('pipeline', 'pdesc.about_prefixes')) t where t <> '') z
                        where strpos(lower(a.source_url), z.w) > 0);
    -- and the LIKE form in stored_v1 is exactly that containment test (no wildcard leaks): same copies kept
    select count(*) into m from pipeline.evidence_artifacts a
     where (exists (select 1 from (select '/' || lower(t) w from jsonb_array_elements_text(security.toolset_setting('pipeline', 'pdesc.about_patterns')) t
                                   union all select '/' || lower(t) from jsonb_array_elements_text(security.toolset_setting('pipeline', 'pdesc.about_prefixes')) t where t <> '') z
                    where strpos(lower(a.source_url), z.w) > 0))
           is distinct from
           (lower(a.source_url) like any (array(select '%/' || replace(replace(replace(lower(t), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                                                  from jsonb_array_elements_text(security.toolset_setting('pipeline', 'pdesc.about_patterns')) t
                                                union all
                                                select '%/' || replace(replace(replace(lower(t), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                                                  from jsonb_array_elements_text(security.toolset_setting('pipeline', 'pdesc.about_prefixes')) t where t <> '')));
    if m <> 0 then raise exception 'variant %: the LIKE prefilter and the containment test differ on % copies', x.v, m; end if;
    -- the first-two-parts check never refuses a copy the page rule passes
    select count(*) into m from pipeline.evidence_artifacts a, pipeline.sources s,
           lateral (select regexp_match(lower(coalesce(substring(a.source_url from '^https?://[^/?#]+(/[^?#]*)'), '')), '^/*([^/]+)(?:/+([^/]+))?') m) g,
           lateral (select array(select lower(t) from jsonb_array_elements_text(security.toolset_setting('pipeline', 'pdesc.about_patterns')) t) names,
                           array(select lower(t) from jsonb_array_elements_text(security.toolset_setting('pipeline', 'pdesc.about_prefixes')) t where t <> '') prefixes) w
     where s.id = a.source_id and a.source_url is not null and (security.provider_description_page_v1(s.provider_id, a.source_url)->>'ok')::boolean
       and not coalesce(regexp_count(lower(coalesce(substring(a.source_url from '^https?://[^/?#]+(/[^?#]*)'), '')), '[^/]+') <= security.pipeline_num_v1('pdesc.about_max_segments', 2) + 1
                and (g.m[1] = any (w.names) or g.m[2] = any (w.names)
                or exists (select 1 from unnest(w.prefixes) px where (left(g.m[1], length(px)) = px and length(g.m[1]) > length(px))
                                                                  or (left(g.m[2], length(px)) = px and length(g.m[2]) > length(px)))), false);
    if m <> 0 then raise exception 'variant %: the first-two-parts and length check refused % copies the page rule passes', x.v, m; end if;
    select count(*) into c from pipeline.evidence_artifacts a, pipeline.sources s where s.id = a.source_id and (security.provider_description_page_v1(s.provider_id, a.source_url)->>'ok')::boolean;
    raise notice 'variant %: % copies pass the page rule, every one kept by both prefilters', x.v, c;
    if m <> 0 then raise exception 'variant %: the prefilter skipped % copies the page rule passes', x.v, m; end if;
  end loop;
  perform fx_variant(1);
  select count(*) into n from fx_old_stored where v = 1 and stored is not null;
  if n < 20 then raise exception 'too few providers with a stored copy to prove anything (%)', n; end if;
  -- the hand-made cases
  if security.provider_description_stored_v1('10000000-0000-0000-0000-000000000001') <> '30000000-0000-0000-0000-000000000001' then raise exception 'Alpha: the main-site About copy'; end if;
  if security.provider_description_stored_v1('10000000-0000-0000-0000-000000000002') <> '30000000-0000-0000-0000-000000000011' then raise exception 'Beta: the tie goes to the lower id'; end if;
  if security.provider_description_stored_v1('10000000-0000-0000-0000-000000000003') is not null then raise exception 'Gamma: no copy passes'; end if;
  raise notice 'hand-made cases: Alpha main-site About copy, Beta tie by id, Gamma none';
end $$;

-- the picker: the same items (stored copy and candidates in the same order) and the same lease answer, direct acquisition on and off
do $$ declare a int; v jsonb; o record; begin
  foreach a in array array[1, 0] loop
    perform fx_requeue();
    update pipeline.platform_toolset_settings set value = to_jsonb(a) where key = 'pdesc.acquire_direct';
    v := public.svc_provider_description_next(50);
    select * into o from fx_old_next where acquire = a;
    if fx_items(v) <> o.items then raise exception 'acquire_direct %: the picker items differ: % vs %', a, fx_items(v), o.items; end if;
    if (v - 'items') <> o.rest then raise exception 'acquire_direct %: the lease answer differs', a; end if;
    raise notice 'acquire_direct %: same % items (% with a stored copy, % candidates in all)', a, jsonb_array_length(o.items),
      (select count(*) from jsonb_array_elements(o.items) i where i->'stored' <> 'null'),
      (select coalesce(sum(jsonb_array_length(i->'candidates')), 0) from jsonb_array_elements(o.items) i);
  end loop;
  update pipeline.platform_toolset_settings set value = '1' where key = 'pdesc.acquire_direct';
  perform fx_requeue();
  v := public.svc_provider_description_next(1);
  if jsonb_array_length(v->'items') <> 1 then raise exception 'one row asked, % leased', jsonb_array_length(v->'items'); end if;
end $$;

-- the stored copy is looked up once per claimed row and never per queued row while direct acquisition is on; the page rule once per suggestion
do $$ declare d text := pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure); s text := pg_get_functiondef('security.provider_description_stored_v1(uuid)'::regprocedure); begin
  if (length(d) - length(replace(d, 'security.provider_description_stored_v1(', ''))) / length('security.provider_description_stored_v1(') <> 2 then raise exception 'stored_v1 calls in the picker'; end if;
  if (length(d) - length(replace(d, 'security.provider_description_page_v1(', ''))) / length('security.provider_description_page_v1(') <> 1 then raise exception 'page_v1 calls in the picker'; end if;
  if (length(s) - length(replace(s, 'security.provider_description_page_v1(', ''))) / length('security.provider_description_page_v1(') <> 1 then raise exception 'page_v1 calls in stored_v1'; end if;
  raise notice 'calls: stored_v1 twice in the picker text (CASE filter, one lateral per claimed row), page_v1 once in stored_v1 and once in the picker (one lateral each)';
end $$;
