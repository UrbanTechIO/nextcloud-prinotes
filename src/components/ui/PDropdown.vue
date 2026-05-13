<template>
  <div class="p-dropdown" ref="root">
    <button class="btn p-dropdown-trigger" @click.stop="toggle" aria-label="More actions">
      <DotsVertical :size="18" />
    </button>
    <Teleport to="body">
      <div v-if="open" class="p-dropdown-menu" :style="menuStyle" @click="close">
        <slot />
      </div>
    </Teleport>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import DotsVertical from 'vue-material-design-icons/DotsVertical.vue'

const open = ref(false)
const root = ref(null)
const menuStyle = ref({})

function toggle() {
  if (!open.value && root.value) {
    const rect = root.value.getBoundingClientRect()
    menuStyle.value = {
      position: 'fixed',
      top: (rect.bottom + 4) + 'px',
      right: (window.innerWidth - rect.right) + 'px',
      zIndex: 9999,
    }
  }
  open.value = !open.value
}

function close() { open.value = false }

function onOutside(e) {
  if (root.value && !root.value.contains(e.target)) close()
}

onMounted(() => document.addEventListener('click', onOutside))
onUnmounted(() => document.removeEventListener('click', onOutside))
</script>

<style lang="scss">
.p-dropdown {
  position: relative;
  display: inline-flex;
}

.p-dropdown-trigger {
  padding: 4px 6px !important;
}

.p-dropdown-menu {
  background: var(--color-main-background);
  border: 1px solid var(--color-border);
  border-radius: var(--border-radius-large, 8px);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.18);
  min-width: 180px;
  padding: 4px 0;
  overflow: hidden;
}

.p-dropdown-item {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  padding: 9px 16px;
  background: none;
  border: none;
  text-align: left;
  font-size: 0.9rem;
  cursor: pointer;
  color: var(--color-main-text);
  white-space: nowrap;

  &:hover { background: var(--color-background-hover); }
  &.danger { color: var(--color-error); }
}
</style>
