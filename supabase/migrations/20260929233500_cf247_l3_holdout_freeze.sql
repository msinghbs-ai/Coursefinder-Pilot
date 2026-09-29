-- CF-CHG-20260915-247 Layer 3 model routing: FREEZE the three fresh holdout sets before any model runs on them.
-- The digest (pipeline.layer3_holdout_digest: case identity, pinned text hash, gold answer, excerpt, candidate context)
-- is recorded with the sampling seed and query and the fingerprint of the task contract frozen at 13:31 UTC. A
-- qualification run is refused if a set's current digest differs from this one.
insert into pipeline.layer3_holdout_sets(gold_set,task_class,case_count,digest,contract_fingerprint,sample_seed,sample_query,provider_count,note)
select s.gold_set, s.task_class, (select count(*) from pipeline.layer3_holdout_cases c where c.gold_set=s.gold_set),
       pipeline.layer3_holdout_digest(s.gold_set),
       (select f.fingerprint from pipeline.layer3_task_contract_freezes f where f.task_class=s.task_class and f.contract_version=s.contract_version),
       0, s.sample_query,
       (select count(distinct c.provider_id) from pipeline.layer3_holdout_cases c where c.gold_set=s.gold_set), s.note
  from (values
   ('l3r-intake-h1','provider_intake_validation','cf247-intake-validation-v1.2.0',
    $q$seed 'l3r-intake-h1': pages p (read, identity_basis='cricos_code', active course, not Layer 4-blocked, course not in pipeline.layer3_intake_benchmark_cases, course has no active catalogue.course_intakes); order by md5('l3r-intake-h1:'||course_id); first course per provider; first 48$q$,
    '48 sampled, 1 left out as unclear (Gordon TAFE); 13 with months, 34 not stated'),
   ('l3r-english-h1','provider_english_validation','cf247-english-validation-v1.0.0',
    $q$seed 'l3r-english-h1': pages p (read, identity_basis='cricos_code', active course, not Layer 4-blocked, Layer 2 found no IELTS/PTE/TOEFL overall, course has no active catalogue.course_english_requirements); order by md5('l3r-english-h1:'||course_id); first course per provider; first 38$q$,
    '38 sampled, 1 left out as unclear (Austra College band table); 19 stated, 18 not stated'),
   ('l3r-tuition-h1','provider_current_tuition_validation','cf247-provider-current-tuition-validation-v2',
    $q$seed 'l3r-tuition-h1': pages p with a tuition hand-off work item (status admitted or layer4_required) and its plain-text evidence; order by md5('l3r-tuition-h1:'||course_id); first course per provider; first 36$q$,
    '36 sampled (6 admitted, 30 Layer 4-held by the live route); 8 admissible annual fees, 28 not admissible')
  ) s(gold_set, task_class, contract_version, sample_query, note)
on conflict (gold_set) do nothing;

do $v$
begin
  if (select count(*) from pipeline.layer3_holdout_sets where gold_set in ('l3r-intake-h1','l3r-english-h1','l3r-tuition-h1') and contract_fingerprint is not null
        and digest=pipeline.layer3_holdout_digest(gold_set))<>3 then
    raise exception 'holdout sets not frozen as expected';
  end if;
  if exists (select 1 from pipeline.layer3_holdout_results r join pipeline.layer3_holdout_cases c on c.id=r.case_id where c.gold_set like 'l3r-%') then
    raise exception 'a model has already run on a holdout set; freezing now would not be before any model run';
  end if;
end $v$;
