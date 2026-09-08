import globals from 'globals'
import tseslint from 'typescript-eslint'

const frontendFiles = ['src/**/*.{js,jsx,ts,tsx}']

export default [
  {
    ignores: [
      'dist/**',
      'node_modules/**',
      'playwright-report/**',
      'test-results/**',
      'uat-artifacts/**',
      'supabase/**',
      'worker/**',
    ],
  },
  {
    files: frontendFiles,
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        ecmaVersion: 'latest',
        sourceType: 'module',
        ecmaFeatures: { jsx: true },
      },
      globals: {
        ...globals.browser,
        ...globals.es2022,
      },
    },
    rules: {
      'no-restricted-imports': ['error', {
        paths: [{
          name: '@supabase/supabase-js',
          message: 'Browser Supabase client creation is restricted to src/lib/supabase.js or src/lib/supabase.ts.',
        }],
      }],
      'no-restricted-syntax': [
        'error',
        {
          selector: "CallExpression[callee.name='createClient']",
          message: 'Do not instantiate Supabase clients outside the governed data-access boundary.',
        },
        {
          selector: "TaggedTemplateExpression[tag.name='sql']",
          message: 'Raw SQL strings are prohibited in frontend source. Use governed admin_read RPC contracts.',
        },
        {
          selector: "CallExpression[callee.property.name='from']",
          message: 'Direct browser table reads/writes are prohibited. Route frontend data access through governed RPC/API methods.',
        },
      ],
    },
  },
  {
    files: ['src/lib/supabase.js', 'src/lib/supabase.ts'],
    rules: {
      'no-restricted-imports': 'off',
      'no-restricted-syntax': 'off',
    },
  },
  {
    files: ['tests/**/*.{js,mjs,ts}', 'vitest.config.js', 'vite.config.js'],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: { ecmaVersion: 'latest', sourceType: 'module' },
      globals: { ...globals.node, ...globals.es2022 },
    },
  },
]
