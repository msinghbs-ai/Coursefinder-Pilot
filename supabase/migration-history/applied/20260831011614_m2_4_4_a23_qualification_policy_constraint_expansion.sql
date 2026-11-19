
alter table pipeline.layer2_scale_qualification_runs
  drop constraint if exists layer2_scale_qualification_runs_wave_size_check;
alter table pipeline.layer2_scale_qualification_runs
  add constraint layer2_scale_qualification_runs_wave_size_check
  check (wave_size between 1 and 500);

alter table pipeline.layer2_scale_qualification_runs
  drop constraint if exists layer2_scale_qualification_runs_sample_size_check;
alter table pipeline.layer2_scale_qualification_runs
  add constraint layer2_scale_qualification_runs_sample_size_check
  check (sample_size between 1 and 50);
