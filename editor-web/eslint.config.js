// ESLint 9 flat config.
//
// CommonJS on purpose: package.json has no `"type": "module"` (scripts/*.js are
// CJS Node scripts), so a `.js` config file is loaded as CJS.
//
// The rule set is deliberately small — `@eslint/js` recommended plus
// typescript-eslint recommended (non type-checked) — so that linting stays fast
// and does not require rewriting the existing sources. Rules that only flag
// deliberate patterns already used across the codebase are relaxed below with a
// short justification each.
const js = require("@eslint/js");
const tseslint = require("typescript-eslint");
const globals = require("globals");
const reactHooks = require("eslint-plugin-react-hooks");

module.exports = tseslint.config(
  {
    // The esbuild output (bundle.js / bundle.css) is written to
    // ../Chirami/Resources/editor. `npm run lint` only walks editor-web so it
    // is already out of reach, but the entry is kept explicit in case ESLint is
    // ever invoked from the repository root.
    ignores: ["node_modules/**", "dist/**", "../Chirami/Resources/editor/**"],
  },

  js.configs.recommended,
  ...tseslint.configs.recommended,

  // ---------------------------------------------------------------- browser
  {
    files: ["src/**/*.ts", "src/**/*.tsx"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: globals.browser,
    },
    rules: {
      // The CodeMirror / Excalidraw / Swift-bridge boundaries are untyped in
      // places; `any` there is a conscious choice, not an oversight.
      "@typescript-eslint/no-explicit-any": "off",
      // Warn, not error: there is one pre-existing dead import
      // (`Range` in extensions/frontmatter.ts) and ESLint was introduced
      // without rewriting sources. Promote to "error" once it is cleaned up.
      // Underscore-prefixed identifiers are the codebase's opt-out marker.
      "@typescript-eslint/no-unused-vars": [
        "warn",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
          caughtErrorsIgnorePattern: "^_",
        },
      ],
    },
  },

  // ------------------------------------------------------------------ React
  {
    files: ["src/**/*.tsx"],
    // Only `configs.flat.*` has the flat-config shape (plugins as an object);
    // the top-level `configs.*` entries are eslintrc-style and ESLint 9
    // rejects them.
    ...reactHooks.configs.flat["recommended-latest"],
  },

  // --------------------------------------------- CommonJS Node files (*.js)
  // scripts/copy-html.js and this config file are plain CJS build tooling.
  {
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: globals.node,
    },
    rules: {
      // These files are CommonJS by design (package.json has no
      // `"type": "module"`), so `require()` is the only option.
      "@typescript-eslint/no-require-imports": "off",
    },
  },
);
