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
          importNames: ['createClient'],
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
          selector: "NewExpression[callee.name='Client']",
          message: 'Do not instantiate database clients in frontend source. Use the governed data-access boundary.',
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
