# 《部落冲突》卡牌冲突活动 — 数据结构与换卡匹配设计

> 本文档基于《部落冲突》"卡牌冲突"活动规则，明确活动机制理解，并给出卡牌数据结构、用户数据结构与换卡匹配逻辑的完整设计。技术方案采用：**Cloudflare Pages / GitHub Pages（静态站点）+ Supabase（数据库/认证）+ 前端 JavaScript 匹配**。

---

## 1. 活动机制理解（摘要）

- **限时活动**：有明确的开始/结束时间；活动结束后，卡牌收集与换卡功能随之结束。
- **卡牌分 4 种类**（交换核心规则）：
  | 种类 | category 编码 | 张数 |
  | --- | --- | --- |
  | 圣水卡牌 | `elixir` | 19 |
  | 暗黑重油卡牌 | `dark_elixir` | 13 |
  | 建筑大师基地卡牌 | `builder_base` | 11 |
  | 超级兵种卡牌 | `super_troop` | 17 |
- **同种类才能交换**：每次交换只能在同一种类内进行，例如圣水卡牌 A 不能与暗黑重油卡牌 B 交换；双向交换中"我给"与"我拿"的两张卡必须同种类。
- **数量精确记录**：不能只记"有/没有"，`quantity ≥ 0` 是核心字段。
- **三个派生概念**（对任意玩家 × 卡牌，实时推导，不落库）：
  - **拥有**：数量 > 0
  - **缺少**：数量 = 0
  - **多余**：数量 > 保留基数（默认保留 1 张）；可交换数量 = 数量 − 保留基数
- **推荐优先级**：
  1. **双向直接交换**（同种类：我给 X、对方给我 Y）——最高优先级
  2. **对方拥有我需要的卡**（单向，供玩家主动联系）
  3. **多人循环交换**（A→B→C→A）——第二版扩展，第一版不实现

---

## 2. 数据模型设计（Supabase / PostgreSQL）

### 2.1 实体关系

```
activities 1 ─── n cards
clans     1 ─── n players
players   1 ─── n player_cards     （库存，核心表）
cards     1 ─── n player_cards
players   1 ─── n trades           （换卡记录，第二版可选）
cards     1 ─── n trades
```

### 2.2 表结构（Supabase SQL，见 `supabase/schema.sql`）

#### activities（活动）
| 字段 | 类型 | 说明 |
| --- | --- | --- |
| activity_id | text PK | 活动ID，如 `card_clash_2026_08` |
| name | text | 活动名称 |
| start_time | timestamptz | 开始时间 |
| end_time | timestamptz | 结束时间 |

#### cards（卡牌）
| 字段 | 类型 | 说明 |
| --- | --- | --- |
| card_id | text PK | 卡牌ID（同时决定图片文件名，见第 7 节） |
| activity_id | text FK → activities | 卡牌所属活动 |
| name | text | 卡牌名称 |
| category | text | 卡牌种类：`elixir` / `dark_elixir` / `builder_base` / `super_troop`（交换匹配的唯一约束维度） |
| image_url | text | 图片路径，如 `images/cards/e01.png`（不带前导 `/`，前端自动拼接部署基路径） |
| sort_order | integer | 展示排序（按种类分组递增） |

> 说明：不再限制"同一活动内卡名唯一"，因为不同种类存在同名兵种（如"飞龙宝宝"同时出现在圣水与建筑大师基地）。

#### clans（部落）
| 字段 | 类型 | 说明 |
| --- | --- | --- |
| clan_id | uuid PK | 部落ID |
| name | text UNIQUE | 部落名称 |

#### players（玩家）
| 字段 | 类型 | 说明 |
| --- | --- | --- |
| player_id | uuid PK | 玩家ID |
| clan_id | uuid FK → clans | 所属部落 |
| player_tag | text 可选 | 部落冲突玩家标签（`#XXXX`），天然唯一，用于识别同一玩家 |
| game_name | text | 部落冲突玩家名称（展示用） |
| access_code | text 可选 | 访问码（用于在其他设备换绑，v1 可选） |
| keep_base | integer 默认 1 | 每种卡牌的保留基数 |
| owner_user_id | uuid 可选 | 绑定的 Supabase 匿名用户 ID，决定谁能编辑该玩家数据 |
| last_updated_at | timestamptz | 该玩家数据最后更新时间 |

约束：同一部落内 `player_tag` 或 `game_name` 唯一。

#### player_cards（玩家卡牌库存 —— 核心表）
| 字段 | 类型 | 说明 |
| --- | --- | --- |
| player_id | uuid FK → players | 玩家 |
| card_id | text FK → cards | 卡牌 |
| quantity | integer ≥ 0 | 拥有数量（CHECK 约束） |
| updated_at | timestamptz | 该行最后更新时间 |

