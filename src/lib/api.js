import { supabase } from './supabase.js';
import { isDemoMode, demoApi } from './demo.js';

/** 当前是否为演示模式（未配置 Supabase 时自动启用） */
export { isDemoMode };

/** Supabase 匿名登录（需在 Auth 设置中开启 Allow anonymous sign-ins） */
export async function signInAnonymously() {
  if (isDemoMode) return demoApi.signInAnonymously();
  const { data, error } = await supabase.auth.signInAnonymously();
  if (error) throw new Error(`匿名登录失败：${error.message}`);
  return data.user;
}

/** 登录/进入：找或建部落、玩家，初始化库存（服务端 RPC）。channel: 'wechat' 微信区 / 'qq' QQ区 */
export async function loginPlayer({ clanName, playerName, playerTag, accessCode, channel }) {
  if (isDemoMode) return demoApi.loginPlayer({ clanName, playerName, playerTag, channel });
  const { data, error } = await supabase.rpc('login_player', {
    p_clan_name: clanName,
    p_player_name: playerName,
    p_player_tag: playerTag || null,
    p_access_code: accessCode || null,
    p_channel: channel || 'wechat',
  });
  if (error) throw new Error(`进入失败：${error.message}`);
  return data;
}

/** 当前活动：优先进行中的，否则取最近开始的活动 */
export async function getCurrentActivity() {
  if (isDemoMode) return demoApi.getCurrentActivity();
  const { data, error } = await supabase.from('activities').select('*');
  if (error) throw new Error(`读取活动失败：${error.message}`);
  if (!data || data.length === 0) return null;

  const now = Date.now();
  const byStartDesc = (a, b) => new Date(b.start_time) - new Date(a.start_time);
  const active = data
    .filter((a) => now >= new Date(a.start_time).getTime() && now <= new Date(a.end_time).getTime())
    .sort(byStartDesc);
  return active[0] || [...data].sort(byStartDesc)[0];
}

/** 活动卡牌列表 */
export async function getActivityCards(activityId) {
  if (isDemoMode) return demoApi.getActivityCards(activityId);
  const { data, error } = await supabase
    .from('cards')
    .select('*')
    .eq('activity_id', activityId)
    .order('sort_order');
  if (error) throw new Error(`读取卡牌失败：${error.message}`);
  return data || [];
}

/** 我的库存：cardId -> quantity */
export async function getMyInventory(playerId, cardIds) {
  if (isDemoMode) return demoApi.getMyInventory(playerId);
  if (!cardIds.length) return {};
  const { data, error } = await supabase
    .from('player_cards')
    .select('card_id, quantity')
    .eq('player_id', playerId)
    .in('card_id', cardIds);
  if (error) throw new Error(`读取库存失败：${error.message}`);
  const map = {};
  for (const row of data || []) map[row.card_id] = row.quantity;
  return map;
}

/**
 * 更新某张卡数量（upsert，兼容新活动新增卡牌时库存行不存在的情况）
 * ± 逻辑由调用方计算，服务端受 RLS 保护（只能改自己绑定的玩家数据）
 */
export async function updateQuantity(playerId, cardId, quantity) {
  if (isDemoMode) return demoApi.updateQuantity(playerId, cardId, quantity);
  const { data, error } = await supabase
    .from('player_cards')
    .upsert(
      { player_id: playerId, card_id: cardId, quantity, updated_at: new Date().toISOString() },
      { onConflict: 'player_id,card_id' }
    )
    .select();
  if (error) throw new Error(`保存失败：${error.message}（可能该玩家数据已绑定其他设备）`);
  return data?.[0]?.quantity;
}

/**
 * 玩家 + 本活动库存（用于换卡匹配）
 * @param {string} scope 'clan' 仅同部落 | 'channel' 同渠道（区服）
 * @param {string} channel 当前玩家登录渠道：'wechat' | 'qq'
 */
export async function getClanTradingData(clanId, cardIds, scope = 'clan', channel = 'wechat') {
  if (isDemoMode) return demoApi.getClanTradingData(clanId, cardIds, scope, channel);
  let query = supabase
    .from('players')
    .select('player_id, game_name, player_tag, keep_base, last_updated_at, clan_id, channel, clans(name)');
  if (scope === 'clan') query = query.eq('clan_id', clanId);
  else if (scope === 'channel') query = query.eq('channel', channel);
  const { data: players, error: err1 } = await query;
  if (err1) throw new Error(`读取玩家数据失败：${err1.message}`);

  const list = (players || []).map((p) => ({
    player_id: p.player_id,
    game_name: p.game_name,
    player_tag: p.player_tag,
    keep_base: p.keep_base,
    last_updated_at: p.last_updated_at,
    clan_id: p.clan_id,
    clan_name: p.clans?.name ?? null,
    channel: p.channel ?? 'wechat',
  }));
  if (!cardIds.length || list.length === 0) {
    return { players: list, inventory: [] };
  }

  const { data: inventory, error: err2 } = await supabase
    .from('player_cards')
    .select('player_id, card_id, quantity')
    .in('player_id', list.map((p) => p.player_id))
    .in('card_id', cardIds);
  if (err2) throw new Error(`读取成员库存失败：${err2.message}`);

  return { players: list, inventory: inventory || [] };
}
/**
 * 一键交换：双方在游戏中交换后，任一方点击按钮即可原子同步双方数据
 * @returns {{ status: 'ok'|'already_done', updated?: Array<{player_id, card_id, quantity}> }}
 */
