<script setup>
import { ref, watch } from 'vue';
import { session } from '../lib/store.js';
import { signInAnonymously, loginPlayer } from '../lib/api.js';

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
        <small class="field-hint">同部落或同渠道（区服）的玩家才能互相换卡；此处仅影响换卡匹配，不影响账号识别。</small>
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
        <span>玩家标签（可选，推荐填写，用于区分同名玩家）</span>
        <input v-model.trim="playerTag" placeholder="例如：#ABC123" />
      </label>
      <label class="field">
        <span>访问码（可选）— 仅当该玩家已设置访问码且你非绑定设备时需要填写，填对即可接管编辑权</span>
        <input v-model.trim="accessCode" type="password" placeholder="未设置访问码则留空" />
      </label>

      <p v-if="error" class="form-error">{{ error }}</p>

      <button class="btn btn-primary btn-block" type="submit" :disabled="submitting">
        {{ submitting ? '进入中…' : '进入' }}
      </button>
      <p class="hint">首次进入将自动创建你的玩家档案并初始化卡牌库存。</p>
    </form>
  </section>
</template>