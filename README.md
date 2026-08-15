# 🏰 部落冲突 · 卡牌冲突换卡助手

辅助《部落冲突》部落成员记录「卡牌冲突」活动的卡牌库存，自动分析**谁缺什么、谁多什么**，生成换卡推荐；游戏内交换完成后，任一方点一下即可一键同步双方数据。

🔗 **线上地址**：https://chen-chen-99.github.io/coc-change-card/

> 活动卡牌共 **60 张、4 种类**：圣水（19）/ 暗黑重油（13）/ 建筑大师基地（11）/ 超级兵种（17）。
> **只有同种类的卡牌才能互相交换**，匹配算法已内置该约束。

---

## ✨ 功能

- **登录进入**：输入部落名称 + 游戏名称（可选玩家标签、访问码），自动建档并初始化卡牌库存；默认部落名「城紫金」，并记住上次输入；新增**登录渠道（区服）选择器**（微信区 / QQ区，默认微信区，老用户默认微信区，可在登录页修改，仅影响匹配不影响账号识别）。
- **我的卡牌**：展示活动全部卡牌，`+` / `-` 直接修改数量，按种类筛选，实时保存到 Supabase。
- **换卡推荐**：自动计算「我缺什么 → 谁有我缺的 → 谁又需要我多余的」，展示**可交换**推荐：**双向互补**（你给 X、对方给你 Y）或**单方交换**（对方有你缺的卡，你任选一张同种类多余卡交换）；只推荐同种类交换；规则为**同部落 或 同渠道（区服）**可换卡，支持在**仅同部落 / 同渠道**之间切换（同渠道模式显示对方部落名）。
- **一键交换**：双方在游戏中完成交换后，**任一方**点击「交换完成，同步数据」即可原子更新双方库存（服务端校验余量 / 同种类 / 防重复）。
- **访问码**：未设置 → 任何设备可登录修改；已设置 → 仅主人可改，其他设备输入正确访问码可接管。
- **页脚免责声明**：已展示 Supercell 玩家内容条款声明（使用官方素材合规）。

## 🧱 技术栈

- 前端：Vue 3 + Vite（纯静态单页应用）
- 托管：GitHub Pages（GitHub Actions 自动构建部署）
- 数据库 / 认证：Supabase（PostgreSQL + RLS + 匿名登录）
- 匹配算法：前端 JavaScript（`src/lib/matching.js`），无需后端
- 包管理：pnpm（Node ≥ 22.13）
- 设计文档：[DESIGN.md](./DESIGN.md)

## 📁 目录结构

```
├── .github/workflows/deploy-gh-pages.yml  # GitHub Pages 自动部署
├── supabase/
│   ├── schema.sql                  # 全新安装：建表 + RLS + RPC + 60 张卡 + 一键交换
│   └── migration_v{2,3,4,5,6}_*.sql  # 已上线数据库的增量迁移（按需执行）
├── public/images/cards/            # 60 张官方兵种立绘（命名规则见其中 README.md）
├── docs/card-image-prompt.md       # 卡牌图片获取提示词（Wiki 页面对照）
├── src/
│   ├── lib/
│   │   ├── supabase.js             # Supabase 客户端
│   │   ├── api.js                  # 数据读写封装（含演示模式）
│   │   ├── demo.js                 # 演示模式（未配置 Supabase 时自动启用）
│   │   ├── matching.js             # ★ 换卡匹配算法（纯 JS，含同种类约束）
│   │   ├── categories.js           # 卡牌种类定义
│   │   └── store.js                # 会话状态
│   ├── views/                      # 登录 / 我的卡牌 / 换卡推荐
│   └── components/                 # 卡牌卡片组件
└── scripts/
    ├── test-matching.mjs           # 匹配算法测试（pnpm run test:matching）
    └── generate_card_images.py     # 生成示例占位图（可不用）
```

## 🚀 快速开始

### 1. 初始化 Supabase

1. 在 [supabase.com](https://supabase.com) 新建项目。
2. 打开 **SQL Editor**，把 `supabase/schema.sql` 全部内容粘贴执行（建表 + RLS + RPC + 60 张真实卡牌 + 一键交换）。
   > 若数据库已有旧数据，请按顺序执行 `migration_v2_cards.sql` → `migration_v3_access_code.sql` → `migration_v4_login_set_code.sql` → `migration_v5_exchange.sql` → `migration_v6_cross_clan_exchange.sql`（跨部落/跨渠道交换）→ `migration_v7_channel.sql`（登录渠道）→ `migration_v8_undo_exchange.sql`（撤销交换）。
3. 打开 **Authentication → Sign In / Up**，开启 **Allow anonymous sign-ins**（匿名登录是本项目的身份基础）。
4. 打开 **Project Settings → API**，复制 `Project URL` 和 `anon public key`。

### 2. 配置并本地运行

```bash
cp .env.example .env        # Windows: copy .env.example .env
# 编辑 .env，填入 Supabase 的 URL 和 anon key

pnpm install
pnpm dev                    # 本地开发，浏览器打开提示的地址
```

进入页面后输入：部落名称 + 玩家名称（可选玩家标签），即可开始录入卡牌数量、查看换卡推荐。

> 未配置 Supabase 时自动进入**演示模式**（内存模拟数据，刷新重置），可先预览完整效果。

### 3. 构建

```bash
pnpm build                  # 产物在 dist/
```

## 📤 部署（GitHub Pages + Actions）

1. 推送代码到 GitHub 仓库。
2. 仓库 **Settings → Secrets and variables → Actions**，新增两个 Secret：
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
3. 仓库 **Settings → Pages**，Source 选择 **GitHub Actions**。
4. 之后每次 `push` 到 `main`，[deploy-gh-pages.yml](./.github/workflows/deploy-gh-pages.yml) 会自动构建并部署到 GitHub Pages。

> ⚠️ 环境变量是构建期注入的（`VITE_` 前缀），改配置后重新 push 即可。

## 🖼️ 卡牌图片

- 图片存放在 `public/images/cards/`，文件名 = 数据库 `card_id` + `.png`（`e01`~`e19`、`d01`~`d13`、`b01`~`b11`、`s01`~`s17`，共 60 张）。
- 当前为**官方兵种立绘**（来源：Clash of Clans Fandom Wiki，透明背景 PNG，512×512）。
- 获取 / 处理步骤与 60 张卡的 Wiki 页面对照见 [docs/card-image-prompt.md](./docs/card-image-prompt.md)。
- 想换图：按命名规则同名覆盖即可，无需改任何代码或数据库。

## ✅ 测试

```bash
pnpm run test:matching       # 运行换卡匹配算法单元测试（23 项）
```

## 📊 数据管理

- 活动 / 卡牌 / 部落 / 玩家数据可直接在 Supabase Dashboard 维护（前端只有读取权限 + 修改自己库存的权限）。
- 新活动：在 `activities` 插入新活动，在 `cards` 为新活动插入卡牌；玩家进入时会自动为当前活动初始化库存（优先进行中的活动，否则取最近开始的活动）。
- 一键交换记录保存在 `exchanges` 表，可用于统计部落换卡情况。

## ©️ 版权说明

本项目为非官方玩家内容，未获得 Supercell 认可。更多信息请参阅 [Supercell 玩家内容条款](https://supercell.com/en/fan-content-policy/cn/)。

- 卡牌图片版权归 Supercell / 相应来源所有，仅用于非商业性部落内部使用。
