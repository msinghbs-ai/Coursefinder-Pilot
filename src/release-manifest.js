// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.9'
export const PACKAGE_VERSION='0.1.431'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'16 Nov 2026',
  title:'A prompt registry, in shadow: today\'s AI prompts recorded exactly, with their variables and answer formats',
  changes:[
    'A prompt registry keeps the prompts of three AI services exactly as they are sent today (course descriptions, provider descriptions and scholarship pages), with the variables each message is built from, the answer format each must return, and the models its route names. It is a record only: no reader uses it yet, and switching a reader to it is a separate step for the Platform Admin.',
    'A parity report shows that each registered prompt still equals the one in use; any difference means the registry must be brought up to date before it could ever be used.',
    'Models & services: the course description service now names the prompt it really sends (cdesc-source-grounded-v2); it still said v1.',
    'Settings Hub (v2.16.8): five groups, Find a setting, and the website and Zoho settings read-only until an approved change is unlocked.'
  ],
  bugFixes:[
    'The website and Zoho APIs are unchanged (checked against their baseline before and after the change).'
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
