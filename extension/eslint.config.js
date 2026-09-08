import js from "@eslint/js";
import tseslint from "typescript-eslint";
import svelte from "eslint-plugin-svelte";

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...svelte.configs["flat/recommended"],
  {
    languageOptions: {
      globals: {
        browser: "readonly",
        console: "readonly",
        CustomEvent: "readonly",
        HTMLElement: "readonly",
        KeyboardEvent: "readonly",
        HTMLTextAreaElement: "readonly",
        window: "readonly",
        document: "readonly",
        fetch: "readonly",
        Response: "readonly",
        TextDecoder: "readonly",
        ReadableStreamDefaultReader: "readonly",
      },
    },
  },
  {
    files: ["**/*.svelte", "**/*.svelte.ts"],
    languageOptions: {
      parserOptions: {
        parser: tseslint.parser,
      },
    },
    rules: {
      "svelte/require-each-key": "off",
    },
  },
  {
    rules: {
      "@typescript-eslint/no-unused-vars": ["warn", { argsIgnorePattern: "^_" }],
      "@typescript-eslint/no-explicit-any": "warn",
      "no-empty": ["error", { allowEmptyCatch: true }],
    },
  },
  {
    ignores: ["node_modules/", "output/", ".wxt/", "dist/"],
  },
);
