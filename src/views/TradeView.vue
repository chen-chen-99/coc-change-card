<script setup>
import { ref, onMounted } from 'vue';
import { session } from '../lib/store.js';
import { getClanTradingData } from '../lib/api.js';
import { buildRecommendations, groupByNeededCard } from '../lib/matching.js';
import { categoryLabel } from '../lib/categories.js';

const base = import.meta.env.BASE_URL;
const cardThumbSrc = (card) => base + (card.image_url || '').replace(/^\//, '');

const loading = ref(false);
const error = ref('');
const groups = ref([]);
const myMissingCount = ref(0);
const mySpareCount = ref(0);
const otherMemberCount = ref(0);

const cardIds = () => session.cards.map((c) => c.card_id);

async function load() {
  loading.value = true;
  error.value = '';
  try {
    const { players, inventory } = await getClanTradingData(session.player.clan_id, cardIds());
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

onMounted(load);
</script>

<template>
  <section>
    <div class="section-head">
      <h2>换卡推荐</h2>
      <button class="btn" :disabled="loading" @click="load">刷新</button>
    </div>

    <div class="banner rule-hint">📌 规则：只有<b>同种类</b>的卡牌才能互相交换（圣水 / 暗黑重油 / 建筑大师基地 / 超级兵种）。</div>

    <div class="stats-row">
      <div class="stat"><span class="stat-num">{{ myMissingCount }}</span> 张缺少</div>
      <div class="stat"><span class="stat-num">{{ mySpareCount }}</span> 张可提供</div>
      <div class="stat"><span class="stat-num">{{ otherMemberCount }}</span> 位成员</div>
    </div>

    <div v-if="loading" class="banner">正在计算匹配…</div>
    <div v-if="error" class="banner error">{{ error }}</div>

    <template v-else-if="!loading">
      <div v-if="myMissingCount === 0" class="banner success">🎉 你已经集齐全部卡牌，无需换卡！</div>

      <div v-else-if="groups.length === 0" class="banner">
        暂无可匹配的换卡对象。等待更多部落成员录入卡牌数据后刷新查看。
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
          <div v-if="rec.partner.lastUpdatedAt" class="rec-meta">
            数据更新：{{ new Date(rec.partner.lastUpdatedAt).toLocaleString('zh-CN') }}
          </div>
        </div>
      </div>
    </template>
  </section>
</template>