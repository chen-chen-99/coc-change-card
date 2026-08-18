<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { session } from '../lib/store.js';
import { getClanTradingData, executeExchange } from '../lib/api.js';
import { buildCollectRecommendations } from '../lib/matching.js';
import { CATEGORIES, categoryLabel } from '../lib/categories.js';

const base = import.meta.env.BASE_URL;
const cardThumbSrc = (card) => base + (card.image_url || '').replace(/^\//, '');

const loading = ref(false);
const error = ref('');
const notice = ref('');
const busyKey = ref('');
/** 匹配范围：'clan' 仅同部落 | 'channel' 同渠道（区服） */
const scope = ref('channel');
const targetCardId = ref('');
const targetCount = ref(3);
const recs = ref([]);
const need = ref(0);
const currentQty = ref(0);
/** 单向/凑卡交换中，我选择给出的多余卡（key -> card_id） */
const selectedGive = ref({});

const targetCard = computed(() => session.cards.find((c) => c.card_id === targetCardId.value) || null);

/** 按种类分组的卡牌选项 */
const cardGroups = computed(() => {
  const groups = {};
  for (const c of session.cards) {
    if (!groups[c.category]) groups[c.category] = [];
    groups[c.category].push(c);
  }
  return groups;
});

const cardIds = () => session.cards.map((c) => c.card_id);
const swapKeyOf = (rec) => `${rec.partner.playerId}:${rec.iGet.card_id}`;

/** 当前选择的「我给对方的卡」名称 */
function giveName(rec) {
  const id = selectedGive.value[swapKeyOf(rec)];
  return session.cards.find((c) => c.card_id === id)?.name ?? '（请选择）';
}

async function load() {
  if (!targetCard.value) {
    recs.value = [];
    need.value = 0;
    return;
  }
  loading.value = true;
  error.value = '';
  try {
    const { players, inventory } = await getClanTradingData(
      session.player.clan_id,
      cardIds(),
      scope.value,
      session.player.channel ?? 'wechat'
    );
    const me = players.find((p) => p.player_id === session.player.player_id);
    if (!me) throw new Error('未找到当前玩家数据');

    const res = buildCollectRecommendations({
      me,
      clanMembers: players,
      cards: session.cards,
      inventory,
      targetCard: targetCard.value,
      targetCount: targetCount.value,
    });
    need.value = res.need;
    recs.value = res.recs;
    const myRow = inventory.find((r) => r.player_id === me.player_id && r.card_id === targetCardId.value);
    currentQty.value = myRow?.quantity ?? 0;

    // 默认选择：双向优先给「对方缺的卡」，否则第一张
    for (const rec of res.recs) {
      const key = swapKeyOf(rec);
      if (!selectedGive.value[key]) {
        const prefer = rec.preferredGive ?? rec.mySpareOptions[0]?.card_id;
        if (prefer) selectedGive.value[key] = prefer;
      }
    }
  } catch (e) {
    error.value = e.message;
  } finally {
    loading.value = false;
  }
}

function setScope(s) {
  if (scope.value === s) return;
  scope.value = s;
  notice.value = '';
  load();
}

watch([targetCardId, targetCount, scope], load);
onMounted(load);

async function onSwap(rec) {
  if (!session.activity) {
    error.value = '暂无活动数据，无法交换';
    return;
  }
  const giveCardId = selectedGive.value[swapKeyOf(rec)];
  if (!giveCardId) {
    error.value = '请先选择你要给出的多余卡';
    return;
  }
  const giveName = session.cards.find((c) => c.card_id === giveCardId)?.name ?? '';

  const ok = window.confirm(
    `确认已在游戏中完成这组交换？\n\n` +
      `你 → ${rec.partner.gameName}：${giveName}\n` +
      `${rec.partner.gameName} → 你：${rec.iGet.name}\n\n` +
      `点击后将自动同步双方卡牌数据。`
  );
  if (!ok) return;

  busyKey.value = swapKeyOf(rec);
  notice.value = '';
  error.value = '';
  try {
    const res = await executeExchange({
      activityId: session.activity.activity_id,
      playerA: session.player.player_id,
      playerB: rec.partner.playerId,
      cardFromA: giveCardId,
      cardFromB: rec.iGet.card_id,
    });
    if (res.status === 'already_done') {
      notice.value = '该交换已完成（可能对方已同步），已为你刷新最新数据。';
    } else {
      for (const row of res.updated || []) {
        if (row.player_id === session.player.player_id) session.inventory[row.card_id] = row.quantity;
      }
      notice.value = `✅ 交换已同步：你给出 ${giveName}，获得 ${rec.iGet.name}。`;
    }
    await load();
  } catch (e) {
    error.value = e.message;
  } finally {
    busyKey.value = '';
  }
}
</script>

<template>
  <section>
    <div class="section-head">
      <h2>凑卡兑换</h2>
      <button class="btn" :disabled="loading" @click="load">刷新</button>
    </div>

    <div class="banner rule-hint">
      🎯 先凑齐目标张数，再用多余的卡去游戏内兑换任意卡；优先推荐<b>对方也缺你能给的卡</b>的组合。
    </div>

    <div class="scope-row">
      <span class="scope-label">匹配范围</span>
      <div class="scope-seg">
        <button
          :class="['scope-btn', { active: scope === 'clan' }]"
          @click="setScope('clan')"
        >🏠 仅同部落</button>
        <button
          :class="['scope-btn', { active: scope === 'channel' }]"
          @click="setScope('channel')"
        >🔗 同渠道</button>
      </div>
      <span v-if="scope === 'channel'" class="scope-hint">同渠道内可跨部落匹配</span>
    </div>

    <div class="collect-pick">
      <label class="field">
        <span>选择想凑的卡牌</span>
        <select v-model="targetCardId" class="give-pick-select collect-select">
          <option value="" disabled>—— 请选择一张卡牌 ——</option>
          <optgroup v-for="cat in CATEGORIES" :key="cat.key" :label="cat.label">
            <option v-for="c in cardGroups[cat.key] || []" :key="c.card_id" :value="c.card_id">
              {{ c.card_id }} {{ c.name }}
            </option>
          </optgroup>
        </select>
      </label>
      <label class="field">
        <span>目标张数</span>
        <div class="scope-seg">
          <button
            v-for="n in [3, 4, 5]"
            :key="n"
            type="button"
            :class="['scope-btn', { active: targetCount === n }]"
            @click="targetCount = n"
          >{{ n }} 张</button>
        </div>
      </label>
    </div>

    <div v-if="notice" class="banner success">{{ notice }}</div>
    <div v-if="error" class="banner error">{{ error }}</div>
    <div v-if="loading" class="banner">正在计算匹配…</div>

    <template v-if="targetCard && !loading">
      <div class="collect-progress">
        <img v-if="targetCard.image_url" class="rec-card-thumb" :src="cardThumbSrc(targetCard)" :alt="targetCard.name" />
        <div class="collect-progress-info">
          <div class="collect-progress-title">{{ targetCard.name }} <span class="rec-category">{{ categoryLabel(targetCard.category) }}</span></div>
          <div class="collect-progress-bar">
            <span class="collect-progress-text">当前 {{ currentQty }} / {{ targetCount }} 张</span>
            <div class="progress-track">
              <div class="progress-fill" :style="{ width: Math.min(100, (currentQty / targetCount) * 100) + '%' }"></div>
            </div>
          </div>
          <div v-if="need > 0" class="collect-progress-hint">还差 <b>{{ need }}</b> 张，就能用 {{ Math.max(0, targetCount - 1) }} 张多余卡去兑换任意卡了</div>
          <div v-else class="collect-progress-done">🎉 已达到 {{ targetCount }} 张，可以去兑换了！</div>
        </div>
      </div>

      <div v-if="need <= 0" class="banner success">🎉 已达目标张数，无需再换！</div>
      <div v-else-if="recs.length === 0" class="banner">
        <template v-if="targetCard && !recs.length && need > 0">
          暂无可匹配对象：需对方<b>缺少你能给的同种类卡</b>才能换。可先去「我的卡牌」攒卡后刷新。
        </template>
      </div>

      <div v-for="rec in recs" :key="swapKeyOf(rec)" class="rec-item" :class="rec.type">
        <div class="rec-partner">
          <span v-if="scope === 'channel' && rec.partner.clanName" class="partner-clan">{{ rec.partner.clanName }}</span>
          <span class="partner-name">{{ rec.partner.gameName }}</span>
          <span v-if="rec.partner.playerTag" class="partner-tag">{{ rec.partner.playerTag }}</span>
          <span class="partner-spare">拥有：{{ rec.iGet.name }} × {{ rec.partner.spareQuantity }}</span>
        </div>

        <div class="rec-flow">
          <div class="flow-line">你 → {{ rec.partner.gameName }}：{{ giveName(rec) }}</div>
          <div class="flow-line">{{ rec.partner.gameName }} → 你：{{ rec.iGet.name }}</div>
        </div>

        <div class="rec-badge twoWay">★★★★★ 双向优先（对方缺你能给的卡）</div>

        <div class="rec-give-pick">
          <span class="give-pick-label">你给（对方缺少、你多余的卡）：</span>
          <select v-model="selectedGive[swapKeyOf(rec)]" class="give-pick-select">
            <option v-for="opt in rec.mySpareOptions" :key="opt.card_id" :value="opt.card_id">
              {{ opt.name }} × {{ opt.spare }}
            </option>
          </select>
        </div>

        <div class="rec-swap">
          <button
            class="btn btn-swap"
            :disabled="busyKey === swapKeyOf(rec)"
            @click="onSwap(rec)"
          >{{ busyKey === swapKeyOf(rec) ? '同步中…' : '✅ 交换完成，同步数据' }}</button>
        </div>

        <div v-if="rec.partner.lastUpdatedAt" class="rec-meta">
          数据更新：{{ new Date(rec.partner.lastUpdatedAt).toLocaleString('zh-CN') }}
        </div>
      </div>
    </template>
  </section>
</template>