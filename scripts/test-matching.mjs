/**
 * 换卡匹配算法单元测试（纯 Node 运行，无依赖）
 * 运行：npm run test:matching  或  node scripts/test-matching.mjs
 */
import { buildRecommendations, groupByNeededCard, computeCardView, buildCollectRecommendations } from '../src/lib/matching.js';

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
// =====================================================================
// 用例 9：凑卡兑换 —— 用户想凑齐某张卡到目标张数
// =====================================================================
{
  console.log('\n用例 9：凑卡兑换（优先双向，其次单方）');
  const cards9 = [
    { card_id: 'c01', name: '卡牌1', category: 'elixir' },
    { card_id: 'c02', name: '卡牌2', category: 'elixir' },
    { card_id: 'c03', name: '卡牌3', category: 'elixir' },
  ];
  const me9 = players([['A', '玩家A', 1]])[0];
  const clanMembers9 = [me9, ...players([['B', '小明', 1], ['C', '小红', 1]])];

  // A 有 c01×1，想凑 3 张；A 有多余 c02×2、c03×1
  // B 有 c01×2（多余1），缺 c02 → 双向，推荐给 c02
  // C 有 c01×2（多余1），什么都不缺 → 单方
  const rows9 = inventory([
    ['A', 'c01', 1], ['A', 'c02', 3], ['A', 'c03', 2],
    ['B', 'c01', 2], ['B', 'c02', 0], ['B', 'c03', 1],
    ['C', 'c01', 2], ['C', 'c02', 1], ['C', 'c03', 1],
  ]);
  const target9 = cards9[0]; // c01
  const res9 = buildCollectRecommendations({
    me: me9, clanMembers: clanMembers9, cards: cards9, inventory: rows9,
    targetCard: target9, targetCount: 3,
  });

  assert(res9.need === 2, `还差 2 张，实际 ${res9.need}`);
  assert(res9.recs.length === 1, `只保留双向（单方被屏蔽），实际 ${res9.recs.length}`);
  assert(res9.recs[0].type === 'twoWay' && res9.recs[0].partner.gameName === '小明', '应为与小明双向');
  assert(res9.recs[0].preferredGive === 'c02', `双向优先给卡牌2，实际 ${res9.recs[0].preferredGive}`);
  assert(res9.recs[0].mySpareOptions?.length === 1 && res9.recs[0].mySpareOptions[0]?.card_id === 'c02', '下拉选项只含「对方缺少且我多余」的卡牌2（不含卡牌3）');
  assert(res9.recs.every((r) => r.type === 'twoWay'), '凑卡兑换只保留双向组合');
  assert(!res9.recs.some((r) => r.partner.gameName === '小红'), '小红什么都不缺（单方）→ 被屏蔽');

  // 已凑够 3 张 → 不需要再换
  const rows9b = inventory([
    ['A', 'c01', 3], ['A', 'c02', 3], ['A', 'c03', 1],
    ['B', 'c01', 2], ['B', 'c02', 0], ['B', 'c03', 1],
  ]);
  const res9b = buildCollectRecommendations({
    me: me9, clanMembers: clanMembers9, cards: cards9, inventory: rows9b,
    targetCard: target9, targetCount: 3,
  });
  assert(res9b.need === 0 && res9b.recs.length === 0, '已凑满 3 张 → 无需推荐');
}
// =====================================================================
// 用例 10：关闭「可被匹配」的玩家不参与匹配
// =====================================================================
{
  console.log('\n用例 10：关闭「可被匹配」的玩家不参与匹配');
  const makeP = (id, name, matchable) => ({
    player_id: id, game_name: name, player_tag: null, keep_base: 1,
    last_updated_at: '2026-08-13T00:00:00Z', matchable,
  });
  const me10 = makeP('A', '玩家A', true);
  const b10 = makeP('B', '小明', true);   // 开启
  const c10 = makeP('C', '小红', false);  // 关闭

  // 换卡推荐：B、C 都有 A 缺的 c02，但 C 关闭了可被匹配
  const rows10 = inventory([
    ['A', 'c01', 3], ['A', 'c02', 0],
    ['B', 'c01', 0], ['B', 'c02', 2],
    ['C', 'c01', 0], ['C', 'c02', 2],
  ]);
  const recs10 = buildRecommendations({
    me: me10, clanMembers: [me10, b10, c10], cards, inventory: rows10,
  });
  assert(recs10.length === 1, `只有开启者参与匹配，实际 ${recs10.length} 条`);
  assert(recs10.every((r) => r.partner.gameName === '小明'), '推荐只来自开启者小明');
  assert(!recs10.some((r) => r.partner.gameName === '小红'), '关闭者小红不应出现');

  // 凑卡兑换同样过滤
  const cards10 = [
    { card_id: 'c01', name: '卡牌1', category: 'elixir' },
    { card_id: 'c02', name: '卡牌2', category: 'elixir' },
  ];
  const rows10b = inventory([
    ['A', 'c01', 1], ['A', 'c02', 3],
    ['B', 'c01', 2], ['B', 'c02', 0],
    ['C', 'c01', 2], ['C', 'c02', 0],
  ]);
  const res10b = buildCollectRecommendations({
    me: me10, clanMembers: [me10, b10, c10], cards: cards10, inventory: rows10b,
    targetCard: cards10[0], targetCount: 3,
  });
  assert(res10b.need === 2, `凑卡还差 2 张，实际 ${res10b.need}`);
  assert(res10b.recs.length === 1 && res10b.recs[0].partner.gameName === '小明', '凑卡兑换只推荐开启者小明');
  assert(!res10b.recs.some((r) => r.partner.gameName === '小红'), '凑卡兑换中关闭者小红不应出现');
}
console.log(`\n结果：${passed} 通过，${failed} 失败`);
if (failed > 0) process.exit(1);