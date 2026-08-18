<script setup>
import { ref } from 'vue';

const qrErrors = ref({ qq: false, wechat: false });
// 用 BASE_URL 拼相对路径，兼容 GitHub Pages 子路径部署
const base = import.meta.env.BASE_URL;
const qrImg = (name) => base + 'images/qrcodes/' + name;
const GROUPS = [
  { key: 'qq', label: '🐧 QQ群', img: qrImg('qq-group.png') },
  { key: 'wechat', label: '💬 微信群', img: qrImg('wechat-group.png') },
];
function onError(key) {
  qrErrors.value[key] = true;
}
</script>

<template>
  <div class="group-join">
    <div class="group-join-title">📢 使用前请先加入对应渠道的群</div>
    <p class="group-join-hint">
      为了更方便大家互相换卡、及时沟通，请先加入你所在渠道的群：
      <b>微信区进微信群，QQ区进QQ群</b>。群里可以互相联系、约换卡时间。
    </p>
    <div class="group-qr-list">
      <div v-for="g in GROUPS" :key="g.key" class="group-qr-item">
        <div class="group-qr-label">{{ g.label }}</div>
        <img
          v-if="!qrErrors[g.key]"
          class="group-qr-img"
          :src="g.img"
          :alt="g.label"
          loading="lazy"
          @error="onError(g.key)"
        />
        <div v-else class="group-qr-fallback">二维码待上传，请联系开发者获取</div>
      </div>
    </div>
    <p class="group-join-save-hint">💡 长按（手机）或右键（电脑）二维码图片，可保存到本地后再扫码进群。</p>
  </div>
</template>