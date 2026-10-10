-- CF-247 Decision 162: the fee-schedule qualifications recorded search_admitted=true, but no Search gate
-- (search.enrichment_source_gates) is approved for these sources, so their fees do not reach Search or the
-- consumer API. The flag now states the real position; opening a Search gate is a separate publication decision.
update pipeline.course_fact_source_qualifications q
   set metadata=q.metadata||jsonb_build_object('search_admitted',false,'search_gate','awaiting publication decision'), updated_at=now()
 where exists (select 1 from pipeline.sources s where s.id=q.source_id and s.source_type='provider_fee_schedule')
   and not exists (select 1 from search.enrichment_source_gates g where g.source_id=q.source_id and g.gate_status='approved');
