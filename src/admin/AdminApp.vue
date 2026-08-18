<script setup>
import { ref, computed, onMounted } from 'vue';
import { adminApi, fetchAll } from '../lib/adminApi.js';
import { buildRecommendations } from '../lib/matching.js';

const code = ref('');
const authed = ref(false);
const tab = ref('overview');
const error = ref('');
const notice = ref('');
const loading = ref(false);
const busy = ref(false);

const stats = ref(null);
const players = ref([]);
const clans = ref([]);
const channelMatch = ref(null);
const search = ref('');

const CHANNEL_LABEL = { wechat: '💬 微信区', qq: '🐧 QQ区' };
const TABS = [
  { key: 'overview', label: '📊 概览' },
  { key: 'users', label: '👥 用户管理' },
  { key: 'clans', label: '🏰 部落管理' },
];

const filteredPlayers = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return players.value;
  return players.value.filter(
    (p) =>
      p.game_name.toLowerCase().includes(q) ||
      (p.player_tag || '').toLowerCase().includes(q) ||
      (p.clan_name || '').toLowerCase().includes(q)
  );
});

function fmt(ts) {
  if (!ts) return '—';
  const d = new Date(ts);
  return isNaN(d.getTime()) ? '—' : d.toLocaleString('zh-CN');
}

