import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Local only: browser calls /api on Vite and Vite forwards requests to Express.
// On EC2, Nginx performs the same reverse-proxy role.
export default defineConfig({
  plugins: [react()],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': 'http://127.0.0.1:5000',
      '/health': 'http://127.0.0.1:5000',
    },
  },
});
