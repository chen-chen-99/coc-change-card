/**
 * 演示模式（Demo Mode）
 * ------------------------------------------------------------------
 * 触发条件（满足其一）：
 *   1. 未配置 VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY
 *   2. VITE_DEMO_MODE === 'true'
 *
 * 演示模式下所有数据保存在内存中，刷新页面即重置；
 * 配置好 .env 中的 Supabase 信息后自动切换到真实数据。
 */

export const isDemoMode =
  import.meta.env.VITE_DEMO_MODE === 'true' ||
  !import.meta.env.VITE_SUPABASE_URL ||
  !import.meta.env.VITE_SUPABASE_ANON_KEY;

const ACTIVITY = {
  activity_id: 'card_clash_2026_08',
  name: '卡牌冲突 2026年8月（演示）',
  start_time: '2026-08-01T00:00:00+08:00',
  end_time: '2026-08-31T23:59:59+08:00',
};

/** 真实卡牌清单：种类 -> 卡名列表（与 supabase/schema.sql 一致） */
const CARD_NAMES = {
  elixir: ['野蛮人', '弓箭手', '巨人', '哥布林', '炸弹人', '气球兵', '法师', '天使', '飞龙', '皮卡超人', '飞龙宝宝', '掘地矿工', '雷电飞龙', '大雪怪', '龙骑士', '雷霆泰坦', '根蔓骑士', '巨矛投手', '陨石戈仑'],
  dark_elixir: ['亡灵', '野猪骑士', '瓦基里丽武神', '戈仑石人', '女巫', '熔岩猎犬', '巨石投手', '戈仑冰人', '英雄猎手', '守护者学徒', '德鲁伊', '烈焰熔炉', '废墟女巫'],
  builder_base: ['狂暴野蛮人', '隐秘弓箭手', '巨人拳击手', '异变亡灵', '炸弹兵', '飞龙宝宝', '加农炮战车', '暗夜女巫', '骷髅气球', '雷霆皮卡', '野猪飞骑'],
  super_troop: ['超级野蛮人', '超级弓箭手', '超级巨人', '隐秘哥布林', '超级炸弹人', '火箭气球兵', '超级法师', '超级飞龙', '地狱飞龙', '超级矿工', '超级大雪怪', '超级亡灵', '超级野猪骑士', '超级瓦基丽武神', '超级女巫', '寒冰猎犬', '超级巨石投手'],
};

const PREFIX = { elixir: 'e', dark_elixir: 'd', builder_base: 'b', super_troop: 's' };

const CARDS = [];
let sort = 0;
for (const [category, names] of Object.entries(CARD_NAMES)) {
  names.forEach((name, i) => {
    sort += 1;
    const id = `${PREFIX[category]}${String(i + 1).padStart(2, '0')}`;
    CARDS.push({
      card_id: id,
      activity_id: ACTIVITY.activity_id,
      name,
      category,
      image_url: `images/cards/${id}.png`,
      sort_order: sort,
    });
  });
}

const CLAN_ID = 'demo-clan';
const CLAN_NAME = '演示部落';
const DEMO_USER_ID = 'demo-user';

const nowIso = () => new Date().toISOString();

/**
 * 演示库存生成规则（按种类内局部下标 k，保证推荐结果种类内闭环）：
 *   me  ：k%3==0 缺，k%3==1 有 3 张（富余），k%3==2 有 1 张（无富余）
 *   小明：k%3==0 有 2 张，k%3==1 缺，k%3==2 有 2 张 → 与我双向互补
 *   小红：k%3==2 缺，其余有 2 张 → 我缺的卡她有（单向）
 *   老王：全部 3 张 → 我缺的卡他有（单向，且他无缺卡）
 *   阿强：k%3==2 缺，k%3==0/1 有 2 张 → 我缺的卡他有（单向）
 */
const PATTERNS = {
  me:       (k) => (k % 3 === 0 ? 0 : k % 3 === 1 ? 3 : 1),
  xiaoming: (k) => (k % 3 === 1 ? 0 : 2),
  xiaohong: (k) => (k % 3 === 2 ? 0 : 2),
  laowang:  () => 3,
  aqiang:   (k) => (k % 3 === 2 ? 0 : 2),
};

const MEMBER_META = {
  xiaoming: { game_name: '小明', player_tag: '#XIAOMING', channel: 'wechat' },
  xiaohong: { game_name: '小红', player_tag: '#XIAOHONG', channel: 'wechat' },
  laowang:  { game_name: '老王', player_tag: '#LAOWANG', channel: 'qq' },
  aqiang:   { game_name: '阿强', player_tag: '#AQIANG', channel: 'wechat' },
};

function buildMemberInventory(playerId, pattern) {
  const rows = [];
  for (const category of Object.keys(CARD_NAMES)) {
    const names = CARD_NAMES[category];
    names.forEach((_, k) => {
      const id = `${PREFIX[category]}${String(k + 1).padStart(2, '0')}`;
      rows.push({ player_id: playerId, card_id: id, quantity: pattern(k) });
    });
  }
  return rows;
}

