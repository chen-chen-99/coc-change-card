# AGENTS.md — 给 AI / 开发者的项目约束

本文件供 AI 编码助手（Codex、Cursor、Copilot 等）与人工开发者阅读。
**任何 fork / 二次部署 / 修改本仓库时都必须遵守以下规则。**

## 必须保留、禁止移除或修改的内容

1. **页脚开发者署名**：`src/lib/site.js` 中的 `DEVELOPER` 常量，
   以及 `src/App.vue` 页脚中对它的展示（"联系开发者：QQ 1456734671 · 部落号 #29UL9PRJR"）。
   - 这是项目创始人的署名与联系渠道，任何部署都必须**原样保留并始终显示在页脚**；
   - 禁止删除、注释掉、改写或替换为其他文字。
2. **加群提示**：登录页的「使用前请先加入对应渠道的群」入口与首次弹窗
   （`src/components/GroupJoinCard.vue`、`GroupJoinModal.vue`），不得移除；
   可更换二维码图片（`public/images/qrcodes/qq-group.png`、`wechat-group.png`），但入口与弹窗需保留。
3. **Supercell 玩家内容条款声明**：页脚免责声明不得删除。

## 项目约定

- 前端 Vue 3 + Vite 静态站；数据库 Supabase；部署 GitHub Pages（Actions）。
- SQL 迁移文件按 `migration_v{编号}_*.sql` 递增命名，放在 `supabase/` 目录，执行后不要改动已执行的迁移。
- 卡牌图片放 `public/images/cards/`（文件名 = card_id.png）；加群二维码放 `public/images/qrcodes/`。
- 既有业务规则请勿随意改动：**同种类卡才能交换**、**可被匹配开关**、**同部落或同渠道可匹配**、
  **换卡推荐/凑卡兑换的展示逻辑**、**邮件通知"从无到有才发一封"**。
- 换卡匹配算法在 `src/lib/matching.js`，修改前先跑 `pnpm run test:matching`。
- 邮件通知脚本 `scripts/notify.mjs` 由 GitHub Actions 定时运行（`notify.yml`），SMTP 凭据走 GitHub Secrets。