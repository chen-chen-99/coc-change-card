import { supabase } from './supabase.js';

async function rpc(name, args) {
  const { data, error } = await supabase.rpc(name, args);
  if (error) throw new Error(error.message);
  return data;
}

/** 分页拉取全部行（PostgREST 单次最多 1000 行） */
export async function fetchAll(table, select, orderBy = 'player_id') {
  const rows = [];
  const pageSize = 1000;
  let from = 0;
  for (;;) {
    const { data, error } = await supabase
      .from(table)
      .select(select)
      .order(orderBy)
      .range(from, from + pageSize - 1);
    if (error) throw error;
    const batch = data || [];
    rows.push(...batch);
    if (batch.length < pageSize) break;
    from += pageSize;
  }
  return rows;
}

/**
 * 后台管理 API（所有操作都需要管理员口令，口令由服务端 RPC 校验，
 * 口令不经过前端持久化，仅保存在内存中）
 */
export const adminApi = {
  verify: (code) => rpc('admin_verify', { p_admin_code: code }),
  stats: (code) => rpc('admin_stats', { p_admin_code: code }),
  listPlayers: (code) => rpc('admin_list_players', { p_admin_code: code }),
  listClans: (code) => rpc('admin_list_clans', { p_admin_code: code }),
  setMatchable: (code, playerId, matchable) =>
    rpc('admin_set_matchable', { p_admin_code: code, p_player_id: playerId, p_matchable: matchable }),
  setBanned: (code, playerId, banned) =>
    rpc('admin_set_banned', { p_admin_code: code, p_player_id: playerId, p_banned: banned }),
  deletePlayer: (code, playerId) =>
    rpc('admin_delete_player', { p_admin_code: code, p_player_id: playerId }),
  deleteClan: (code, clanId) =>
    rpc('admin_delete_clan', { p_admin_code: code, p_clan_id: clanId }),
};