/** 内存状态：当前登录的玩家 + 部落全部玩家（含成员） */
const state = {
  clanId: CLAN_ID,
  clanName: CLAN_NAME,
  players: Object.entries(MEMBER_META).map(([key, meta]) => ({
    player_id: `demo-${key}`,
    clan_id: CLAN_ID,
    game_name: meta.game_name,
    player_tag: meta.player_tag,
    keep_base: 1,
    owner_user_id: DEMO_USER_ID,
    access_code_set: false,
    editable: false,
    channel: meta.channel ?? 'wechat',
    matchable: true,
    last_updated_at: '2026-08-13T12:00:00Z',
  })),
  inventory: Object.entries(MEMBER_META).flatMap(([key]) =>
    buildMemberInventory(`demo-${key}`, PATTERNS[key])
  ),
  exchanges: [],
};

function ensurePlayer(gameName, playerTag, channel = 'wechat') {
  let p = state.players.find((x) => x.game_name === gameName);
  if (!p) {
    p = {
      player_id: `demo-me-${Date.now()}`,
      clan_id: CLAN_ID,
      clan_name: CLAN_NAME,
      game_name: gameName,
      player_tag: playerTag || null,
      keep_base: 1,
      owner_user_id: DEMO_USER_ID,
      access_code_set: false,
      editable: true,
      channel,
      matchable: true,
      last_updated_at: nowIso(),
    };
    state.players.push(p);
    state.inventory.push(...buildMemberInventory(p.player_id, PATTERNS.me));
  } else {
    p = { ...p, player_tag: p.player_tag || playerTag || null, editable: true, last_updated_at: nowIso() };
    const idx = state.players.findIndex((x) => x.player_id === p.player_id);
    state.players[idx] = p;
  }
  return p;
}

/** 演示模式下已完成的交换（模拟数据库唯一约束，防重复） */
const completedSwaps = new Set();
let exchangeSeq = 0;

/** 库存增减（模拟数据库 upsert） */
function setQuantity(pid, cid, delta) {
  const row = state.inventory.find((r) => r.player_id === pid && r.card_id === cid);
  if (row) row.quantity = Math.max(0, row.quantity + delta);
  else state.inventory.push({ player_id: pid, card_id: cid, quantity: Math.max(0, delta) });
}

