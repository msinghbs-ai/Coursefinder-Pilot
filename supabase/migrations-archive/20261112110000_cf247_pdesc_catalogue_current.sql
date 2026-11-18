-- CF-247 F-PDESC (Platform Admin 11 Nov 2026 21:04: "Add Provider description to the Guide for applicable role ... record schedule, working
-- mechanism, how to control the throughput or stop the associated jobs").
--
-- The automation catalogue (G1) is what Scheduled jobs › Automations shows for each job. The two provider description jobs still described
-- an earlier design: the reader "every ten minutes, at :06 ... :56", "off until the Platform Admin activates it" and "a person approves or
-- rejects it"; the self-heal without its read-again for a new prompt version. Live (11 Nov 2026 21:10 AEDT): provider-description-read runs
-- at 1,6,...,56 (every 5 minutes), provider-description-self-heal at 3,13,...,53, the reader is on, automatic admission is on and the prompt
-- from Settings is in use. This brings both descriptions (and the self-heal label) up to date. Only catalogue text changes.
-- Consumer API (G3): not touched. Nothing is dropped or deleted. No job, schedule or setting changes.
-- Replaces: the two catalogue descriptions and the self-heal label (text only).
-- Retires: nothing.

update pipeline.automation_catalogue set description =
  'Every 5 minutes (at :01, :06 … :56) while Provider descriptions: reader on is 1, and at most once every Provider descriptions: run every. '
  || 'Each run first settles descriptions waiting for automatic admission (waiting items settled a run), then sends the coverage-sweep worker '
  || 'up to Provider descriptions: providers a run: providers asked for with Fill description first, then live providers with no description '
  || '(or only the short register profile). For each, the worker finds the provider''s own About page (the stored copy, or the About link on '
  || 'its home page; read directly with robots.txt respected, through Firecrawl only when the site refuses and within the Firecrawl reads '
  || 'ceiling and daily share), and the pinned model writes the description with the prompt kept on Models & services › AI & OpenRouter. '
  || 'Every sentence must be backed by a passage on the page, every number must be in its passage and the first sentence must name the '
  || 'provider. A description that passes is admitted automatically when it carries no refused topic, marketing wording or word kept for a '
  || 'person; otherwise it waits in Layer 4. A description typed by hand is never replaced. Stops when the AI spend ceiling, the OpenRouter '
  || 'daily guard or the Firecrawl allowance is reached (Fill description is not held by these task limits). Failed reads are tried again '
  || 'up to Provider descriptions: tries a read. Schedule, controls and how to stop it: admin docs/platform/PROVIDER-DESCRIPTIONS-RUNBOOK.md.'
 where jobname = 'provider-description-read';

update pipeline.automation_catalogue set
  label = 'Provider descriptions: recover held answers, Firecrawl-stopped reads and reads for a new prompt',
  description =
  'Every 10 minutes (at :03, :13 … :53), between the reader''s runs, while Provider descriptions: reader on is 1. Three parts, each bounded '
  || 'by a setting: records again, through the normal checks and with no AI or Firecrawl, answers held only because the model said the page '
  || 'does not describe the institution (held answers re-checked a run); puts back in the queue reads stopped only by the Firecrawl '
  || 'allowance once it renews; and puts back once the reads held under an older prompt version when a new prompt is saved (Firecrawl-stopped '
  || 'reads put back a run caps each). It skips providers with a read already open, and a description typed by hand is never replaced. Pause it on this screen '
  || '(PIM Admin) or stop it with Provider descriptions: reader on 0.'
 where jobname = 'provider-description-self-heal';

do $post$
begin
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'provider-description-read' and description like 'Every 5 minutes (at :01, :06%' and description like '%PROVIDER-DESCRIPTIONS-RUNBOOK%') then raise exception 'post-check: reader description'; end if;
  if not exists (select 1 from pipeline.automation_catalogue where jobname = 'provider-description-self-heal' and description like 'Every 10 minutes (at :03, :13%' and description like '%older prompt version%') then raise exception 'post-check: self-heal description'; end if;
end $post$;
