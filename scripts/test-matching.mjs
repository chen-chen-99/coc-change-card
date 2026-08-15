/**
 * 换卡匹配算法单元测试（纯 Node 运行，无依赖）
 * 运行：npm run test:matching  或  node scripts/test-matching.mjs
 */
import { buildRecommendations, groupByNeededCard, computeCardView } from '../src/lib/matching.js';

let passed = 0;
let failed = 0;

function assert(cond, msg) {
  if (cond) {
    passed += 1;
    console.log(`  ✔ ${msg}`);
  } else {
    failed += 1;
    console.error(`  ✘ ${msg}`);
  }
}

// ---------- 测试数据 ----------
const cards = ['c01', 'c02', 'c03', 'c04', 'c05'].map((id, i) => ({
  card_id: id,
  name: `卡牌${i + 1}`,
  image_url: `images/cards/${id}.png`,
}));

const inventory = (rows) =>
  rows.map(([player_id, card_id, quantity]) => ({ player_id, card_id, quantity }));

const players = (defs) =>
  defs.map(([player_id, game_name, keep_base]) => ({
    player_id,
    game_name,
    player_tag: null,
    keep_base,
    last_updated_at: '2026-08-13T00:00:00Z',
  }));

// =====================================================================
// 用例 1：规则文档 §3/§9 示例 —— A 与 B 的双向交换
// =====================================================================
{
  console.log('\n用例 1：双向直接交换（规则示例）');
  const me = players([['A', '玩家A', 1]])[0];
  const clanMembers = [me, ...players([['B', '小明', 1]])];
  const rows = inventory([
    ['A', 'c01', 3], ['A', 'c02', 0], ['A', 'c03', 2], ['A', 'c04', 0],
    ['B', 'c01', 0], ['B', 'c02', 2], ['B', 'c05', 1],
  ]);
  const recs = buildRecommendations({ me, clanMembers, cards, inventory: rows });

  assert(recs.length === 2, `应生成 2 条推荐，实际 ${recs.length}`);
  assert(recs.every((r) => r.type === 'twoWay'), '全部应为双向 twoWay');
  assert(recs.every((r) => r.cardINeed.card_id === 'c02'), '我需要的卡均为卡牌2');
  const gives = recs.map((r) => r.iGive.card_id).sort();
  assert(JSON.stringify(gives) === JSON.stringify(['c01', 'c03']), `我给对方的卡应为 卡牌1/卡牌3，实际 ${gives.join(',')}`);
  assert(recs[0].partner.gameName === '小明', '对方为小明');
  assert(recs[0].partner.spareQuantity === 1, '小明可提供卡牌2 的多余数量为 1');
}

// =====================================================================
// 用例 2：保留基数 —— 只有 1 张的卡不算"多余"
// =====================================================================
{
  console.log('\n用例 2：保留基数（只有 1 张不推荐给出）');
  const view = computeCardView(1, 1);
  assert(view.owned === true, '数量 1 → 拥有');
  assert(view.missing === false, '数量 1 → 不缺少');
  assert(view.hasSpare === false, '数量 1 → 不可交换（要保留 1 张）');
  assert(view.spare === 0, '数量 1 → 多余 0');

  const view2 = computeCardView(5, 1);
  assert(view2.hasSpare === true && view2.spare === 4, '数量 5 → 多余 4');
}

