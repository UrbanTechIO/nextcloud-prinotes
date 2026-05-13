// @nextcloud/vue pre-built chunks do: import Vue, { useCssVars } from 'vue'
// Vue 3 has no default export from its ESM bundler build, causing Rollup to fail.
// This shim re-exports everything from Vue 3 and adds a default export so the
// pre-built @nextcloud/vue chunks can resolve it correctly.
export * from 'vue/dist/vue.runtime.esm-bundler.js'
import * as _vue from 'vue/dist/vue.runtime.esm-bundler.js'
export default _vue
