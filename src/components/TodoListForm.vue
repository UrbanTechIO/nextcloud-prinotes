<template>
  <div class="tl-form">
    <div class="form-field">
      <label>{{ parentId ? 'Sub-category name' : 'Category name' }}</label>
      <input v-model="form.title" class="p-input" placeholder="e.g. Home Assistant" @keydown.enter="save" />
    </div>
    <div v-if="!list && !parentId" class="form-field">
      <label>Parent (optional)</label>
      <select v-model="form.parentId" class="p-input">
        <option :value="null">None (top level)</option>
        <option v-for="l in parents" :key="l.id" :value="l.id">{{ l.title }}</option>
      </select>
    </div>
    <div class="form-row">
      <label>Color</label>
      <div class="color-swatches">
        <div v-for="c in colors" :key="c" class="swatch" :class="{ selected: form.color === c }"
          :style="{ background: c }" @click="form.color = c" />
        <div class="swatch clear" @click="form.color = null">✕</div>
      </div>
    </div>
    <p v-if="error" class="form-error">{{ error }}</p>
    <div class="form-actions">
      <button v-if="list && !list.isSystem" class="btn btn-error" @click="remove">Delete</button>
      <span class="spacer" />
      <button class="btn" @click="$emit('cancel')">Cancel</button>
      <button class="btn btn-primary" :disabled="!form.title.trim()" @click="save">{{ list ? 'Update' : 'Create' }}</button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useTodosStore } from '../stores/todos.js'

const props = defineProps({
  list: { type: Object, default: null },
  parentId: { type: Number, default: null },
})
const emit = defineEmits(['saved', 'cancel'])
const store = useTodosStore()

const colors = ['#ef4444', '#f97316', '#eab308', '#22c55e', '#0082c9', '#8b5cf6', '#ec4899', '#6b7280']
const form = ref({
  title: props.list?.title ?? '',
  color: props.list?.color ?? null,
  parentId: props.list?.parentId ?? props.parentId ?? null,
})
const error = ref('')
// Only top-level, non-Inbox lists can be parents (one level of nesting).
const parents = computed(() => store.lists.filter(l => !l.parentId && !l.isSystem))

async function save() {
  if (!form.value.title.trim()) return
  error.value = ''
  try {
    if (props.list) {
      const patch = { color: form.value.color }
      if (!props.list.isSystem) patch.title = form.value.title
      await store.updateList(props.list.id, patch)
    } else {
      await store.addList({ title: form.value.title, color: form.value.color, parentId: form.value.parentId })
    }
    emit('saved')
  } catch (e) {
    error.value = e.response?.data?.ocs?.meta?.message ?? e.message
  }
}

async function remove() {
  const n = store.taskCountInList(props.list.id)
  const sub = store.lists.filter(l => l.parentId === props.list.id).length
  const msg = `Delete "${props.list.title}"${sub ? ` and its ${sub} sub-categor${sub === 1 ? 'y' : 'ies'}` : ''}? This also deletes ${n} task${n === 1 ? '' : 's'}.`
  if (!window.confirm(msg)) return
  await store.deleteList(props.list.id)
  emit('saved')
}
</script>

<style lang="scss" scoped>
.tl-form { display: flex; flex-direction: column; gap: 12px; min-width: 300px; }
.form-field { display: flex; flex-direction: column; gap: 4px; label { font-size: 0.88rem; } }
.form-row { display: flex; align-items: center; gap: 12px; label { min-width: 60px; font-size: 0.88rem; } }
.color-swatches { display: flex; gap: 6px; }
.swatch {
  width: 26px; height: 26px; border-radius: 50%; cursor: pointer; border: 2px solid transparent;
  &.selected { border-color: var(--color-main-text); }
  &.clear { background: var(--color-border); display: flex; align-items: center; justify-content: center; font-size: 0.75rem; }
}
.form-actions { display: flex; gap: 8px; align-items: center; margin-top: 4px; }
.spacer { flex: 1; }
.form-error { color: var(--color-error, #e9322d); margin: 0; font-size: 0.85rem; }
</style>
