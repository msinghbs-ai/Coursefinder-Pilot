-- CF-247 Decision 162 step 4 (Platform Admin approval 29 Sep 2026): switch on higher_component_v1 for UQ double
-- degrees after the trial on 29 Sep 2026: 84 of 94 double degrees resolved (68 minimum, 10 Laws (Honours) Table 1,
-- 6 Education (Secondary) Table 1); 10 held with an unrecognised component; against existing course-page values
-- 51 of 52 agree and the one difference is a course-page PTE of 30 (IELTS agrees), left unchanged for Layer 4.
update pipeline.sources s
   set metadata=s.metadata||jsonb_build_object('double_degree_rule','higher_component_v1',
         'double_degree_rule_approval','Platform Admin approval 29 Sep 2026 after trial (51/52 agree with course pages)')
 where s.source_type='provider_english_requirements' and s.metadata->>'provider_cricos'='00025B';