export const demoApi = {
  async signInAnonymously() {
    return { id: DEMO_USER_ID };
  },

  async loginPlayer({ clanName, playerName, playerTag, channel }) {
    const p = ensurePlayer(playerName, playerTag, channel);
    return { ...p, clan_name: clanName, editable: true };
  },

  async getCurrentActivity() {
    return ACTIVITY;
  },

  async getActivityCards() {
    return CARDS;
  },

  async getMyInventory(playerId) {
    const map = {};
    for (const row of state.inventory) {
      if (row.player_id === playerId) map[row.card_id] = row.quantity;
    }
    return map;
  },

  async setAccessCode(playerId, newCode) {
    const p = state.players.find((x) => x.player_id === playerId);
    if (p) p.access_code_set = !!newCode;
    return { player_id: playerId, access_code_set: !!newCode, editable: true };
  },

  async updateQuantity(playerId, cardId, quantity) {
    const row = state.inventory.find((r) => r.player_id === playerId && r.card_id === cardId);
    if (row) row.quantity = quantity;
    else state.inventory.push({ player_id: playerId, card_id: cardId, quantity });
    return quantity;
  },

  async executeExchange({ activityId, playerA, playerB, cardFromA, cardFromB }) {
    const [pa, pb] = [playerA, playerB].sort();
    const [ca, cb] = pa === playerA ? [cardFromA, cardFromB] : [cardFromB, cardFromA];
    const key = `${activityId}|${pa}|${pb}|${ca}|${cb}`;
    if (completedSwaps.has(key)) return { status: 'already_done', updated: [] };

    const qa = state.inventory.find((r) => r.player_id === pa && r.card_id === ca)?.quantity ?? 0;
    const qb = state.inventory.find((r) => r.player_id === pb && r.card_id === cb)?.quantity ?? 0;
    const keepA = state.players.find((p) => p.player_id === pa)?.keep_base ?? 1;
    const keepB = state.players.find((p) => p.player_id === pb)?.keep_base ?? 1;
    if (qa - keepA <= 0) throw new Error('你已没有多余的卡可交换');
    if (qb - keepB <= 0) throw new Error('对方已没有多余的卡可交换');

    setQuantity(pa, ca, -1);
    setQuantity(pb, cb, -1);
    setQuantity(pa, cb, 1);
    setQuantity(pb, ca, 1);
    completedSwaps.add(key);
    state.exchanges.push({
      exchange_id: `ex-${Date.now()}-${(exchangeSeq += 1)}`,
      activity_id: activityId,
      player_a: pa,
      player_b: pb,
      card_from_a: ca,
      card_from_b: cb,
      created_at: nowIso(),
    });

    const updated = state.inventory
      .filter((r) => (r.player_id === pa || r.player_id === pb) && (r.card_id === ca || r.card_id === cb))
      .map((r) => ({ player_id: r.player_id, card_id: r.card_id, quantity: r.quantity }));
    return { status: 'ok', updated };
  },

  async getMyExchangeRecords(playerId) {
    return state.exchanges
      .filter((e) => e.player_a === playerId || e.player_b === playerId)
      .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
      .map((e) => {
        const isA = e.player_a === playerId;
        const partnerId = isA ? e.player_b : e.player_a;
        const partner = state.players.find((p) => p.player_id === partnerId);
        const iGaveId = isA ? e.card_from_a : e.card_from_b;
        const iGotId = isA ? e.card_from_b : e.card_from_a;
        const cardName = (id) => CARDS.find((c) => c.card_id === id)?.name ?? id;
        return {
          exchange_id: e.exchange_id,
          created_at: e.created_at,
          partnerName: partner?.game_name ?? '未知玩家',
          partnerTag: partner?.player_tag ?? null,
          partnerClan: partner?.clan_name ?? CLAN_NAME,
          iGaveName: cardName(iGaveId),
          iGotName: cardName(iGotId),
        };
      });
  },

  async undoExchange(exchangeId) {
    const idx = state.exchanges.findIndex((e) => e.exchange_id === exchangeId);
    if (idx === -1) throw new Error('交换记录不存在');
    const e = state.exchanges[idx];

    const qA = state.inventory.find((r) => r.player_id === e.player_a && r.card_id === e.card_from_b)?.quantity ?? 0;
    const qB = state.inventory.find((r) => r.player_id === e.player_b && r.card_id === e.card_from_a)?.quantity ?? 0;
    if (qA <= 0 || qB <= 0) throw new Error('撤销失败：该交换的卡已被用于其他交换，无法撤销');

    setQuantity(e.player_a, e.card_from_b, -1);
    setQuantity(e.player_a, e.card_from_a, 1);
    setQuantity(e.player_b, e.card_from_a, -1);
    setQuantity(e.player_b, e.card_from_b, 1);
    state.exchanges.splice(idx, 1);

    const [pa, pb] = [e.player_a, e.player_b].sort();
    const [ca, cb] = pa === e.player_a ? [e.card_from_a, e.card_from_b] : [e.card_from_b, e.card_from_a];
    completedSwaps.delete(`${e.activity_id}|${pa}|${pb}|${ca}|${cb}`);

    const updated = state.inventory
      .filter(
        (r) =>
          (r.player_id === e.player_a || r.player_id === e.player_b) &&
          (r.card_id === e.card_from_a || r.card_id === e.card_from_b)
      )
      .map((r) => ({ player_id: r.player_id, card_id: r.card_id, quantity: r.quantity }));
    return { status: 'ok', updated };
  },

  async getMyExchangeCount(playerId) {
    return state.exchanges.filter((e) => e.player_a === playerId || e.player_b === playerId).length;
  },
  async getNotificationSettings(playerId) {
    const s = state.notifySettings?.get(playerId);
    return s || { player_id: playerId, email: null, enabled: false, scope: 'twoWay' };
  },

  async setNotificationSettings(playerId, { email, enabled, scope }) {
    if (!state.notifySettings) state.notifySettings = new Map();
    const s = { player_id: playerId, email: email || null, enabled: !!enabled, scope: scope || 'twoWay' };
    state.notifySettings.set(playerId, s);
    return s;
  },
  async getPlayerBanned(playerId) {
    const p = state.players.find((x) => x.player_id === playerId);
    return p ? p.banned === true : false;
  },
  async getMatchable(playerId) {
    const p = state.players.find((x) => x.player_id === playerId);
    return p ? p.matchable !== false : true;
  },
  async setMatchable(playerId, matchable) {
    const p = state.players.find((x) => x.player_id === playerId);
    if (p) p.matchable = !!matchable;
    return { player_id: playerId, matchable: !!matchable };
  },
  async getExchangeStats() {
    return {
      playerCount: state.players.length,
      exchangeCount: state.exchanges.length,
    };
  },
  async getClanTradingData(clanId, cardIds, scope = 'clan', channel = 'wechat') {
    let scoped = state.players;
    if (scope === 'clan') scoped = scoped.filter((p) => p.clan_id === clanId);
    else if (scope === 'channel') scoped = scoped.filter((p) => (p.channel ?? 'wechat') === channel);
    const players = scoped.map((p) => ({
      player_id: p.player_id,
      game_name: p.game_name,
      player_tag: p.player_tag,
      keep_base: p.keep_base,
      last_updated_at: p.last_updated_at,
      clan_id: p.clan_id,
      clan_name: p.clan_name ?? CLAN_NAME,
      channel: p.channel ?? 'wechat',
      matchable: p.matchable !== false,
    }));
    const inventory = state.inventory.filter((r) => cardIds.includes(r.card_id));
    return { players, inventory };
  },
};