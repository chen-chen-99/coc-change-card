<script setup>
import { ref, onMounted } from 'vue';
import { supabase } from './lib/supabase.js';
import { session, saveSession, loadSession, clearSession } from './lib/store.js';
import { isDemoMode, getCurrentActivity, getActivityCards, getMyInventory, getNotificationSettings } from './lib/api.js';
import LoginView from './views/LoginView.vue';
import MyCardsView from './views/MyCardsView.vue';
import TradeView from './views/TradeView.vue';
import CollectView from './views/CollectView.vue';
import NotificationSettingsModal from './components/NotificationSettingsModal.vue';

const activeTab = ref('cards');
const showNotify = ref(false);

async function loadGameData() {
  session.loading = true;
  session.error = null;
  try {
    const activity = await getCurrentActivity();
    session.activity = activity;
    if (!activity) {
      session.error = '暂无活动数据，请稍后再试或联系管理员。';
      return;
    }
    const cards = await getActivityCards(activity.activity_id);
    session.cards = cards;
    session.inventory = await getMyInventory(
      session.player.player_id,
      cards.map((c) => c.card_id)
    );
  } catch (e) {
    session.error = e.message;
  } finally {
    session.loading = false;
  }
}

async function refreshNotify() {
  session.player.notify = { email: null, enabled: false, scope: 'twoWay' };
  if (isDemoMode) return;
  try {
    const s = await getNotificationSettings(session.player.player_id);
    session.player.notify = { email: s.email, enabled: s.enabled, scope: s.scope };
  } catch {
    // 读取失败保持默认关闭，不影响使用
  }
}

async function restore() {
  if (isDemoMode) return; // 演示模式不做会话恢复
  const saved = loadSession();
  if (!saved?.user || !saved?.player) return;
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) {
    clearSession();
    return;
  }
  session.user = data.user;
  session.player = saved.player;
  session.activity = saved.activity ?? null;
  await loadGameData();
  await refreshNotify();
}

onMounted(restore);

async function onLoggedIn() {
  saveSession();
  activeTab.value = 'cards';
  await loadGameData();
  await refreshNotify();
}

function logout() {
  if (!isDemoMode) supabase.auth.signOut().catch(() => {});
  clearSession();
}
</script>

<template>
  <div class="app">
    <header v-if="session.player" class="topbar">
      <div class="brand">🏰 卡牌冲突换卡助手</div>
      <div class="session-info">
        <span class="who">{{ session.player.clan_name }} · {{ session.player.game_name }}</span>
        <span v-if="session.activity" class="activity-name">{{ session.activity.name }}</span>
        <button class="btn btn-notify" :class="{ on: session.player?.notify?.enabled }" @click="showNotify = true">
        {{ session.player?.notify?.enabled ? '🔔 通知开' : '🔕 通知关' }}
      </button>
      <button class="btn btn-ghost" @click="logout">退出</button>
      </div>
      <nav class="tabs">
        <button
          :class="['tab', { active: activeTab === 'cards' }]"
          @click="activeTab = 'cards'"
        >我的卡牌</button>
        <button
          :class="['tab', { active: activeTab === 'trade' }]"
          @click="activeTab = 'trade'"
        >换卡推荐</button>
        <button
          :class="['tab', { active: activeTab === 'collect' }]"
          @click="activeTab = 'collect'"
        >凑卡兑换</button>

      </nav>
    </header>

    <main class="container">
      <div v-if="isDemoMode" class="banner demo">
        🧪 当前为<b>演示模式</b>：未配置 Supabase，数据仅保存在内存中（刷新后重置）。
        配置 <code>.env</code> 后会自动切换到真实数据。
      </div>

      <div v-if="session.error" class="banner error">{{ session.error }}</div>
      <div v-if="session.loading" class="banner">加载中…</div>

      <LoginView v-if="!session.player" @logged-in="onLoggedIn" />
      <template v-else>
        <MyCardsView v-show="activeTab === 'cards'" />
        <!-- v-if：每次切入换卡页都重新挂载，自动重新拉取部落数据计算推荐 -->
        <TradeView v-if="activeTab === 'trade'" />
        
        <CollectView v-if="activeTab === 'collect'" />
      </template>
    </main>

        <NotificationSettingsModal
      v-if="showNotify"
      @close="showNotify = false"
      @saved="refreshNotify"
    />

    <footer class="footer">
      <div>仅供部落内部使用</div>
      <div class="disclaimer">
        此非官方作品，未获得Supercell认可。更多信息，请参阅
        <a href="https://supercell.com/en/fan-content-policy/cn/" target="_blank" rel="noopener noreferrer">Supercell 玩家内容条款</a>。
      </div>
    </footer>
  </div>
</template>