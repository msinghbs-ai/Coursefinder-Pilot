insert into ref.study_levels(code,name,parent_id,sort_order,status)
select 'professional_degree','First Professional Degree',null,75,'active'
where not exists (select 1 from ref.study_levels where code='professional_degree');
