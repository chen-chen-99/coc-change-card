<script setup>
import { ref, onMounted } from 'vue';
import { session } from '../lib/store.js';
import { getClanTradingData, executeExchange } from '../lib/api.js';
import { buildRecommendations, groupByNeededCard } from '../lib/matching.js';
import { categoryLabel } from '../lib/categories.js';

const base = import.meta.env.BASE_URL;
const cardThumbSrc = (card) => base + (card.image_url || '').replace(/^\//, '');

const loading = ref(false);
const error = ref('');
const notice = ref('');
const busyKey = ref('');
const groups = ref([]);
const myMissingCount = ref(0);
const mySpareCount = ref(0);
const otherMemberCount = ref(0);
/** 匹配范围：'clan' 仅同部落 | 'all' 所有部落 */
const scope = ref('clan');

const cardIds = () => session.cards.map((c) => c.card_id);

/** 每个推荐条目的唯一标识，用于按钮忙碌态 */
const swapKeyOf = (rec) =>
  rec.type === 'twoWay'
    ? `${rec.partner.playerId}:${rec.iGive.card_id}:${rec.iGet.card_id}`
    : `oneway:${rec.partner.playerId}:${rec.iGet.card_id}`;

async function load() {
  loading.value = true;
  error.value = '';
  try {
    const { players, inventory } = await getClanTradingData(
      session.player.clan_id,
      cardIds(),
      scope.value
    );
    const me = players.find((p) => p.player_id === session.player.player_id);
    if (!me) throw new Error('未找到当前玩家数据');

    const recs = buildRecommendations({ me, clanMembers: players, cards: session.cards, inventory });
    groups.value = groupByNeededCard(recs);

    const myRows = inventory.filter((r) => r.player_id === me.player_id);
    const keep = me.keep_base ?? 1;
    let missing = 0;
    let spare = 0;
    for (const c of session.cards) {
      const q = myRows.find((r) => r.card_id === c.card_id)?.quantity ?? 0;
      if (q === 0) missing += 1;
      spare += Math.max(0, q - keep);
    }
    myMissingCount.value = missing;
    mySpareCount.value = spare;
    otherMemberCount.value = players.filter((p) => p.player_id !== me.player_id).length;
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

/**
 * 一键交换：双方在游戏中完成交换后，任一方点击即原子同步双方数据。
 * 服务端校验余量/同种类/防重复；返回后刷新推荐。
 */
async function onSwap(rec) {
  if (rec.type !== 'twoWay') return;
  if (!session.activity) {
    error.value = '暂无活动数据，无法交换';
    return;
  }
  const ok = window.confirm(
    `确认已在游戏中完成这组交换？\n\n` +
      `你 → ${rec.partner.gameName}：${rec.iGive.name}\n` +
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
      cardFromA: rec.iGive.card_id,
      cardFromB: rec.iGet.card_id,
    });
    if (res.status === 'already_done') {
      notice.value = '该交换已完成（可能对方已同步），已为你刷新最新数据。';
    } else {
      for (const row of res.updated || []) {
        if (row.player_id === session.player.player_id) session.inventory[row.card_id] = row.quantity;
      }
      notice.value = `✅ 交换已同步：你给出 ${rec.iGive.name}，获得 ${rec.iGet.name}。`;
    }
    await load();
  } catch (e) {
    error.value = e.message;
  } finally {
    busyKey.value = '';
  }
}

onMounted(load);
</script>

<template>
  <section>
    <div class="section-head">
      <h2>换卡推荐</h2>
      <button class="btn" :disabled="loading" @click="load">刷新</button>
    </div>

    <div class="scope-row">
      <span class="scope-label">匹配范围</span>
      <div class="scope-seg">
        <button
          :class="['scope-btn', { active: scope === 'clan' }]"
          @click="setScope('clan')"
        >🏠 仅同部落</button>
        <button
          :class="['scope-btn', { active: scope === 'all' }]"
          @click="setScope('all')"
        >🌍 所有部落</button>
      </div>
      <span v-if="scope === 'all'" class="scope-hint">已显示其他部落成员的部落名</span>
    </div>

    <div class="banner rule-hint">📌 规则：只有<b>同种类</b>的卡牌才能互相交换（圣水 / 暗黑重油 / 建筑大师基地 / 超级兵种）。</div>

    <div v-if="notice" class="banner success">{{ notice }}</div>

    <div class="stats-row">
      <div class="stat"><span class="stat-num">{{ myMissingCount }}</span> 张缺少</div>
      <div class="stat"><span class="stat-num">{{ mySpareCount }}</span> 张可提供</div>
      <div class="stat">
        <span class="stat-num">{{ otherMemberCount }}</span>
        {{ scope === 'all' ? '位可匹配玩家' : '位成员' }}
      </div>
    </div>

    <div v-if="loading" class="banner">正在计算匹配…</div>
    <div v-if="error" class="banner error">{{ error }}</div>

    <template v-else-if="!loading">
      <div v-if="myMissingCount === 0" class="banner success">🎉 你已经集齐全部卡牌，无需换卡！</div>

      <div v-else-if="groups.length === 0" class="banner">
        暂无可匹配的换卡对象。等待更多玩家录入卡牌数据后刷新查看。
      </div>

      <div v-for="g in groups" :key="g.card.card_id" class="rec-group">
        <div class="rec-group-title">
          <img
            v-if="g.card.image_url"
            class="rec-card-thumb"
            :src="cardThumbSrc(g.card)"
            :alt="g.card.name"
          />
          <span>{{ g.card.name }}</span>
          <span class="rec-category">{{ categoryLabel(g.card.category) }}</span>
          <span class="rec-group-count">{{ g.items.length }} 个匹配</span>
        </div>

        <div v-for="(rec, idx) in g.items" :key="idx" class="rec-item" :class="rec.type">
          <div class="rec-partner">
            <span v-if="scope === 'all' && rec.partner.clanName" class="partner-clan">{{ rec.partner.clanName }}</span>
            <span class="partner-name">{{ rec.partner.gameName }}</span>
            <span v-if="rec.partner.playerTag" class="partner-tag">{{ rec.partner.playerTag }}</span>
            <span class="partner-spare">拥有：{{ g.card.name }} × {{ rec.partner.spareQuantity }}</span>
          </div>

          <div class="rec-flow">
            <template v-if="rec.type === 'twoWay'">
              <div class="flow-line">你 → {{ rec.partner.gameName }}：{{ rec.iGive.name }}</div>
              <div class="flow-line">{{ rec.partner.gameName }} → 你：{{ rec.iGet.name }}</div>
            </template>
            <template v-else>
              <div class="flow-line">{{ rec.partner.gameName }} → 你：{{ rec.iGet.name }}</div>
            </template>
          </div>

          <div class="rec-badge" :class="rec.type">
            <template v-if="rec.type === 'twoWay'">★★★★★ 双向交换</template>
            <template v-else>单向 · 对方有你缺的卡</template>
          </div>

          <div class="rec-swap">
            <button
              v-if="rec.type === 'twoWay'"
              class="btn btn-swap"
              :disabled="busyKey === swapKeyOf(rec)"
              @click="onSwap(rec)"
            >{{ busyKey === swapKeyOf(rec) ? '同步中…' : '✅ 交换完成，同步数据' }}</button>
            <button
              v-else
              class="btn btn-swap btn-swap-disabled"
              disabled
              title="单向推荐没有约定换出卡，需双方约定后从双向推荐一键同步"
            >单向无法一键同步</button>
          </div>

          <div v-if="rec.partner.lastUpdatedAt" class="rec-meta">
            数据更新：{{ new Date(rec.partner.lastUpdatedAt).toLocaleString('zh-CN') }}
          </div>
        </div>
      </div>
    </template>
  </section>
</template>