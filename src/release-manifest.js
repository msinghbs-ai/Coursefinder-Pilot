// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.395'
export const PACKAGE_VERSION='0.1.322'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'1 Nov 2026',
  title:'Guides state who acts, how alerts arrive and where the specialist tasks are',
  changes:[
    'Platform guide, Alerts: alerts arrive by push and e-mail from the hourly Work queue alerts task (D12), up to about 75 minutes after an issue; the rules (15-minute confirmation, cooldown, reminder, recovery, retries) and their settings are listed, and Delivered means sent, not read (UR-01).',
    'Roles and SOPs: the Pipeline Operator diagnoses, records and escalates; the PIM Admin paces, pauses, resumes and runs again; automations marked Platform Admin need the Platform Admin; entry requirement (AER) items are decided by the Platform Admin only, with the three current choices (UR-02).',
    'SOP documents carry their source commit, reviewed release and a content digest, and the export can check a copy for drift (UR-03).',
    'Platform guide, Specialist tasks: each role\'s top tasks link to the specialist guide section, with the lowest role, the source needed, what is saved and who to escalate to; counsellor wording for estimates, unstated scales and reporting a wrong value (UR-17).'
  ],
  bugFixes:[]
}

// Ordered accepted releases. The first item is the only recovery baseline for a new candidate.
// Historical releases before this central manifest remain retained by the legacy release-history source.
export const ACCEPTED_RELEASES=[
  {
    version:'2.15.79',
    packageVersion:'0.1.6',
    date:'14 Sep 2026',
    pilotMain:'32be4e96a8df342deba3011f9740dc1230a672b2',
    title:'Dispatcher tuning & run metrics',
    changes:[
      'Administration > Scraper Config now separates vendor controls from governed Layer 2 dispatcher tuning.',
      'Admins can compare recent runs using throughput, response/extraction latency, retries, Evidence, field resolution and Layer 2/Layer 3/blocked outcomes.',
      'PIM/Data Admins can tune batch size, run concurrency, stale recovery and paid-attempt limits for subsequent runs with an auditable governance reason.',
      'Running batches retain their immutable policy snapshot; tuning never rewrites work already in flight.',
      'Hourly CourseFinder metrics track dispatcher continuations, provider performance, Evidence and policy snapshots for evidence-based tuning.'
    ],
    bugFixes:[
      'Retains the Layer 2 runner transport safety cap introduced by PR #84: ordinary invocations remain capped at four items and scraper-first invocations at two.',
      'Dispatcher metrics are sanitized and do not expose raw payloads, result/error text, target URLs, Storage paths or provider credentials.',
      'Preserves Layer 1 authority, Layer 3 Evidence/profile/model governance, Layer 4 human authority and separate Search/Publication admission.'
    ]
  }
]

export const RECOVERY_RELEASE=ACCEPTED_RELEASES[0]
