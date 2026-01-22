import js from "@eslint/js";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "module",
      globals: {
        ...globals.browser,
        // Stimulus globals
        Stimulus: "readonly",
        // Rails/Turbo globals
        Turbo: "readonly",
        // ActionCable
        ActionCable: "readonly",
      },
    },
    rules: {
      // Relaxed rules for Stimulus controllers
      "no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
        },
      ],
      // Allow console for development debugging
      "no-console": "warn",
      // Prefer const/let over var
      "no-var": "error",
      "prefer-const": "error",
    },
  },
  {
    // Ignore build outputs and vendor files
    ignores: [
      "app/assets/builds/**",
      "node_modules/**",
      "tmp/**",
      "public/**",
      "vendor/**",
    ],
  },
];