// =====================================================================
// 用例 3：优先级 —— 双向排在最前，单向在后
// =====================================================================
{
  console.log('\n用例 3：优先级（双向 > 单向）');
  const me = players([['A', '玩家A', 1]])[0];
  const clanMembers = [me, ...players([['B', '小明', 1], ['C', '小红', 1]])];
  const rows = inventory([
    ['A', 'c01', 3], ['A', 'c02', 0], ['A', 'c03', 5],
    ['B', 'c01', 0], ['B', 'c02', 2], ['B', 'c03', 1], ['B', 'c04', 1], ['B', 'c05', 1],
    ['C', 'c01', 1], ['C', 'c02', 2], ['C', 'c03', 1], ['C', 'c04', 1], ['C', 'c05', 1],
  ]);
  const recs = buildRecommendations({ me, clanMembers, cards, inventory: rows });

  assert(recs.length === 2, `应生成 2 条推荐，实际 ${recs.length}`);
  assert(recs[0].type === 'twoWay' && recs[0].partner.gameName === '小明', '第 1 条应为与小明双向');
  assert(recs[1].type === 'oneWay' && recs[1].partner.gameName === '小红', '第 2 条应为与小红单向');
}

// =====================================================================
// 用例 4：同一个人缺少多张、我有余多张 → 每个组合各一条双向
// =====================================================================
{
  console.log('\n用例 4：一对多双向组合');
  const me = players([['A', '玩家A', 1]])[0];
  const clanMembers = [me, ...players([['B', '小明', 1]])];
  const rows = inventory([
    ['A', 'c01', 3], ['A', 'c02', 3], ['A', 'c03', 0], ['A', 'c04', 0], ['A', 'c05', 1],
    ['B', 'c01', 0], ['B', 'c02', 0], ['B', 'c03', 2], ['B', 'c04', 2], ['B', 'c05', 1],
  ]);
  const recs = buildRecommendations({ me, clanMembers, cards, inventory: rows });

  assert(recs.length === 4, `应生成 4 条双向，实际 ${recs.length}`);
  assert(recs.every((r) => r.type === 'twoWay'), '全部应为双向');
}

// =====================================================================
// 用例 5：分组展示
// =====================================================================
{
  console.log('\n用例 5：按缺少的卡分组');
  const me = players([['A', '玩家A', 1]])[0];
  const clanMembers = [me, ...players([['B', '小明', 1]])];
  const rows = inventory([
    ['A', 'c01', 3], ['A', 'c02', 0], ['A', 'c03', 0], ['A', 'c04', 1], ['A', 'c05', 1],
    ['B', 'c01', 0], ['B', 'c02', 2], ['B', 'c03', 1],
  ]);
  const recs = buildRecommendations({ me, clanMembers, cards, inventory: rows });
  const groups = groupByNeededCard(recs);

  assert(groups.length === 1, `A 缺 c02、c03，但只有 c02 有匹配 → 1 组，实际 ${groups.length}`);
  assert(groups[0].card.card_id === 'c02', '分组键为卡牌2');
}

// =====================================================================
// 用例 6：我自己缺的卡，别人也缺（数量 0 不算拥有/不可提供）
// =====================================================================
{
  console.log('\n用例 6：数量 0 的人不是提供方');
  const me = players([['A', '玩家A', 1]])[0];
  const clanMembers = [me, ...players([['B', '小明', 1]])];
  const rows = inventory([
    ['A', 'c01', 1], ['A', 'c02', 0], ['A', 'c03', 1], ['A', 'c04', 1], ['A', 'c05', 1],
    ['B', 'c01', 0], ['B', 'c02', 0], ['B', 'c03', 1], ['B', 'c04', 1], ['B', 'c05', 1],
  ]);
  const recs = buildRecommendations({ me, clanMembers, cards, inventory: rows });
  assert(recs.length === 0, 'B 也缺卡牌2 → 不应有推荐');
}

