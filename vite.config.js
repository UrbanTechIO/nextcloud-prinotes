import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  plugins: [vue()],
  build: {
    outDir: '.',
    emptyOutDir: false,
    // esbuild minifier has a '$' identifier collision bug in large bundles.
    // Terser handles large scopes correctly and avoids this.
    minify: 'terser',
    terserOptions: {
      mangle: {
        // Reserve '$' so terser never picks it as a mangled identifier name.
        // Nextcloud loads jQuery which already uses '$' as a global.
        reserved: ['$', '$$'],
      },
    },
    rollupOptions: {
      input: { 'prinotes-main': path.resolve(__dirname, 'src/main.js') },
      output: {
        entryFileNames: 'js/[name].js',
        chunkFileNames: 'js/chunks/[name]-[hash].js',
        assetFileNames: (assetInfo) => {
          const name = assetInfo.name || ''
          if (name.endsWith('.css')) return 'css/[name][extname]'
          if (/\.(woff2?|ttf|eot|otf|svg)$/.test(name)) return 'css/fonts/[name][extname]'
          return 'js/assets/[name]-[hash][extname]'
        },
      },
    },
  },
  css: {
    preprocessorOptions: {
      scss: { quietDeps: true, silenceDeprecations: ['legacy-js-api', 'import'] },
    },
  },
  optimizeDeps: { include: ['vue', 'pinia', 'vue-router'] },
  resolve: { alias: { '@': path.resolve(__dirname, 'src') }, dedupe: ['vue'] },
})
