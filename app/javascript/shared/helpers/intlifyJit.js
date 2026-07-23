// vue-i18n compiles message strings to functions at runtime using `new Function()`,
// which a CSP without 'unsafe-eval' blocks. JIT mode builds messages from the parsed
// AST instead, so no eval is needed.
//
// These flags are read by @intlify/core-base via `typeof __INTLIFY_*__ !== 'boolean'`
// guards. Vite's `define` does not substitute identifiers inside `typeof`, so the
// guards would otherwise default them to false. Setting them on globalThis before
// vue-i18n initialises makes the guards see real booleans and keep these values.
/* eslint-disable no-underscore-dangle -- flag names are defined by @intlify/core-base */
globalThis.__INTLIFY_JIT_COMPILATION__ = true;
globalThis.__INTLIFY_DROP_MESSAGE_COMPILER__ = false;
