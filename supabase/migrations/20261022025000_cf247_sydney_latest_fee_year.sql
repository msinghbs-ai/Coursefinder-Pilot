-- CF-247 (22 Oct 2026). First trial of the Sydney course data file (20 courses): 12 read with fee, year, IELTS, TOEFL and PTE; most files
-- list two years (2026 and 2027) and the pattern took the first. The fee and its year now come from the last year in the file that has an
-- international fee (the newest), and the 12 read are read again. 8 files answered with something other than a data file (recorded as
-- not read; they are tried again by the job's retry rule).
-- Replaces: the Sydney companion patterns (pipeline.uni_adapter_companions, configuration row)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

update pipeline.uni_adapter_companions c
   set patterns = c.patterns
         || jsonb_build_object(
              'fee_international', '"year":\d{4},"fees":\[[^\]]*?"type":"INTFEE","title":"[^"]*","amount":"\$([\d,]+)"(?![\s\S]*"type":"INTFEE","title":"[^"]*","amount":"\$)',
              'fee_year', '"year":(\d{4}),"fees":\[[^\]]*?"type":"INTFEE","title":"[^"]*","amount":"\$[\d,]+"(?![\s\S]*"type":"INTFEE","title":"[^"]*","amount":"\$)'),
       reason = c.reason || '; 22 Oct 2026: newest year with an international fee', updated_at = now()
  from catalogue.providers p
 where p.id = c.provider_id and p.canonical_name = 'The University of Sydney';

update pipeline.course_companion_pages cp set status = 'due', read_attempts = 0, next_read_at = now(), updated_at = now()
  from catalogue.providers p
 where p.id = cp.provider_id and p.canonical_name = 'The University of Sydney' and cp.status = 'read';
