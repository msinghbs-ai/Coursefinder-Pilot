// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.25'
export const PACKAGE_VERSION='0.1.447'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'17 Nov 2026',
  title:'Layer 1 sources show their parser; the wizard takes a target record type',
  changes:[
    'Layer 1 › Sources: each source line has a Parser badge: Hardcoded parser (read by code), AI-built parser (read from a reviewed parser spec) or No parser yet. Filter by Country as before; schedule, warn and stop %, record bounds, Run now, Check source and Pause are on each line.',
    'When a reader flags that a source\'s layout has changed, the line says so and offers Re-infer Parser Spec (Pipeline Operator and above, with a reason). The request is recorded and logged; the source keeps its current parser until a new spec is accepted.',
    'Add source wizard, step 1: choose the Target record type (Course register, Provider register, Tuition fees, Study rules, Destination metrics, Career outcomes, Scholarships).',
    'Add source wizard, step 3: when the AI mapper is deployed, AI Auto-Map also proposes the parser spec, its target table and the category routing, shown for review before saving. On activation the spec becomes the source\'s AI-built parser.'
  ],
  bugFixes:[
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