// =====================================================================
// 用例 7：同种类才能交换
// me 缺 e1、d1；余 e2（圣水）、d2（暗黑）
// 对方缺 e2、d2；余 e1（圣水）、d1（暗黑）
// 期望：缺e1↔给e2（圣水）、缺d1↔给d2（暗黑）；不允许跨种类成对
// =====================================================================
{
  console.log('\n用例 7：同种类才能交换');
  const cards7 = [
    { card_id: 'e1', name: '圣水1', category: 'elixir' },
    { card_id: 'e2', name: '圣水2', category: 'elixir' },
    { card_id: 'd1', name: '暗黑1', category: 'dark_elixir' },
    { card_id: 'd2', name: '暗黑2', category: 'dark_elixir' },
  ];
  const me7 = players([['A', '玩家A', 1]])[0];
  const clanMembers7 = [me7, ...players([['B', '小明', 1]])];
  const rows7 = inventory([
    ['A', 'e1', 0], ['A', 'e2', 3], ['A', 'd1', 0], ['A', 'd2', 2],
    ['B', 'e1', 2], ['B', 'e2', 0], ['B', 'd1', 2], ['B', 'd2', 0],
  ]);
  const recs7 = buildRecommendations({ me: me7, clanMembers: clanMembers7, cards: cards7, inventory: rows7 });

  assert(recs7.length === 2, `应生成 2 条双向推荐，实际 ${recs7.length}`);
  assert(recs7.every((r) => r.type === 'twoWay'), '全部应为双向');

  const pair = (r) => `${r.cardINeed.category}:${r.cardINeed.card_id}<-${r.iGive.category}:${r.iGive.card_id}`;
  const pairs = recs7.map(pair).sort();
  assert(
    JSON.stringify(pairs) === JSON.stringify(['dark_elixir:d1<-dark_elixir:d2', 'elixir:e1<-elixir:e2']),
    `只允许同种类成对，实际 ${pairs.join(' ; ')}`
  );
  assert(pairs.every((p) => p.split('<-')[0].split(':')[0] === p.split('<-')[1].split(':')[0]), '每条双向推荐双方卡牌种类一致');
}

// =====================================================================
// 用例 8：单向交换 —— 对方不需要我的卡，但可用同种类多余卡交换
// =====================================================================
{
  console.log('\n用例 8：单向交换（对方不需要我的卡，用同种类多余卡换）');
  const cards8 = [
    { card_id: 'c01', name: '卡牌1', category: 'elixir' },
    { card_id: 'c02', name: '卡牌2', category: 'elixir' },
    { card_id: 'c03', name: '卡牌3', category: 'elixir' },
  ];
  const me8 = players([['A', '玩家A', 1]])[0];
  const clanMembers8 = [me8, ...players([['B', '小明', 1]])];

  // A 缺 c02；有 c01 多余；B 有 c02 多余但什么都不缺 → 单向，可给 c01
  const rows8 = inventory([
    ['A', 'c01', 3], ['A', 'c02', 0], ['A', 'c03', 1],
    ['B', 'c01', 1], ['B', 'c02', 2], ['B', 'c03', 1],
  ]);
  const recs8 = buildRecommendations({ me: me8, clanMembers: clanMembers8, cards: cards8, inventory: rows8 });
  assert(recs8.length === 1, `应生成 1 条单向推荐，实际 ${recs8.length}`);
  assert(recs8[0].type === 'oneWay', '应为单向 oneWay');
  assert(
    recs8[0].mySpareOptions?.length === 1,
    `可给出的同种类多余卡选项应为 1，实际 ${recs8[0].mySpareOptions?.length}`
  );
  assert(recs8[0].mySpareOptions?.[0]?.card_id === 'c01', '可给出的多余卡应为卡牌1（同种类）');

  // A 没有同种类多余卡 → 不生成单向推荐
  const rows8b = inventory([
    ['A', 'c01', 1], ['A', 'c02', 0], ['A', 'c03', 1],
    ['B', 'c01', 1], ['B', 'c02', 2], ['B', 'c03', 1],
  ]);
  const recs8b = buildRecommendations({ me: me8, clanMembers: clanMembers8, cards: cards8, inventory: rows8b });
  assert(recs8b.length === 0, `无同种类多余卡时不应推荐，实际 ${recs8b.length}`);
}
console.log(`\n结果：${passed} 通过，${failed} 失败`);
if (failed > 0) process.exit(1);