async function login() {
  error.value = '';
  if (!code.value.trim()) {
    error.value = '请输入管理员口令';
    return;
  }
  loading.value = true;
  try {
    await adminApi.verify(code.value.trim());
    authed.value = true;
    await refreshAll();
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}

function logout() {
  authed.value = false;
  code.value = '';
  stats.value = null;
  players.value = [];
  clans.value = [];
  channelMatch.value = null;
}

async function refreshAll() {
  loading.value = true;
  error.value = '';
  notice.value = '';
  try {
    const [s, ps, cs] = await Promise.all([
      adminApi.stats(code.value),
      adminApi.listPlayers(code.value),
      adminApi.listClans(code.value),
    ]);
    stats.value = s;
    players.value = ps || [];
    clans.value = cs || [];
    await computeChannelMatches();
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}

async function refreshStatsOnly() {
  try {
    stats.value = await adminApi.stats(code.value);
  } catch (e) {
    error.value = e.message;
  }
}

/** 前端计算：各渠道当前有没有可匹配的数据（复用换卡匹配算法） */
async function computeChannelMatches() {
  const [cards, allPlayers, inventory] = await Promise.all([
    fetchAll('cards', 'card_id,name,category', 'card_id'),
    fetchAll('players', 'player_id, game_name, keep_base, clan_id, channel, matchable, last_updated_at', 'player_id'),
    fetchAll('player_cards', 'player_id, card_id, quantity', 'player_id'),
  ]);
  const result = {};
  for (const ch of ['wechat', 'qq']) {
    const members = allPlayers.filter((p) => p.channel === ch && p.matchable !== false);
    let withMatch = 0;
    let twoWay = 0;
    let oneWay = 0;
    for (const me of members) {
      const others = members.filter((m) => m.player_id !== me.player_id);
      const recs = buildRecommendations({ me, clanMembers: others, cards, inventory });
      if (recs.length > 0) withMatch += 1;
      twoWay += recs.filter((r) => r.type === 'twoWay').length;
      oneWay += recs.filter((r) => r.type === 'oneWay').length;
    }
    result[ch] = { players: members.length, withMatch, twoWay, oneWay };
  }
  channelMatch.value = result;
}

async function toggleBanned(p) {
  const action = p.banned ? '启用' : '禁用';
  const tip = p.banned
    ? '启用后该用户可正常登录使用。'
    : '禁用后该用户登录时会提示「先加群 / 联系开发者」，且无法再修改库存或交换。';
  if (!window.confirm(`确定要${action}「${p.game_name}」吗？${tip}`)) return;
  busy.value = true;
  try {
    await adminApi.setBanned(code.value, p.player_id, !p.banned);
    p.banned = !p.banned;
    notice.value = `已${action}「${p.game_name}」`;
    await refreshStatsOnly();
  } catch (e) {
    error.value = e.message;
  } finally {
    busy.value = false;
  }
}

async function removePlayer(p) {
  if (!window.confirm(`确定要删除用户「${p.game_name}」吗？\n将同时删除其库存、换卡记录与通知设置，且不可恢复！`)) return;
  busy.value = true;
  try {
    await adminApi.deletePlayer(code.value, p.player_id);
    players.value = players.value.filter((x) => x.player_id !== p.player_id);
    notice.value = `已删除用户「${p.game_name}」`;
    await Promise.all([refreshStatsOnly(), computeChannelMatches()]);
  } catch (e) {
    error.value = e.message;
  } finally {
    busy.value = false;
  }
}

async function removeClan(c) {
  if (!window.confirm(`确定要删除部落「${c.name}」吗？\n将删除该部落全部 ${c.member_count} 名玩家及其数据，且不可恢复！`)) return;
  busy.value = true;
  try {
    await adminApi.deleteClan(code.value, c.clan_id);
    clans.value = clans.value.filter((x) => x.clan_id !== c.clan_id);
    players.value = players.value.filter((x) => x.clan_id !== c.clan_id);
    notice.value = `已删除部落「${c.name}」`;
    await Promise.all([refreshStatsOnly(), computeChannelMatches()]);
  } catch (e) {
    error.value = e.message;
  } finally {
    busy.value = false;
  }
}

onMounted(() => {});
</script>

<template>
  <div class="admin-app">
    <!-- 未登录：口令验证 -->
    <section v-if="!authed" class="login-box">
      <h1>🔐 后台管理</h1>
      <p class="hint">卡牌冲突换卡助手 · 管理员入口</p>
      <label class="field">
        <span>管理员口令</span>
        <input v-model="code" type="password" placeholder="请输入管理员口令" @keyup.enter="login" />
      </label>
      <p v-if="error" class="form-error">{{ error }}</p>
      <button class="btn btn-primary btn-block" :disabled="loading" @click="login">
        {{ loading ? '验证中…' : '进入后台' }}
      </button>
      <p class="hint">口令保存在 Supabase 的 app_config.admin_code（migration_v13 已生成默认口令，请务必修改）。</p>
    </section>

    <!-- 已登录：后台主界面 -->
    <template v-else>
      <header class="admin-head">
        <div class="admin-title">🔐 卡牌冲突 · 后台管理</div>
        <div class="admin-head-right">
          <button class="btn" :disabled="loading" @click="refreshAll">🔄 刷新</button>
          <button class="btn btn-ghost" @click="logout">退出</button>
        </div>
      </header>

      <nav class="admin-tabs">
        <button
          v-for="t in TABS"
          :key="t.key"
          :class="['admin-tab', { active: tab === t.key }]"
          @click="tab = t.key"
        >{{ t.label }}</button>
      </nav>

      <div v-if="error" class="banner error">{{ error }}</div>
      <div v-if="notice" class="banner success">{{ notice }}</div>
      <div v-if="loading" class="banner">加载中…</div>

      <!-- 概览 -->
      <section v-if="tab === 'overview'" class="admin-panel">
        <div class="stat-grid" v-if="stats">
          <div class="stat-card"><div class="stat-num">{{ stats.players }}</div><div class="stat-label">玩家总数</div></div>
          <div class="stat-card"><div class="stat-num">{{ stats.clans }}</div><div class="stat-label">部落数</div></div>
          <div class="stat-card"><div class="stat-num">{{ stats.exchanges }}</div><div class="stat-label">成功换卡</div></div>
          <div class="stat-card danger"><div class="stat-num">{{ stats.banned }}</div><div class="stat-label">已禁用</div></div>
          <div class="stat-card"><div class="stat-num">{{ stats.channel_wechat }}</div><div class="stat-label">微信区人数</div></div>
          <div class="stat-card"><div class="stat-num">{{ stats.channel_qq }}</div><div class="stat-label">QQ区人数</div></div>
        </div>

        <h3 class="panel-title">各渠道匹配状态（按「可被匹配」用户实时计算）</h3>
        <table class="admin-table" v-if="channelMatch">
          <thead>
            <tr><th>渠道</th><th>可匹配用户</th><th>有可匹配的用户</th><th>双向组合</th><th>单向组合</th><th>结论</th></tr>
          </thead>
          <tbody>
            <tr v-for="ch in ['wechat', 'qq']" :key="ch">
              <td>{{ CHANNEL_LABEL[ch] }}</td>
              <td>{{ channelMatch[ch].players }}</td>
              <td>{{ channelMatch[ch].withMatch }}</td>
              <td>{{ channelMatch[ch].twoWay }}</td>
              <td>{{ channelMatch[ch].oneWay }}</td>
              <td>
                <span :class="['badge', channelMatch[ch].withMatch > 0 ? 'ok' : 'muted']">
                  {{ channelMatch[ch].withMatch > 0 ? '有可匹配' : '暂无' }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <!-- 用户管理 -->
      <section v-if="tab === 'users'" class="admin-panel">
        <div class="toolbar">
          <input v-model="search" type="search" class="search-input" placeholder="🔍 搜索玩家名 / 标签 / 部落" />
          <span class="search-count">共 {{ players.length }} 人，显示 {{ filteredPlayers.length }} 人</span>
        </div>
        <div class="table-wrap">
          <table class="admin-table">
            <thead>
              <tr>
                <th>玩家</th><th>渠道</th><th>部落</th><th>已录卡</th><th>数据行</th>
                <th>最后登录</th><th>最后更新</th><th>状态</th><th>操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="p in filteredPlayers" :key="p.player_id">
                <td>
                  <div class="cell-main">{{ p.game_name }}</div>
                  <div class="cell-sub">{{ p.player_tag || '—' }}</div>
                </td>
                <td>{{ CHANNEL_LABEL[p.channel] || p.channel }}</td>
                <td>{{ p.clan_name || '—' }}</td>
                <td>{{ p.owned_cards }}</td>
                <td>{{ p.data_rows }}</td>
                <td>{{ fmt(p.last_login_at) }}</td>
                <td>{{ fmt(p.last_updated_at) }}</td>
                <td>
                  <span v-if="p.banned" class="badge danger">已禁用</span>
                  <span v-else class="badge ok">正常</span>
                  <span v-if="p.matchable === false" class="badge muted">不匹配</span>
                </td>
                <td class="cell-actions">
                  <button class="btn btn-sm" :disabled="busy" @click="toggleBanned(p)">
                    {{ p.banned ? '启用' : '禁用' }}
                  </button>
                  <button class="btn btn-sm btn-danger" :disabled="busy" @click="removePlayer(p)">删除</button>
                </td>
              </tr>
              <tr v-if="filteredPlayers.length === 0"><td colspan="9" class="empty">暂无数据</td></tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- 部落管理 -->
      <section v-if="tab === 'clans'" class="admin-panel">
        <div class="table-wrap">
          <table class="admin-table">
            <thead>
              <tr><th>部落名称</th><th>成员数</th><th>操作</th></tr>
            </thead>
            <tbody>
              <tr v-for="c in clans" :key="c.clan_id">
                <td>{{ c.name }}</td>
                <td>{{ c.member_count }}</td>
                <td class="cell-actions">
                  <button class="btn btn-sm btn-danger" :disabled="busy" @click="removeClan(c)">删除部落</button>
                </td>
              </tr>
              <tr v-if="clans.length === 0"><td colspan="3" class="empty">暂无数据</td></tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.admin-app { max-width: 1080px; margin: 0 auto; padding: 20px; }
.login-box { max-width: 380px; margin: 12vh auto 0; background: var(--card-bg); border: 1px solid var(--border); border-radius: 14px; padding: 26px 28px; box-shadow: 0 12px 30px rgba(0,0,0,0.35); }
.login-box h1 { margin: 0 0 4px; font-size: 22px; color: var(--gold); }
.login-box .hint { margin-top: 10px; font-size: 12px; color: var(--text-dim); line-height: 1.6; }
.admin-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; flex-wrap: wrap; }
.admin-title { font-weight: 700; font-size: 18px; color: var(--gold); }
.admin-head-right { display: flex; gap: 8px; }
.admin-tabs { display: flex; gap: 6px; margin-bottom: 16px; flex-wrap: wrap; }
.admin-tab { background: var(--bg-soft); border: 1px solid var(--border); border-radius: 8px; color: var(--text-dim); padding: 8px 16px; cursor: pointer; font-size: 14px; }
.admin-tab.active { background: var(--gold); color: #1a2230; font-weight: 700; border-color: var(--gold); }
.admin-panel { display: flex; flex-direction: column; gap: 14px; }
.panel-title { margin: 6px 0 0; font-size: 15px; color: var(--text); }
.stat-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(130px, 1fr)); gap: 12px; }
.stat-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 12px; padding: 16px; text-align: center; }
.stat-card.danger .stat-num { color: var(--red); }
.stat-num { font-size: 26px; font-weight: 700; color: var(--gold); }
.stat-label { font-size: 13px; color: var(--text-dim); margin-top: 4px; }
.toolbar { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.table-wrap { overflow-x: auto; }
.admin-table { width: 100%; border-collapse: collapse; font-size: 13px; background: var(--card-bg); border: 1px solid var(--border); border-radius: 10px; overflow: hidden; }
.admin-table th, .admin-table td { padding: 8px 10px; text-align: left; border-bottom: 1px solid var(--border); vertical-align: middle; }
.admin-table th { background: var(--bg-soft); color: var(--text-dim); font-weight: 600; white-space: nowrap; }
.admin-table tr:last-child td { border-bottom: none; }
.cell-main { font-weight: 600; }
.cell-sub { font-size: 12px; color: var(--text-dim); }
.cell-actions { white-space: nowrap; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 12px; margin-right: 4px; }
.badge.ok { background: rgba(76,208,125,0.12); color: var(--green); }
.badge.danger { background: rgba(239,106,106,0.12); color: var(--red); }
.badge.muted { background: var(--bg-soft); color: var(--text-dim); }
.empty { text-align: center; color: var(--text-dim); padding: 20px; }
.btn-sm { padding: 4px 10px; font-size: 12px; }
.btn-danger { border-color: var(--red); color: var(--red); background: rgba(239,106,106,0.08); }
.btn-danger:hover:not(:disabled) { background: rgba(239,106,106,0.18); }
</style>