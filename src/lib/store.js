import { reactive } from 'vue';

// 全局会话状态：登录后写入，刷新时从 localStorage 恢复
export const session = reactive({
  user: null,      // Supabase 匿名用户
  player: null,    // login_player RPC 返回的玩家信息
  activity: null,  // 当前活动
  cards: [],       // 活动卡牌列表
  inventory: {},   // cardId -> quantity
  loading: false,
  error: null,
});

const STORAGE_KEY = 'card_clash_session_v1';

export function saveSession() {
  localStorage.setItem(
    STORAGE_KEY,
    JSON.stringify({
      user: session.user,
      player: session.player,
      activity: session.activity,
    })
  );
}

export function loadSession() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const data = JSON.parse(raw);
    return data;
  } catch {
    return null;
  }
}

export function clearSession() {
  localStorage.removeItem(STORAGE_KEY);
  session.user = null;
  session.player = null;
  session.activity = null;
  session.cards = [];
  session.inventory = {};
  session.error = null;
}
