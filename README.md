# 🏰 部落冲突 · 卡牌冲突换卡助手

辅助《部落冲突》部落成员记录「卡牌冲突」活动的卡牌库存，自动分析**谁缺什么、谁多什么**，生成换卡推荐；游戏内交换完成后，任一方点一下即可一键同步双方数据。

🔗 **线上地址**：https://chen-chen-99.github.io/coc-change-card/

> 活动卡牌共 **60 张、4 种类**：圣水（19）/ 暗黑重油（13）/ 建筑大师基地（11）/ 超级兵种（17）。
> **只有同种类的卡牌才能互相交换**，匹配算法已内置该约束。

---

## ✨ 功能

- **登录进入**：输入部落名称 + 游戏名称（可选玩家标签、访问码），自动建档并初始化卡牌库存；默认部落名「城紫金」，并记住上次输入；新增**服务器选择**（🇨🇳 国服 / 🌍 国际服，默认国服并记住选择）+ **登录渠道选择器**（微信区 / QQ区，默认微信区）；**国服与国际服互不匹配**，国际服不区分微信/QQ（同渠道=全部国际服玩家，同部落=同部落名）。
- **我的卡牌**：展示活动全部卡牌，`+` / `-` 直接修改数量，按种类筛选，实时保存到 Supabase。
- **换卡推荐**：自动计算「我缺什么 → 谁有我缺的 → 谁又需要我多余的」，展示**可交换**推荐：**双向互补**（你给 X、对方给你 Y）或**单方交换**（对方有你缺的卡，你任选一张同种类多余卡交换）；只推荐同种类交换；规则为**同部落 或 同渠道（区服）**可换卡，支持在**仅同部落 / 同渠道**之间切换（同渠道模式显示对方部落名）。
- **一键交换**：双方在游戏中完成交换后，**任一方**点击「交换完成，同步数据」即可原子更新双方库存（服务端校验余量 / 同种类 / 防重复）。
- **换卡记录 / 撤销**：「换卡记录」页展示历史交换，误点可一键撤销恢复双方数据（仅交换双方之一可撤销，需双方库存仍可归还）。
- **凑卡兑换**：想用「两张多余卡」兑换任意卡时，可先凑齐某张卡到目标张数（3/4/5）；选择目标卡后自动匹配有多余该卡的人，**仅展示对方也缺你能给的卡**的双向组合（纯单方无法在游戏内发起换卡），支持一键交换。
- **访问码**：未设置 → 任何设备可登录修改；已设置 → 仅主人可改，其他设备输入正确访问码可接管。
- **邮件通知**：顶部 🔔 按钮可绑定邮箱并开启通知（可选：仅双向 / 双向+单向）；系统每 30 分钟检查一次，当「从没有可交换卡牌 → 出现可交换卡牌」时自动发送**一封**邮件提醒，无需一直盯着系统。
- **加群提示**：首次使用自动弹窗，后续登录页保留「使用前请先加入对应渠道的群」入口可再次查看；二维码放 `public/images/qrcodes/`（`qq-group.png` / `wechat-group.png`，命名规则见其中 README.md）。
- **联系开发者**：页脚展示开发者联系方式（QQ 1456734671 · 部落号 #29UL9PRJR）。
- **后台管理（本地）**：独立的 `/admin.html` 管理页，可查看全站统计与各渠道匹配状态、管理用户（禁用/启用/删除）、删除部落；禁用用户登录时会提示「先加群 / 联系开发者」。所有操作需管理员口令（存于数据库 `app_config.admin_code`）。
- **页脚免责声明**：已展示 Supercell 玩家内容条款声明（使用官方素材合规）。

## 🧱 技术栈

- 前端：Vue 3 + Vite（纯静态单页应用）
- 托管：GitHub Pages（GitHub Actions 自动构建部署）
- 数据库 / 认证：Supabase（PostgreSQL + RLS + 匿名登录）
- 匹配算法：前端 JavaScript（`src/lib/matching.js`），无需后端
- 定时通知：GitHub Actions（每 30 分钟）+ QQ/163 邮箱 SMTP（免费、无需域名）
- 包管理：pnpm（Node ≥ 22.13）
- 设计文档：[DESIGN.md](./DESIGN.md)
- 项目约束（二次部署/修改前必读）：[AGENTS.md](./AGENTS.md)（须保留页脚开发者署名、加群提示等）