主键：`(player_id, card_id)`。

**关键设计要点**：
- 玩家首次进入时，由 `login_player` RPC 为其**当前活动**的每张卡牌初始化一行 `quantity = 0`。
- 库存行缺失等价于数量 0（前端按 0 处理）。
- 不存储"是否拥有"，一律由 `quantity` 实时推导，避免不一致。
- 活动通过卡牌关联：`player_cards → cards → activities`，支持多活动并存、新活动复用同一套表结构。

### 2.3 安全模型（Row Level Security）

- 所有表启用 RLS。
- **读**：匿名登录用户可读全部（整个部落的数据需要共享，用于换卡匹配）。
- **写**：只能修改 `owner_user_id = auth.uid()`（当前匿名用户）绑定的玩家库存；创建/初始化由 `SECURITY DEFINER` 的 `login_player` RPC 完成。
- 活动/卡牌/部落的增删改仅通过 Supabase 控制台（service role）或 SQL 管理。

### 2.4 登录/进入流程（RPC `login_player`）

前端调用 `supabase.rpc('login_player', {...})`，服务端在**一个事务**内完成：

1. 按部落名称找部落，找不到则创建；
2. 按玩家标签（优先）或玩家名称找玩家：找不到 → 创建并绑定当前匿名用户、初始化库存；未绑定 → 认领；已绑定他人 → 返回 `editable=false`（可输入 `access_code` 换绑）；
3. 返回玩家信息 + `editable` 标记。

---

## 3. 换卡匹配逻辑（前端 JavaScript 实现）

### 3.1 基础判定公式

对玩家 p、卡牌 c、数量 q、保留基数 K：

| 概念 | 判定 | 公式 |
| --- | --- | --- |
| 拥有 owned | `q > 0` | — |
| 缺少 missing | `q === 0` | — |
| 多余数量 spare | `q > K` 时的可交换量 | `max(0, q - K)` |
| 可交换 hasSpare | `q - K > 0` | — |

> K 取各玩家自己的 `keep_base`（默认 1）。

### 3.2 匹配算法（伪代码，实现见 `src/lib/matching.js`）

```
needs  = { c | q(me, c) === 0 }            // 我缺少的卡
spares = { c | q(me, c) > me.keepBase }     // 我多余的卡

result = []

for c in needs:                             // 遍历我缺少的每张卡
    providers = [ m | m ∈ 部落成员, m ≠ me, hasSpare(m, c) ]
    for m in providers:
        // 同种类才能交换：对方缺的 y 必须与 c 同种类，且我有余
        mutual = [ y | y ∈ needs(m), category(y) = category(c), hasSpare(me, y) ]
        if mutual:
            for y in mutual:
                result.push({ type: "twoWay", cardINeed: c, partner: m, iGive: y, iGet: c, resolvedCount: 2 })
        else:
            result.push({ type: "oneWay", cardINeed: c, partner: m, iGive: null, iGet: c, resolvedCount: 1 })

// 排序：twoWay 优先 → resolvedCount 降序 → 对方余量降序 → 对方数据新者优先
```

**复杂度**：O(成员数 × 卡牌数²)，部落规模（≤50 人 × 60 卡）下毫秒级。

**正确性说明**：
- `mutual` 强制 `category(y) === category(c)`，保证双向交换的两张卡同种类。
- `c` 不可能同时出现在 `mutual` 中（`me` 缺 c ⇒ `hasSpare(me, c)` 恒为 false）。
- 单向推荐是"对方拥有我需要的卡"，本身就是单卡，无跨种类问题。

### 3.3 推荐结果结构

```ts
interface TradeRecommendation {
  type: "twoWay" | "oneWay";
  cardINeed: Card;          // 我需要的卡（含 category，展示分组依据）
  iGet: Card;               // 我获得 = cardINeed
  iGive?: Card;             // twoWay 时：我给对方的卡（与 cardINeed 同种类）
  partner: {
    playerId: string;
    gameName: string;
    playerTag?: string;
    spareQuantity: number;
    lastUpdatedAt: string;
  };
  resolvedCount: number;    // 双向=2，单向=1
}
```

### 3.4 边界情况处理

| 场景 | 处理 |
| --- | --- |
| 我无缺少卡牌 | 提示"已集齐，无需换卡" |
| 部落无其他成员数据 | 提示"等待部落成员录入数据" |
| 我无多余卡牌 | 仍展示单向推荐，并标注"你暂无可交换的多余卡牌" |
| 对方数据可能过期 | 展示每个成员的最后更新时间 |
| 活动已结束 | 数量修改置为只读，推荐功能隐藏或只读 |
| 对方某卡余量多 | 每条推荐交换 1 张（目标为每种 ≥1），同时显示"可交换 N 张" |
| **跨种类** | **不产生任何双向推荐；页面提示"只有同种类的卡牌才能互相交换"** |