export async function executeExchange({ activityId, playerA, playerB, cardFromA, cardFromB }) {
  if (isDemoMode) return demoApi.executeExchange({ activityId, playerA, playerB, cardFromA, cardFromB });
  const { data, error } = await supabase.rpc('execute_exchange', {
    p_activity_id: activityId,
    p_player_a: playerA,
    p_player_b: playerB,
    p_card_from_a: cardFromA,
    p_card_from_b: cardFromB,
  });
  if (error) throw new Error(`交换失败：${error.message}`);
  return data;
}
/** 我的换卡记录（涉及我的历史交换，含对方/卡牌信息），按时间倒序 */
export async function getMyExchangeRecords(playerId, cardIds) {
  if (isDemoMode) return demoApi.getMyExchangeRecords(playerId, cardIds);
  const { data: exchanges, error: err1 } = await supabase
    .from('exchanges')
    .select('*')
    .or(`player_a.eq.${playerId},player_b.eq.${playerId}`)
    .order('created_at', { ascending: false });
  if (err1) throw new Error(`读取换卡记录失败：${err1.message}`);
  if (!exchanges || exchanges.length === 0) return [];

  const playerIds = [...new Set(exchanges.flatMap((e) => [e.player_a, e.player_b]))];
  const cardIdsSet = [...new Set(exchanges.flatMap((e) => [e.card_from_a, e.card_from_b]))];

  const { data: players, error: err2 } = await supabase
    .from('players')
    .select('player_id, game_name, player_tag, clan_id, clans(name)')
    .in('player_id', playerIds);
  if (err2) throw new Error(`读取玩家信息失败：${err2.message}`);

  const { data: cards, error: err3 } = await supabase
    .from('cards')
    .select('card_id, name')
    .in('card_id', cardIdsSet);
  if (err3) throw new Error(`读取卡牌信息失败：${err3.message}`);

  const playerById = new Map((players || []).map((p) => [p.player_id, p]));
  const cardById = new Map((cards || []).map((c) => [c.card_id, c]));

  return (exchanges || []).map((e) => {
    const isA = e.player_a === playerId;
    const partner = playerById.get(isA ? e.player_b : e.player_a);
    const iGaveId = isA ? e.card_from_a : e.card_from_b;
    const iGotId = isA ? e.card_from_b : e.card_from_a;
    return {
      exchange_id: e.exchange_id,
      created_at: e.created_at,
      partnerName: partner?.game_name ?? '未知玩家',
      partnerTag: partner?.player_tag ?? null,
      partnerClan: partner?.clans?.name ?? null,
      iGaveName: cardById.get(iGaveId)?.name ?? iGaveId,
      iGotName: cardById.get(iGotId)?.name ?? iGotId,
    };
  });
}

/** 我的成功换卡次数（涉及我的交换记录数） */
export async function getMyExchangeCount(playerId) {
  if (isDemoMode) return demoApi.getMyExchangeCount(playerId);
  const { count, error } = await supabase
    .from('exchanges')
    .select('exchange_id', { count: 'exact', head: true })
    .or(`player_a.eq.${playerId},player_b.eq.${playerId}`);
  if (error) throw new Error(`读取换卡记录失败：${error.message}`);
  return count ?? 0;
}
/** 撤销一笔交换（RPC：仅交换双方之一可撤销；校验库存足以归还） */
export async function undoExchange(exchangeId) {
  if (isDemoMode) return demoApi.undoExchange(exchangeId);
  const { data, error } = await supabase.rpc('undo_exchange', { p_exchange_id: exchangeId });
  if (error) throw new Error(`撤销失败：${error.message}`);
  return data;
}
/** 全站统计：玩家总数 + 成功换卡次数（供登录页/推荐页展示） */
export async function getExchangeStats() {
  if (isDemoMode) return demoApi.getExchangeStats();
  const [pRes, eRes] = await Promise.all([
    supabase.from('players').select('player_id', { count: 'exact', head: true }),
    supabase.from('exchanges').select('exchange_id', { count: 'exact', head: true }),
  ]);
  if (pRes.error) throw new Error(`读取统计失败：${pRes.error.message}`);
  if (eRes.error) throw new Error(`读取统计失败：${eRes.error.message}`);
  return { playerCount: pRes.count ?? 0, exchangeCount: eRes.count ?? 0 };
}
/** 设置/修改/清除访问码（RPC：无访问码可任意设置；已设置则仅主人可改） */
export async function setAccessCode(playerId, newCode) {
  if (isDemoMode) return demoApi.setAccessCode(playerId, newCode);
  const { data, error } = await supabase.rpc('set_access_code', {
    p_player_id: playerId,
    p_new_code: newCode || null,
  });
  if (error) throw new Error(`访问码操作失败：${error.message}`);
  return data;
}