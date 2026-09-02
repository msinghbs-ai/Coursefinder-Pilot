update pipeline.layer1_source_operations o
set expected_format=case
 when upper(s.metadata->>'source_system')='QS' then 'QS authorised CSV/XLSX; compact multi-year rank columns supported'
 when upper(s.metadata->>'source_system')='THE' then 'THE native JSON/TXT or authorised CSV/XLSX; compact rank/score columns supported'
 else o.expected_format end,
 updated_at=now()
from pipeline.sources s
where s.id=o.source_id and upper(coalesce(s.metadata->>'source_system','')) in ('QS','THE');

update pipeline.sources
set metadata=coalesce(metadata,'{}'::jsonb)||
 case upper(metadata->>'source_system')
  when 'QS' then jsonb_build_object('dataset_family_code','global_qs_wur','dataset_family_label','QS World University Rankings','supported_edition_years',jsonb_build_array(2027,2026),'current_edition_year',2027,'multi_year_family',true)
  when 'THE' then jsonb_build_object('dataset_family_code','global_the_wur','dataset_family_label','Times Higher Education World University Rankings','supported_edition_years',to_jsonb(array[2026,2025,2024,2023,2022,2021,2020,2019,2018,2017,2016,2015]),'current_edition_year',2026,'multi_year_family',true)
  else '{}'::jsonb end,
 updated_at=now()
where upper(coalesce(metadata->>'source_system','')) in ('QS','THE');