### 3.5 多人循环交换（第二版扩展）

建模为**有向图**：节点 = 玩家；边 `m → n` 标记卡牌 `c`（n 缺 c 且 m 有余 c）。用 DFS 枚举长度 ≥ 3 的简单环；环内每一步都满足同种类约束。第一版不实现。

---

## 4. 技术架构

```
┌────────────────────────────────────────────────────┐
│  静态站点（Cloudflare Pages / GitHub Pages）        │
│  Vue 3 + Vite                                       │
│  ├─ 页面：玩家进入 / 我的卡牌 / 换卡推荐             │
│  ├─ 匹配算法：src/lib/matching.js（纯前端计算）      │
│  └─ 图片：public/images/cards/*.png（随站点部署）    │
└──────────────┬─────────────────────────────────────┘
               │ HTTPS（Supabase JS 客户端，anon key）
┌──────────────▼─────────────────────────────────────┐
│  Supabase                                          │
│  ├─ PostgreSQL：activities/cards/clans/players/     │
│  │               player_cards（RLS 保护）           │
│  ├─ Auth：匿名登录（signInAnonymously）             │
│  └─ RPC：login_player（找/建部落与玩家、初始化库存） │
└────────────────────────────────────────────────────┘
```

- **无自建后端**：所有读写直接走 Supabase（JS SDK + RLS + RPC）。
- **图片随站点部署**：放入 `public/images/cards/`，构建时原样复制到 `dist`。
- **演示模式**：未配置 Supabase 时自动启用内存模拟数据（60 张真实卡 + 演示成员），便于预览。

---

## 5. 前端页面与数据流

| 页面 | 行为 |
| --- | --- |
| 玩家进入 | 匿名登录 → 输入部落名称/玩家名称（可选玩家标签）→ 调 `login_player` RPC → 拉取当前活动 + 卡牌 + 我的库存 |
| 我的卡牌 | 60 张卡按 4 种类筛选展示：图片、名称、种类标签、当前数量、[-]/[+]；显示"缺少/已收集/多余 N 张" |
| 换卡推荐 | 拉取同部落全部玩家 + 库存 → `buildRecommendations()`（同种类约束）→ 按缺少的卡分组展示，双向优先，标注种类 |

数量修改使用**增量 delta（±1）**语义：前端计算 `next = max(0, current ± 1)` 后 upsert 该行。

---

## 6. 部署步骤（详见根目录 README.md）

1. 创建 Supabase 项目 → SQL Editor 执行 `supabase/schema.sql`（建表 + RLS + RPC + 60 张真实卡种子数据）；若已执行过旧版，先执行 `supabase/migration_v2_cards.sql`。
2. Authentication → 开启 **Allow anonymous sign-ins**。
3. 复制 `Project Settings → API` 中的 URL 与 anon public key 到 `.env`。
4. `npm install && npm run build`，把 `dist` 部署到 Cloudflare Pages 或 GitHub Pages。

---

## 7. 图片资源与命名规则

**目录**：`public/images/cards/`（随网页一起部署）

**命名规则**：`{card_id}.png`，与数据库 `cards.card_id` 一一对应，按种类前缀分组：

| 种类 | card_id 前缀 | 示例 |
| --- | --- | --- |
| 圣水卡牌 | `e` | e01.png ~ e19.png |
| 暗黑重油卡牌 | `d` | d01.png ~ d13.png |
| 建筑大师基地卡牌 | `b` | b01.png ~ b11.png |
| 超级兵种卡牌 | `s` | s01.png ~ s17.png |

- 当前已附带 60 张程序生成的示例占位图（按种类配色 + 图标 + 卡名）。
- 重新生成：`python scripts/generate_card_images.py`；替换为真实图：按上表同名覆盖即可。
- 建议 512 × 512 PNG；文件名全小写、无空格、无中文；缺失时页面显示占位图。

---

## 8. 实施顺序

1. ✅ 设计文档（本文档）
2. ✅ Supabase schema（建表 + RLS + RPC + 60 张真实卡种子）
3. ✅ 前端骨架（登录 / 我的卡牌 / 换卡推荐）
4. ✅ 匹配算法（含"同种类才能交换"约束）+ 单元测试（23 项）
5. ✅ 示例卡牌图片（60 张占位图）
6. ⬜ 接入真实 Supabase 项目（需要你提供 URL + anon key）
7. ⬜ 替换为真实卡图 / 部署到 Cloudflare Pages / GitHub Pages