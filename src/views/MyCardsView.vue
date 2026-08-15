<script setup>
import { ref, computed } from 'vue';
import { session } from '../lib/store.js';
import { updateQuantity, setAccessCode } from '../lib/api.js';
import { CATEGORIES } from '../lib/categories.js';
import CardItem from '../components/CardItem.vue';

const categoryFilter = ref('all');
const searchQuery = ref('');

const editable = computed(() => session.player?.editable !== false);
const keepBase = computed(() => session.player?.keep_base ?? 1);
const hasCode = computed(() => session.player?.access_code_set === true);

const cardsWithQty = computed(() => {
  const q = searchQuery.value.trim().toLowerCase();
  return session.cards
    .filter((c) => categoryFilter.value === 'all' || c.category === categoryFilter.value)
    .filter((c) => !q || c.name.toLowerCase().includes(q) || c.card_id.toLowerCase().includes(q))
    .map((card) => ({ card, quantity: session.inventory[card.card_id] ?? 0 }));
});

const stats = computed(() => {
  let owned = 0;
  let missing = 0;
  for (const c of session.cards) {
    if ((session.inventory[c.card_id] ?? 0) > 0) owned += 1;
    else missing += 1;
  }
  return { owned, missing, total: session.cards.length };
});

async function changeDelta(cardId, delta) {
  const prev = session.inventory[cardId] ?? 0;
  const next = Math.max(0, prev + delta);
  if (next === prev) return;
  session.inventory[cardId] = next;
  session.error = null;
  try {
    await updateQuantity(session.player.player_id, cardId, next);
  } catch (e) {
    session.inventory[cardId] = prev;
    session.error = e.message;
  }
}

async function onSetCode() {
  const code = window.prompt(
    hasCode.value ? '输入新的访问码（留空并确定 = 清除访问码）' : '设置访问码（留空 = 不设置）',
    ''
  );
  if (code === null) return; // 用户取消
  session.error = null;
  try {
    const res = await setAccessCode(session.player.player_id, code.trim());
    session.player.access_code_set = res.access_code_set;
  } catch (e) {
    session.error = e.message;
  }
}
</script>

<template>
  <section>
    <div class="section-head">
      <h2>我的卡牌</h2>
      <div class="progress">
        已收集 <strong>{{ stats.owned }}</strong> / {{ stats.total }}
        <span v-if="stats.missing === 0" class="complete">🎉 全部集齐！</span>
      </div>
    </div>

    <div v-if="!editable" class="banner">
      🔒 该玩家已设置访问码并绑定其他设备，当前为<b>只读</b>。
      如你是本人，请在<b>登录页</b>的"访问码"框输入正确访问码即可接管编辑权。
    </div>

    <div v-else class="access-row">
      <span class="access-status" :class="{ locked: hasCode }">
        {{ hasCode ? '🔒 已设置访问码：其他设备需输入访问码才能修改' : '🔓 未设置访问码：任何设备都能登录修改' }}
      </span>
      <button class="btn" @click="onSetCode">
        {{ hasCode ? '修改访问码' : '设置访问码' }}
      </button>
    </div>

    <div class="search-row">
      <input
        v-model="searchQuery"
        type="search"
        class="search-input"
        placeholder="🔍 搜索兵种名称或编号，如：野蛮人 / 皮卡 / e01"
      />
      <span v-if="searchQuery.trim()" class="search-count">找到 {{ cardsWithQty.length }} 张</span>
    </div>

    <div class="category-chips">
      <button
        :class="['chip', { active: categoryFilter === 'all' }]"
        @click="categoryFilter = 'all'"
      >全部</button>
      <button
        v-for="c in CATEGORIES"
        :key="c.key"
        :class="['chip', { active: categoryFilter === c.key }]"
        @click="categoryFilter = c.key"
      >{{ c.label }}</button>
    </div>

    <div v-if="searchQuery.trim() && cardsWithQty.length === 0" class="banner">
      没有找到匹配的兵种，换个关键词试试。
    </div>

    <div class="card-grid">
      <CardItem
        v-for="item in cardsWithQty"
        :key="item.card.card_id"
        :card="item.card"
        :quantity="item.quantity"
        :editable="editable"
        :keep-base="keepBase"
        @change="changeDelta"
      />
    </div>
  </section>
</template>