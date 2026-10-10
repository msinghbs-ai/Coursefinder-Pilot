// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.238'
export const PACKAGE_VERSION='0.1.165'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'11 Oct 2026',
  title:'Archived status, clean-up workflow and the Archived review screen',
  changes:[
    'Providers \u203a Archived: archived providers and courses that are not active, each with why (left the register, archived by hand, closed or merged, outside the import scope, suspended) and when, with Restore (PIM Operator and above).',
    'Archiving a provider by hand shows a checklist first: courses, campuses and scholarships hidden; adapter and course link search switched off; waiting Layer 4 reviews closed as superseded; background work stopped. A reason is chosen from a short list. Restore switches back on exactly what was switched off.',
    'Layer 1: a provider whose registered courses have all left the register is archived automatically, and restored automatically when one of its courses comes back. The ten providers already waiting at the departure review are archived now (among them UniSA and the University of Adelaide, merged into Adelaide University).',
    'The Providers and Courses lists show active records unless another Status is chosen.'
  ],
  bugFixes:[
    'A course archived or restored by hand now leaves or returns to search straight away (the search rebuild was not asked for).',
    'A course that is not active is never served by Wix, Zoho or the website, even when asked for by its id.',
    'Providers whose courses had all left the register stayed published with no courses until someone reviewed them.'
  ]
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
