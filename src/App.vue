<script setup>
import { ref, onMounted } from 'vue';
import { supabase } from './lib/supabase.js';
import { session, saveSession, loadSession, clearSession } from './lib/store.js';
import { isDemoMode, getCurrentActivity, getActivityCards, getMyInventory } from './lib/api.js';
import LoginView from './views/LoginView.vue';
import MyCardsView from './views/MyCardsView.vue';
import TradeView from './views/TradeView.vue';

const activeTab = ref('cards');

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
}

onMounted(restore);

function onLoggedIn() {
  saveSession();
  activeTab.value = 'cards';
  loadGameData();
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
      </template>
    </main>

    <footer class="footer">仅供部落内部使用</footer>
  </div>
</template>