CREATE OR REPLACE FUNCTION security.scholarship_tier_text(p_pcts numeric[], p_amts numeric[], p_up_to boolean, p_currency text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select array_to_string(array_remove(array[
    case when cardinality(coalesce(p_pcts, '{}'::numeric[])) = 1 then p_pcts[1]::int || '% of tuition fees'
         when cardinality(coalesce(p_pcts, '{}'::numeric[])) > 1 then case when p_up_to then 'Up to ' || p_pcts[cardinality(p_pcts)]::int || '% of tuition fees (' || (select string_agg(x::int || '%', ', ') from unnest(p_pcts) x) || ' stated)'
                                                                       else p_pcts[1]::int || '% to ' || p_pcts[cardinality(p_pcts)]::int || '% of tuition fees' end end,
    case when cardinality(coalesce(p_amts, '{}'::numeric[])) = 1 then scholarship.money_prefix(p_currency) || to_char(p_amts[1], 'FM999,999,999')
         when cardinality(coalesce(p_amts, '{}'::numeric[])) > 1 then case when p_up_to then 'Up to ' || scholarship.money_prefix(p_currency) || to_char(p_amts[cardinality(p_amts)], 'FM999,999,999') || ' (' || (select string_agg(scholarship.money_prefix(p_currency) || to_char(x, 'FM999,999,999'), ', ') from unnest(p_amts) x) || ' stated)'
                                                                       else scholarship.money_prefix(p_currency) || to_char(p_amts[1], 'FM999,999,999') || ' to ' || scholarship.money_prefix(p_currency) || to_char(p_amts[cardinality(p_amts)], 'FM999,999,999') end end
  ], null), ' or ')
$function$
