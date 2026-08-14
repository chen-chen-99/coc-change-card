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

/** 登录/进入：找或建部落、玩家，初始化库存（服务端 RPC） */
export async function loginPlayer({ clanName, playerName, playerTag, accessCode }) {
  if (isDemoMode) return demoApi.loginPlayer({ clanName, playerName, playerTag });
  const { data, error } = await supabase.rpc('login_player', {
    p_clan_name: clanName,
    p_player_name: playerName,
    p_player_tag: playerTag || null,
    p_access_code: accessCode || null,
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

/** 同部落全部玩家 + 本活动库存（用于换卡匹配） */
export async function getClanTradingData(clanId, cardIds) {
  if (isDemoMode) return demoApi.getClanTradingData(clanId, cardIds);
  const { data: players, error: err1 } = await supabase
    .from('players')
    .select('player_id, game_name, player_tag, keep_base, last_updated_at')
    .eq('clan_id', clanId);
  if (err1) throw new Error(`读取部落成员失败：${err1.message}`);

  const list = players || [];
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