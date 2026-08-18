<script setup>
import { ref, watch, onMounted } from 'vue';
import { session } from '../lib/store.js';
import { signInAnonymously, loginPlayer, getExchangeStats } from '../lib/api.js';
import GroupJoinModal from '../components/GroupJoinModal.vue';

const emit = defineEmits(['logged-in']);

// 记住上次输入（localStorage），部落默认填"城紫金"、渠道默认微信区
const DEFAULT_CLAN = '城紫金';
const DEFAULT_CHANNEL = 'wechat';
const CHANNELS = [
  { key: 'wechat', label: '💬 微信区' },
  { key: 'qq', label: '🐧 QQ区' },
];
const KEYS = {
  clan: 'card_clash_clan_name',
  player: 'card_clash_player_name',
  tag: 'card_clash_player_tag',
  channel: 'card_clash_channel',
};

const clanName = ref(localStorage.getItem(KEYS.clan) || DEFAULT_CLAN);
const playerName = ref(localStorage.getItem(KEYS.player) || '');
const playerTag = ref(localStorage.getItem(KEYS.tag) || '');
const savedChannel = localStorage.getItem(KEYS.channel);
const channel = ref(savedChannel === 'qq' || savedChannel === 'wechat' ? savedChannel : DEFAULT_CHANNEL);
watch([clanName, playerName, playerTag, channel], ([c, p, t, ch]) => {
  localStorage.setItem(KEYS.clan, c);
  localStorage.setItem(KEYS.player, p);
  localStorage.setItem(KEYS.tag, t);
  localStorage.setItem(KEYS.channel, ch);
});
const accessCode = ref('');
const stats = ref(null);

// 首次使用弹窗：提示先加对应渠道的群（记住已看过）
const GROUP_NOTICE_KEY = 'card_clash_group_notice_shown';
const showGroupModal = ref(false);
function closeGroupModal() {
  localStorage.setItem(GROUP_NOTICE_KEY, '1');
  showGroupModal.value = false;
}

onMounted(async () => {
  try {
    stats.value = await getExchangeStats();
  } catch {
    // 统计加载失败不影响登录
  }
  if (!localStorage.getItem(GROUP_NOTICE_KEY)) {
    showGroupModal.value = true;
  }
});
const submitting = ref(false);
const error = ref('');

async function submit() {
  error.value = '';
  if (!clanName.value.trim() || !playerName.value.trim()) {
    error.value = '请填写部落名称和玩家名称';
    return;
  }
  submitting.value = true;
  try {
    const user = await signInAnonymously();
    const player = await loginPlayer({
      clanName: clanName.value.trim(),
      playerName: playerName.value.trim(),
      playerTag: playerTag.value.trim(),
      accessCode: accessCode.value.trim(),
      channel: channel.value,
    });
    session.user = user;
    session.player = player;
    emit('logged-in');
  } catch (e) {
    error.value = e.message;
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <section class="login-card">
    <h1>🏰 卡牌冲突换卡助手</h1>
    <p class="subtitle">只需填写玩家名称，进入你的卡牌管理页</p>
    <p v-if="stats" class="stats-line">👥 已有 {{ stats.playerCount }} 位成员 · 🏆 累计成功换卡 {{ stats.exchangeCount }} 次</p>

    <button class="group-join-link" @click="showGroupModal = true">📢 使用前请先加入对应渠道的群</button>

    <form class="form" @submit.prevent="submit">
      <label class="field">
        <span>登录渠道（区服）</span>
        <div class="channel-seg">
          <button
            v-for="c in CHANNELS"
            :key="c.key"
            type="button"
            :class="['scope-btn', { active: channel === c.key }]"
            @click="channel = c.key"
          >{{ c.label }}</button>
        </div>
        <small class="field-hint">同渠道或同部落才能互相换卡。</small>
      </label>

      <label class="field">
        <span>部落名称</span>
        <input v-model.trim="clanName" placeholder="城紫金" required />
      </label>
      <label class="field">
        <span>部落冲突玩家名称</span>
        <input v-model.trim="playerName" placeholder="例如：小明" required />
      </label>
      <label class="field">
        <span>玩家标签（可选）</span>
        <input v-model.trim="playerTag" placeholder="例如：#ABC123" />
      </label>
      <label class="field">
        <span>访问码（可选，已设置时需填写）</span>
        <input v-model.trim="accessCode" type="password" placeholder="未设置访问码则留空" />
      </label>

      <p v-if="error" class="form-error">{{ error }}</p>

      <button class="btn btn-primary btn-block" type="submit" :disabled="submitting">
        {{ submitting ? '进入中…' : '进入' }}
      </button>
    </form>
  </section>

  <GroupJoinModal v-if="showGroupModal" @close="closeGroupModal" />
</template>