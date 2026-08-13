<script setup>
import { ref, computed } from 'vue';
import { computeCardView } from '../lib/matching.js';
import { categoryShort } from '../lib/categories.js';

const props = defineProps({
  card: { type: Object, required: true },
  quantity: { type: Number, default: 0 },
  editable: { type: Boolean, default: false },
  keepBase: { type: Number, default: 1 },
});
const emit = defineEmits(['change']);

const imgFailed = ref(false);
const base = import.meta.env.BASE_URL;

const imageSrc = computed(() => {
  const url = props.card.image_url || `images/cards/${props.card.card_id}.png`;
  return base + url.replace(/^\//, '');
});

const view = computed(() => computeCardView(props.quantity, props.keepBase));
const catShort = computed(() => categoryShort(props.card.category));
</script>

<template>
  <div class="card-item" :class="{ missing: view.missing }">
    <div class="card-image">
      <img v-if="!imgFailed" :src="imageSrc" :alt="card.name" loading="lazy" @error="imgFailed = true" />
      <div v-else class="card-fallback">{{ card.name }}</div>
    </div>

    <div class="card-name" :title="catShort">{{ card.name }}</div>

    <div class="card-qty">
      <button
        class="btn btn-qty"
        :disabled="!editable || view.quantity === 0"
        @click="emit('change', card.card_id, -1)"
      >−</button>
      <span class="qty-num">{{ view.quantity }}</span>
      <button
        class="btn btn-qty"
        :disabled="!editable"
        @click="emit('change', card.card_id, 1)"
      >＋</button>
    </div>

    <div class="card-tags">
      <span class="tag tag-category">{{ catShort }}</span>
      <span v-if="view.missing" class="tag tag-missing">缺少</span>
      <span v-else class="tag tag-owned">已收集</span>
      <span v-if="view.hasSpare" class="tag tag-spare">多余 {{ view.spare }} 张</span>
    </div>
  </div>
</template>