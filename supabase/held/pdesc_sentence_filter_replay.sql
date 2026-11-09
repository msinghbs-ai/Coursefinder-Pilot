-- HELD (not a migration): offline replay for 20261110120000 (provider-description sentence filter). READ ONLY: one SELECT, no AI call, no write, no fetch. Run it on the live project (or any copy) to see how many of the held provider-description reads
-- would pass the validator if the sentences that fail a sentence rule were left out, which is what the record does for a new read once the migration and worker v0.60.0 are live.
-- It takes the stored proposal of every read held on one of the rules the filter handles and tests each stored sentence ALONE with the live security.provider_description_validate_v1: the sentence is given with a second sentence whose quote is
-- not on the page ("zzqq."), so a sentence that passes every sentence rule (quote on the page, marketing, claim, evidence-claim, complete sentence, numbers, verbatim span, historic context, support) is stopped only at that second sentence, and the
-- count, length, age and duplicate tests are never reached. A read passes when the sentences that pass number at least pdesc.min_sentences and their text is within pdesc.min_chars and pdesc.max_chars (the duplicate and source-age tests are not replayed:
-- they run at the record). The last columns say whether the kept text is also admissible by the machine word policy (security.provider_description_machine_gate_v1, the text and figure rule; the policy is not changed by the filter).
-- Output: one row for each held rule and a total row: the reads held, the reads that would pass the validator, the reads that would also pass the machine gate, and the average sentences given and kept. The sample query at the end shows the text that would be proposed.
with p as (select security.pipeline_num_v1('pdesc.min_sentences', 2) mn, security.pipeline_num_v1('pdesc.min_chars', 150) lo, security.pipeline_num_v1('pdesc.max_chars', 900) hi),
held as (
  select r.id, r.provider_id, r.rule, r.source_url, r.source_captured_at, coalesce(r.read_via, 'stored') via, r.proposal->'sentences' sents
    from pipeline.provider_description_reads r
   where r.state = 'held' and r.rule in ('verbatim_passage', 'quote_not_on_page', 'unsupported_sentence', 'unsupported_claim', 'unsupported_numeric_claim')
     and jsonb_typeof(r.proposal->'sentences') = 'array' and jsonb_array_length(r.proposal->'sentences') > 0),
each as (
  select h.id, h.rule, h.provider_id, h.via, e.o, e.s,
         (security.provider_description_validate_v1(h.provider_id, h.source_url, h.source_captured_at,
            jsonb_build_object('about_page', true, 'sentences', jsonb_build_array(e.s, jsonb_build_object('text', 'zzqq.', 'quote', 'zzqq', 'on_page', false)))) ->> 'reason') like '%: zzqq.' as pass
    from held h, jsonb_array_elements(h.sents) with ordinality e(s, o)),
per_read as (
  select id, rule, provider_id, via, count(*) filter (where pass) kept, count(*) given,
         string_agg(btrim(s->>'text'), ' ' order by o) filter (where pass) kept_text,
         jsonb_agg(s order by o) filter (where pass) kept_sentences
    from each group by id, rule, provider_id, via),
judged as (
  select pr.*, (pr.kept >= p.mn and length(pr.kept_text) between p.lo and p.hi) as validator_pass
    from per_read pr, p),
gated as (
  select j.*, case when j.validator_pass then (security.provider_description_machine_gate_v1(j.provider_id, j.kept_text, jsonb_build_object('tier', j.via, 'sentences', j.kept_sentences)) ->> 'ok')::boolean end as machine_ok
    from judged j)
select rule as held_rule, count(*) as reads_held, count(*) filter (where validator_pass) as would_pass_validator, count(*) filter (where machine_ok) as would_pass_machine_gate,
       round(avg(given), 1) as avg_sentences_given, round(avg(kept), 1) as avg_sentences_kept
  from gated group by rollup (rule) order by rule nulls last;
-- samples (replace the select above by this one): the text that would be proposed
-- select g.id, g.provider_id, g.rule, g.kept || ' of ' || g.given as kept_of_given, g.machine_ok, g.kept_text from gated g where g.validator_pass order by g.machine_ok desc nulls last, g.id limit 10;
