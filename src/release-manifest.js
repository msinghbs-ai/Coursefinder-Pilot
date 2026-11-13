// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.0'
export const PACKAGE_VERSION='0.1.422'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'13 Nov 2026',
  title:'Models & services redesigned: one model list, a model cascade and cap for each service, prompts and usage',
  changes:[
    'Models & services > AI is one page with four panes: OpenRouter key and usage, Models, Services and Recent usage. It replaces the AI & OpenRouter screens, which had grown card by card.',
    'OpenRouter key and usage: whether the key is there (it is never shown), the credit and when it was read, the low-balance warning and floor, and one daily spend ceiling for all AI with today\'s spend against it.',
    'Models: one list by family (Qwen3, MiMo, Mistral Small, Kimi K2, Gemini, Llama, DeepSeek) with price, context and the services using each. GPT and Claude models are listed as not allowed. GPT-4.1 mini is no longer used: it exhausted the AI credit.',
    'Services: one row for each AI use, by area, with its model cascade in order, on/off switch, daily cap in US$ and calls, today\'s spend and a state. Open a row for its prompt and its other AI settings. A service with no model shows a red "No model", never a blank.',
    'Recent usage: spend and calls by service and by model, for the last 24 hours by hour and the last 14 days by day. A figure that was not recorded says "Not measured", not 0.',
    'Every change on the page asks for a reason and shows what will change before it is saved.',
    'The four panes are open on a desktop and can be collapsed; a collapsed pane still shows its warnings. Curator and above read the page; a control you cannot use says which role it needs.',
    'A cascade is shown as the worker runs it: one model where there is no fallback yet, read only where a service is not migrated, and only models qualified for a service can be added to it.',
    'A service\'s model is chosen in one place only: its row on Models & services > AI. Every AI reader asks that row before it hands out work.',
    'A cascade moves to the next model only when a call fails technically (an error, a time-out, an unreadable answer), never because of what a model answered.',
    'The daily spend ceiling for all AI and each service\'s daily cap are enforced. Work held by a cap or the ceiling carries on when the UTC day changes; work an operator asked for under an open request is still let through.',
    'The credit floor stops all AI work when the OpenRouter balance is at or below it, including Run now.',
    'GPT and Claude models are not allowed, and cannot be allowed from the screen: adding a family is a release.',
    'A guard reports any place outside the services that still names a model that is not allowed; a build check does the same for the code.',
    'Settings: the AI settings moved to Models & services, with one line pointing there. Scholarship extraction is configured under the Scholarship pages service on Models & services; its results stay on Scholarships › Coverage.',
    'Since v2.15.494: scholarships show delivery state, more detail columns and filters, provider coverage for all providers and a nationality filter; entry requirements have Read / refresh now, machine approval and a v2 trial reader; providers have Fill description with a prompt the Platform Admin maintains; the Provider and Course catalogues have chosen columns and a description filter; and the screens operated from a phone were made usable there.',
    'Since v2.15.494: Website API v3 and Zoho API v3 run beside v2 (v2 is unchanged); work an operator asks for is not held by toolset limits and reports its estimate before and its use after.'
  ],
  bugFixes:[
    'GPT-4.1 mini was pinned by build sessions on 12 Oct (central pages) and 26 Oct (entry requirements), outside the Platform Admin\'s model cascade; nothing checked a service\'s model against the cascade. From this release a build check and a database guard do.',
    'A text setting (for example a model name) is a text box. It used to be drawn as a number box that said "Between 0 and 0" and could not be changed.',
    'The old table showed a dash in the Model column for four AI uses, which hid the model they ran on. Every service now names its model.',
    'Since v2.15.494: intake dates are read from more calendar layouts and never take a later year\'s start; course and provider descriptions held for size or one weak sentence are recovered; scholarship reading no longer stalls on a long queue; several jobs that ran past their time limit were fixed at the source.'
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
