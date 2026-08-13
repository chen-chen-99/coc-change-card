/**
 * 换卡匹配算法（纯前端计算，无外部依赖）
 *
 * 概念定义（对玩家 p、卡牌 c、数量 q、保留基数 K）：
 *   拥有   owned   : q > 0
 *   缺少   missing : q === 0
 *   多余   spare   : max(0, q - K)
 *   可交换 hasSpare: q - K > 0
 *
 * 推荐优先级：
 *   1. twoWay 双向直接交换（我给 X、对方给我 Y，双方各解决一张缺卡）
 *   2. oneWay 对方拥有我需要的卡（单向，供主动联系）
 */

/** 计算某玩家对某张卡的派生状态 */
export function computeCardView(quantity, keepBase = 1) {
  const q = Math.max(0, Number(quantity) || 0);
  return {
    quantity: q,
    owned: q > 0,
    missing: q === 0,
    spare: Math.max(0, q - keepBase),
    hasSpare: q - keepBase > 0,
  };
}

/**
 * 生成换卡推荐
 * @param {object} options
 * @param {object} options.me         当前玩家（含 player_id, keep_base）
 * @param {Array}  options.clanMembers 同部落全部玩家（含 me，字段含 player_id, game_name, keep_base, last_updated_at）
 * @param {Array}  options.cards       活动卡牌列表（字段含 card_id, name, image_url）
 * @param {Array}  options.inventory   库存行 [{ player_id, card_id, quantity }]
 * @returns {Array<TradeRecommendation>}
 */
export function buildRecommendations({ me, clanMembers = [], cards = [], inventory = [] }) {
  // 库存索引：playerId -> cardId -> quantity（缺失按 0 处理）
  const q = {};
  for (const row of inventory) {
    if (!q[row.player_id]) q[row.player_id] = {};
    q[row.player_id][row.card_id] = row.quantity;
  }
  const quantityOf = (playerId, cardId) => q[playerId]?.[cardId] ?? 0;
  const keepOf = (player) => player.keep_base ?? 1;
  const hasSpare = (player, cardId) =>
    quantityOf(player.player_id, cardId) - keepOf(player) > 0;
  const missingCards = (player) =>
    cards.filter((c) => quantityOf(player.player_id, c.card_id) === 0);
  const spareCards = (player) =>
    cards.filter((c) => quantityOf(player.player_id, c.card_id) - keepOf(player) > 0);

  const myNeeds = new Set(missingCards(me).map((c) => c.card_id));
  const mySpareSet = new Set(spareCards(me).map((c) => c.card_id));
  const others = clanMembers.filter((m) => m.player_id !== me.player_id);
  const cardById = new Map(cards.map((c) => [c.card_id, c]));

  const result = [];

  for (const needId of myNeeds) {
    const needCard = cardById.get(needId);
    if (!needCard) continue;

    const providers = others.filter((m) => hasSpare(m, needId));

    for (const m of providers) {
      // 双向互补：对方缺的卡 y 必须与我缺的卡 needId 同种类（同种类才能交换）
      // 且该卡我有富余
      const mutual = missingCards(m).filter(
        (c) => c.category === needCard.category && mySpareSet.has(c.card_id)
      );

      if (mutual.length > 0) {
        for (const y of mutual) {
          result.push({
            type: 'twoWay',
            cardINeed: needCard,                          // 我需要的卡（分组依据）
            iGet: needCard,                               // 我获得
            iGive: y,                                     // 我给对方的卡
            partner: {
              playerId: m.player_id,
              gameName: m.game_name,
              playerTag: m.player_tag ?? null,
              spareQuantity: quantityOf(m.player_id, needId) - keepOf(m),
              lastUpdatedAt: m.last_updated_at,
            },
            resolvedCount: 2,                             // 双向一次解决 2 个需求
          });
        }
      } else {
        result.push({
          type: 'oneWay',
          cardINeed: needCard,
          iGet: needCard,
          iGive: null,
          partner: {
            playerId: m.player_id,
            gameName: m.game_name,
            playerTag: m.player_tag ?? null,
            spareQuantity: quantityOf(m.player_id, needId) - keepOf(m),
            lastUpdatedAt: m.last_updated_at,
          },
          resolvedCount: 1,
        });
      }
    }
  }

  // 排序：双向优先 → 解决需求数多优先 → 对方余量多优先 → 对方数据新优先
  const typeRank = { twoWay: 0, oneWay: 1 };
  result.sort((a, b) => {
    if (typeRank[a.type] !== typeRank[b.type]) return typeRank[a.type] - typeRank[b.type];
    if (b.resolvedCount !== a.resolvedCount) return b.resolvedCount - a.resolvedCount;
    if (b.partner.spareQuantity !== a.partner.spareQuantity)
      return b.partner.spareQuantity - a.partner.spareQuantity;
    return String(b.partner.lastUpdatedAt).localeCompare(String(a.partner.lastUpdatedAt));
  });

  return result;
}

/** 按"我缺少的卡"分组，供换卡页面展示 */
export function groupByNeededCard(recommendations) {
  const groups = new Map();
  for (const rec of recommendations) {
    const key = rec.cardINeed.card_id;
    if (!groups.has(key)) groups.set(key, { card: rec.cardINeed, items: [] });
    groups.get(key).items.push(rec);
  }
  return [...groups.values()];
}
