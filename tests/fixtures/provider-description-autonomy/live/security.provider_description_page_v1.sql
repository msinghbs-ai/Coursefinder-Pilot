CREATE OR REPLACE FUNCTION security.provider_description_page_v1(p_provider uuid, p_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_host text := regexp_replace(lower(coalesce(substring(p_url from '^https?://([^/?#:]+)'), '')), '^www\.', '');
        v_path text := lower(coalesce(substring(p_url from '^https?://[^/?#]+(/[^?#]*)'), ''));
        v_hosts text[] := security.provider_hosts_v1(p_provider); v_main boolean; v_segs text[]; v_first text; v_n int;
begin
  if v_host = '' or security.provider_page_host_v1(p_provider, p_url) <> 'own' then
    return jsonb_build_object('ok', false, 'rule', 'wrong_host', 'main_host', false);
  end if;
  v_main := v_host = any (v_hosts);
  if not v_main and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.refused_host_labels'), '[]'::jsonb)) l
                             where split_part(v_host, '.', 1) = lower(l)) then
    return jsonb_build_object('ok', false, 'rule', 'refused_host', 'main_host', false);
  end if;
  v_segs := array(select s from unnest(string_to_array(regexp_replace(v_path, '/+$', ''), '/')) s where s <> '');
  if cardinality(v_segs) > 0 and v_segs[1] ~ '^[a-z]{2}(-[a-z]{2})?$' then v_segs := v_segs[2:]; end if;  -- fixed: a language part (/en/, /en-au/) is not a path part
  if exists (select 1 from unnest(v_segs) s, regexp_split_to_table(s, '[-_.]+') t,
                  jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.refused_path_words'), '[]'::jsonb)) w
              where t = lower(w) or s = lower(w)) then
    return jsonb_build_object('ok', false, 'rule', 'refused_word', 'main_host', v_main);
  end if;
  v_n := coalesce(cardinality(v_segs), 0); v_first := coalesce(v_segs[1], '');
  if v_n = 0 or v_n > security.pipeline_num_v1('pdesc.about_max_segments', 2)
     or not (exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_patterns'), '[]'::jsonb)) a where v_first = lower(a))
             or exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.about_prefixes'), '[]'::jsonb)) x
                         where x <> '' and left(v_first, length(x)) = lower(x) and length(v_first) > length(x))) then
    return jsonb_build_object('ok', false, 'rule', 'not_about_page', 'main_host', v_main);
  end if;
  return jsonb_build_object('ok', true, 'rule', 'about_page', 'main_host', v_main);
end $function$

