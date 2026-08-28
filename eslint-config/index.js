// Shared ESLint config for all __ORG__ repos.
// Consume in a repo:  extends: ['@__ORG__/eslint-config']
module.exports = {
  env: { node: true, es2022: true, jest: true },
  parserOptions: { ecmaVersion: 2022, sourceType: 'module' },
  extends: ['eslint:recommended', 'prettier'],
  rules: {
    'no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
    'no-console': ['warn', { allow: ['warn', 'error'] }],
    eqeqeq: ['error', 'always'],
    'no-throw-literal': 'error'
  }
};
