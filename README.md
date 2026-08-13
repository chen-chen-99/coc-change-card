# 部落冲突 · 卡牌冲突换卡助手

辅助部落成员记录《部落冲突》"卡牌冲突"活动卡牌库存，并自动分析"谁缺什么、谁多什么"，生成换卡推荐（双向直接交换优先）。

> 活动卡牌分 4 种类：圣水（19）/ 暗黑重油（13）/ 建筑大师基地（11）/ 超级兵种（17）。**只有同种类的卡牌才能互相交换**，匹配算法已内置该约束。

- 前端：Vue 3 + Vite（纯静态，可部署到 Cloudflare Pages / GitHub Pages）
- 数据库：Supabase（PostgreSQL + RLS + 匿名登录）
- 匹配算法：前端 JavaScript（`src/lib/matching.js`），无需后端
- 设计文档：见 [DESIGN.md](./DESIGN.md)

## 目录结构

```
├── DESIGN.md                  # 数据结构与匹配逻辑设计文档
├── supabase/
│   ├── schema.sql             # 全新安装：建表 + RLS + RPC + 60 张真实卡（SQL Editor 执行）
│   └── migration_v2_cards.sql # 旧版升级：增加卡牌种类 + 60 张真实卡
├── public/images/cards/       # 卡牌图片（命名规则见其中的 README.md）
├── src/
│   ├── lib/
│   │   ├── supabase.js        # Supabase 客户端
│   │   ├── api.js             # 数据读写封装（含演示模式）
│   │   ├── demo.js            # 演示模式（未配置 Supabase 时自动启用）
│   │   ├── matching.js        # ★ 换卡匹配算法（纯 JS，含同种类约束）
│   │   ├── categories.js      # 卡牌种类定义
│   │   └── store.js           # 会话状态
│   ├── views/                 # 登录 / 我的卡牌 / 换卡推荐
│   └── components/            # 卡牌卡片组件
└── scripts/
    ├── test-matching.mjs      # 匹配算法测试（npm run test:matching）
    └── generate_card_images.py# 生成示例卡牌图片
```

## 快速开始

### 1. 创建 Supabase 项目

1. 在 [supabase.com](https://supabase.com) 新建项目。
2. 打开 **SQL Editor**，把 `supabase/schema.sql` 全部内容粘贴执行（建表 + RLS + RPC + 60 张真实卡牌）。
   > 若此前已执行过旧版（12 张 c01~c12），请改执行 `supabase/migration_v2_cards.sql`。
3. 打开 **Authentication → Sign In / Up**，开启 **Allow anonymous sign-ins**（匿名登录是本项目的身份基础）。
4. 打开 **Project Settings → API**，复制 `Project URL` 和 `anon public key`。

### 2. 配置并本地运行

```bash
# 复制环境变量模板
cp .env.example .env        # Windows: copy .env.example .env
# 编辑 .env，填入 Supabase 的 URL 和 anon key

npm install                 # 或 pnpm install
npm run dev                 # 本地开发，浏览器打开提示的地址
```

进入页面后输入：部落名称 + 玩家名称（可选玩家标签），即可开始录入卡牌数量、查看换卡推荐。

> 未配置 Supabase 时自动进入**演示模式**（内存模拟数据，刷新重置），可先预览完整效果。

### 3. 构建

```bash
npm run build               # 产物在 dist/
```

### 4. 部署

**Cloudflare Pages（推荐）**

1. 把代码推送到 GitHub/GitLab 仓库。
2. Cloudflare Pages → Create project → 连接该仓库。
3. 构建设置：Build command = `npm run build`，Build output directory = `dist`。
4. 在项目的 **Environment variables** 里添加 `VITE_SUPABASE_URL` 与 `VITE_SUPABASE_ANON_KEY`。
5. 保存部署。

**GitHub Pages**

1. 在仓库 Settings → Pages，Source 选择 GitHub Actions（或部署 `dist/` 到 Pages 分支）。
2. 构建时注入环境变量 `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`（Vite 构建时必须存在，否则运行时报错）。
3. 项目已配置 `base: './'`，支持仓库子路径访问。

> ⚠️ 环境变量是构建期注入的（`VITE_` 前缀），改配置后需要重新构建部署。

## 示例卡牌图片

项目已附带 60 张程序生成的示例占位卡图（`public/images/cards/`，按种类前缀 `e`/`d`/`b`/`s` 分组），可直接预览。

- 重新生成：`python scripts/generate_card_images.py`（可修改脚本里的主题色与图标）
- 替换为真实卡图：按命名规则覆盖同名文件即可（`e01.png`、`d01.png`、`b01.png`、`s01.png`…）

## 数据管理

- 活动、卡牌、部落、玩家的增删改请直接在 Supabase Dashboard 操作（前端只有读取权限 + 修改自己库存的权限）。
- 新活动：在 `activities` 插入新活动，在 `cards` 为新活动插入卡牌；玩家进入时会自动为当前活动初始化库存（优先进行中的活动，否则取最近开始的活动）。
- 图片：按 [public/images/cards/README.md](./public/images/cards/README.md) 的命名规则放入 `public/images/cards/`。

## 测试

```bash
npm run test:matching        # 运行换卡匹配算法单元测试
```

## 需要你提供的资料

1. **Supabase 项目**：`Project URL` + `anon public key`（填入 `.env`）。
2. **卡牌图片**（可选）：按命名规则放入 `public/images/cards/`（如 `e01.png`）替换示例占位图。
   > 60 张卡牌清单已按你提供的资料录入 `supabase/schema.sql`，如需调整可再告诉我。