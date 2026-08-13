import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';

// base 使用相对路径：Cloudflare Pages（根路径）与 GitHub Pages（子路径）都能正常加载资源与图片
export default defineConfig({
  base: './',
  plugins: [vue()],
});
