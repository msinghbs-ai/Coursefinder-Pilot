CREATE OR REPLACE FUNCTION security.provider_description_stored_v1(p_provider uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- IQ-00055 (v2.15.410 regression): the page rule passes only an address whose first path part is an About page name or starts with an
  -- About prefix, so an address without "/<name>" or "/<prefix>" anywhere cannot pass; those copies are skipped first (a LIKE with the
  -- list's own words, escaped), then the other checks run on what is left, then the page rule once per copy
  with w as (select array(select '%/' || replace(replace(replace(lower(t), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                            from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) t
                          union all
                          select '%/' || replace(replace(replace(lower(t), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                            from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb)) t where t <> '') ws,
                    array(select lower(t) from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) t) names,
                    array(select lower(t) from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb)) t where t <> '') prefixes,
                    -- the oldest capture kept, read once (it was read once per copy)
                    security.pipeline_num_v1('pdesc.about_max_segments', 2) + 1 max_parts,
                    now() - make_interval(days => security.pipeline_num_v1('pdesc.source_max_age_days', 365)::int) since),
  f as (select a.id, a.source_url, a.storage_path, a.mime_type, coalesce(a.captured_at, a.created_at) at
          from w, pipeline.sources s join pipeline.evidence_artifacts a on a.source_id = s.id
         where s.provider_id = p_provider and lower(a.source_url) like any (w.ws)
        offset 0),
  -- the page rule's About part is the first path part, or the second after a language part: one of the first two parts must be an About
  -- page name or start with an About prefix (the path is read as the page rule reads it)
  c as (select f.id, f.at, f.source_url
          from w, f cross join lateral (select z.p, regexp_match(z.p, '^/*([^/]+)(?:/+([^/]+))?') m
                                          from (select lower(coalesce(substring(f.source_url from '^https?://[^/?#]+(/[^?#]*)'), '')) p) z) g
         where f.storage_path is not null and f.source_url ~* '^https?://'
           and coalesce(f.mime_type, 'text/html') ~* 'html|markdown|text'
           and f.at > w.since
           -- at most pdesc.about_max_segments parts, and one more for a language part
           and regexp_count(g.p, '[^/]+') <= w.max_parts
           and (g.m[1] = any (w.names) or g.m[2] = any (w.names)
                or exists (select 1 from unnest(w.prefixes) x where (left(g.m[1], length(x)) = x and length(g.m[1]) > length(x))
                                                                 or (left(g.m[2], length(x)) = x and length(g.m[2]) > length(x))))
        offset 0)
  -- pilot 2 Nov 2026 16:16: the page rule (a held news article was used because "about" was one of its path parts), once per copy
  select c.id
    from c cross join lateral (select security.provider_description_page_v1(p_provider, c.source_url) pg offset 0) r
   where (r.pg->>'ok')::boolean
   order by (r.pg->>'main_host')::boolean desc, c.at desc, c.id
   limit 1
$function$

