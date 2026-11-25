/// <reference types="vitest/config" />
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// Same file:// compatibility as DeviceWeb/device_page: IIFE bundle, scripts at end of body.
function fileProtocolCompat() {
  return {
    name: 'file-protocol-compat',
    enforce: 'post' as const,
    transformIndexHtml(html: string) {
      let r = html.replace(/ crossorigin/g, '')
      const scripts: string[] = []
      r = r.replace(/<script\b[^>]*src="[^"]*"[^>]*><\/script>/g, (m) => { scripts.push(m.replace(' type="module"', '')); return '' })
      return r.replace('</body>', scripts.join('\n') + '\n</body>')
    },
  }
}

export default defineConfig({
  base: './',
  plugins: [react(), tailwindcss(), fileProtocolCompat()],
  build: {
    target: ['chrome109', 'edge109'],
    rollupOptions: { output: { format: 'iife', name: 'TouchSidebarApp', inlineDynamicImports: true,
      entryFileNames: 'assets/[name].js', assetFileNames: 'assets/[name].[ext]' } },
  },
  test: { environment: 'node', include: ['tests/**/*.test.ts'] },
})
