<template>
  <div class="prinotes-app-layout">
    <nav class="prinotes-nav">
      <AppNavigation />
    </nav>
    <main class="prinotes-main">
      <router-view v-slot="{ Component }">
        <transition name="fade" mode="out-in">
          <component :is="Component" />
        </transition>
      </router-view>
    </main>
  </div>
</template>

<script setup>
import { onMounted } from 'vue'
import AppNavigation from './components/AppNavigation.vue'
import { useNotesStore } from './stores/notes.js'

const store = useNotesStore()
onMounted(() => store.init())
</script>

<style lang="scss">
@import './styles/ui.scss';

.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.15s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
