CREATE OR REPLACE FUNCTION security.course_description_held_reasons_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with span as (select make_interval(days => security.pipeline_num_v1('enrich.course_description_held_days', 7)::int) s),
  words as (select w from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'enrich.course_description_claim_words'), security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w),
  f as (select x.* from pipeline.field_enrich_items x, span where x.field = 'description' and x.updated_at >= now() - span.s),
  held as (select f.id, f.value, f.value->'check'->>'rule' rule, nullif(f.value->'check'->'checks'->>'chars', '')::int chars, nullif(f.value->'check'->'checks'->>'sentences', '')::int sentences
             from f where f.state = 'skipped' and f.reason like 'held: %'),
  passed as (select f.* from f where f.state in ('review', 'filled') or (f.state = 'skipped' and f.reason like 'held\_first\_admission:%')),
  claim as (
    select words.w word, h.id from held h cross join lateral jsonb_array_elements(coalesce(h.value->'sentences', '[]'::jsonb)) s cross join words
     where h.rule = 'unsupported_claim' and security.pdesc_has_term_v1(s->>'text', words.w) and not security.pdesc_has_term_v1(s->>'quote', words.w)
     group by words.w, h.id)
  select jsonb_build_object(
    'days', (select extract(day from span.s) from span),
    'readings', (select count(*) from passed) + (select count(*) from held),
    'passed_every_check', (select count(*) from passed),
    'held_by_a_check', (select count(*) from held),
    'by_rule', coalesce((select jsonb_object_agg(z.rule, z.n) from (select coalesce(held.rule, 'unknown') rule, count(*) n from held group by 1) z), '{}'::jsonb),
    'too_long_chars', (select jsonb_build_object('held', count(*), 'median', percentile_cont(0.5) within group (order by held.chars), 'p90', percentile_cont(0.9) within group (order by held.chars), 'max', max(held.chars))
                         from held where held.rule = 'length'),
    'too_many_sentences', coalesce((select jsonb_object_agg(z.sentences::text, z.n) from (select held.sentences, count(*) n from held where held.rule = 'sentence_count' group by 1) z), '{}'::jsonb),
    'claim_words', coalesce((select jsonb_object_agg(z.word, z.n) from (select claim.word, count(*) n from claim group by 1) z), '{}'::jsonb),
    'failed', coalesce((select jsonb_object_agg(z.why, z.n) from (select left(coalesce(f.reason, 'no reason recorded'), 80) why, count(*) n from f where f.state = 'failed' group by 1) z), '{}'::jsonb),
    'ai_cost_usd', (select round(coalesce(sum(f.cost_usd), 0)::numeric, 4) from f),
    'ai_cost_per_passing_reading_usd', (select round((coalesce(sum(f.cost_usd), 0) / nullif((select count(*) from passed), 0))::numeric, 5) from f),
    'reask', jsonb_build_object('attempted', (select count(*) from f where f.value ? 'reask'),
                                'now_within_limits', (select count(*) from passed where passed.value ? 'reask'),
                                'still_held', (select count(*) from held h where h.value ? 'reask')),
    'reask_max', security.pipeline_num_v1('enrich.course_description_reask_max', 0))
$function$