## 📁 目录结构

```
├── .github/workflows/deploy-gh-pages.yml  # GitHub Pages 自动部署
├── .github/workflows/notify.yml          # 换卡邮件通知定时任务（每 30 分钟）
├── supabase/
│   ├── schema.sql                  # 全新安装：建表 + RLS + RPC + 60 张卡 + 一键交换
│   └── migration_v{2,3,4,5,6}_*.sql  # 已上线数据库的增量迁移（按需执行）
├── public/images/cards/            # 60 张官方兵种立绘（命名规则见其中 README.md）
├── public/images/qrcodes/          # 加群二维码（qq-group.png / wechat-group.png，命名规则见其中 README.md）
├── docs/card-image-prompt.md       # 卡牌图片获取提示词（Wiki 页面对照）
├── admin.html                      # 后台管理入口（本地使用）
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
    ├── notify.mjs                  # 换卡邮件通知脚本（每 30 分钟，QQ/163 SMTP）
    └── generate_card_images.py     # 生成示例占位图（可不用）
```

## 🚀 快速开始

### 1. 初始化 Supabase

1. 在 [supabase.com](https://supabase.com) 新建项目。
2. 打开 **SQL Editor**，把 `supabase/schema.sql` 全部内容粘贴执行（建表 + RLS + RPC + 60 张真实卡牌 + 一键交换）。
   > 若数据库已有旧数据，请按顺序执行 `migration_v2_cards.sql` → `migration_v3_access_code.sql` → `migration_v4_login_set_code.sql` → `migration_v5_exchange.sql` → `migration_v6_cross_clan_exchange.sql`（跨部落/跨渠道交换）→ `migration_v7_channel.sql`（登录渠道）→ `migration_v8_undo_exchange.sql`（撤销交换）→ `migration_v9_open_account_permission.sql`（开放账号权限修复）→ `migration_v10_notifications.sql` → `migration_v11_notify_gha.sql`（通知改用 GitHub Actions + QQ/163 SMTP，取代 SendGrid；新库可直接只执行 v11）→ `migration_v12_matchable.sql`（可被匹配开关）→ `migration_v13_admin.sql`（后台管理）。
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

## 📧 邮件通知（可选，免费）

不想一直盯着系统？可绑定邮箱开启通知：系统每 30 分钟检查一次换卡匹配，
当从「没有可交换卡牌」变为「出现可交换卡牌」时，自动发送**一封**邮件提醒
（不会每张卡发一封；邮箱变更后重新满足条件会再次通知）。

实现方式（无需服务器 / 无需域名 / 完全免费）：

- 定时任务：GitHub Actions（[notify.yml](./.github/workflows/notify.yml)）每 30 分钟运行
  `scripts/notify.mjs`，读取 Supabase 数据计算匹配并发送邮件；
- 发信邮箱：用你自己的 **QQ 邮箱 / 163 邮箱** 的 SMTP（授权码），无需注册任何第三方邮件服务。

### 配置步骤

1. **准备邮箱授权码**（以 QQ 邮箱为例）：登录 [mail.qq.com](https://mail.qq.com) →
   设置 → 账号 → 开启「POP3/SMTP 服务」→ 按提示获取 **16 位授权码**（不是 QQ 密码）。
   163 邮箱同理（设置 → POP3/SMTP/IMAP → 客户端授权密码）。
2. **执行数据库迁移**：在 Supabase SQL Editor 执行 `supabase/migration_v11_notify_gha.sql`
   （若数据库还没执行过 v10，可直接只执行 v11，它包含建表 + RPC；已执行过 v10 的
   再执行一次 v11 即可停用旧的 SendGrid 定时任务）。
3. **在 GitHub 仓库添加 Secrets**（Settings → Secrets and variables → Actions）：
   - `SUPABASE_SERVICE_ROLE_KEY`：Supabase 项目 Settings → API → service_role key
   - `SMTP_HOST` = `smtp.qq.com`（或 `smtp.163.com`）
   - `SMTP_PORT` = `465`
   - `SMTP_USER` = 你的邮箱地址（如 `xxx@qq.com`）
   - `SMTP_PASS` = 上面的 16 位授权码
   - `SMTP_FROM` = 发件人地址（一般与 `SMTP_USER` 相同，可省略）
   （`VITE_SUPABASE_URL` 已在部署时配置，脚本会自动复用。）
4. 推送代码到 `main`，之后每 30 分钟自动检查一次；也可在 Actions 页面手动运行
   **Card Exchange Notify** 立即测试（日志会显示发送结果）。

> ⚠️ 小提示：GitHub 的定时任务在仓库**连续 60 天没有任何活动**时会自动暂停，
> 项目在持续更新则不受影响；暂停后手动运行一次或推一次代码即可恢复。

## 🔐 后台管理（本地使用）

独立的 `admin.html` 管理页，用于了解系统使用状态与管理用户。

### 功能

- **概览**：玩家数 / 部落数 / 成功换卡 / 已禁用数，以及**各渠道（微信区 / QQ区）当前是否有可匹配数据**（按「可被匹配」用户实时计算，含双向/单向组合数）；
- **用户管理**：搜索玩家，查看已录入卡牌数、数据行数、最后登录时间、最后更新时间；支持**禁用 / 启用**、**删除**用户；
- **部落管理**：查看部落与成员数，支持**删除部落**（连同其全部玩家数据）；
- **禁用提示**：被禁用的用户登录时会看到提示「使用前请先加入对应渠道的群，或联系开发者」，且无法修改库存 / 交换。

### 启用步骤

1. 在 Supabase SQL Editor 执行 `supabase/migration_v13_admin.sql`（新增 `banned` / `last_login_at` 列、登录拦截、后台 RPC，并生成默认管理员口令）。
2. **务必修改管理员口令**：执行
   ```sql
   update public.app_config set value = '你的新口令' where key = 'admin_code';
   ```
3. 本地启动（见下方），打开 **http://localhost:5173/admin.html**，输入口令进入后台。

### 本地启动

```bash
pnpm install
pnpm dev
```

- 前台：http://localhost:5173/
- 后台管理：http://localhost:5173/admin.html

> ⚠️ 安全提示：`admin.html` 也会随 GitHub Pages 一起部署到公网，但所有操作都要求管理员口令（口令存数据库、由服务端 RPC 校验，前端不落盘），请务必把默认口令改成你自己的，且不要泄露口令。
## 🖼️ 卡牌图片

- 图片存放在 `public/images/cards/`，文件名 = 数据库 `card_id` + `.png`（`e01`~`e19`、`d01`~`d13`、`b01`~`b11`、`s01`~`s17`，共 60 张）。
- 当前为**官方兵种立绘**（来源：Clash of Clans Fandom Wiki，透明背景 PNG，512×512）。
- 获取 / 处理步骤与 60 张卡的 Wiki 页面对照见 [docs/card-image-prompt.md](./docs/card-image-prompt.md)。
- 想换图：按命名规则同名覆盖即可，无需改任何代码或数据库。

## ✅ 测试

```bash
pnpm run test:matching       # 运行换卡匹配算法单元测试（36 项）
```

## 📊 数据管理

- 活动 / 卡牌 / 部落 / 玩家数据可直接在 Supabase Dashboard 维护（前端只有读取权限 + 修改自己库存的权限）。
- 新活动：在 `activities` 插入新活动，在 `cards` 为新活动插入卡牌；玩家进入时会自动为当前活动初始化库存（优先进行中的活动，否则取最近开始的活动）。
- 一键交换记录保存在 `exchanges` 表，可用于统计部落换卡情况。

## ©️ 版权说明

本项目为非官方玩家内容，未获得 Supercell 认可。更多信息请参阅 [Supercell 玩家内容条款](https://supercell.com/en/fan-content-policy/cn/)。

- 卡牌图片版权归 Supercell / 相应来源所有，仅用于非商业性部落内部使用。
