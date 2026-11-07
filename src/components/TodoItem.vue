<template>
  <div class="todo-row" :class="{ done: todo.isDone, selected }" @click="$emit('open', todo.id)">
    <button class="todo-check" :class="{ checked: todo.isDone }" :title="todo.isDone ? 'Mark as not done' : 'Mark as done'"
      @click.stop="$emit('toggle', todo.id)">
      <span v-if="todo.isDone">✓</span>
    </button>
    <div class="todo-main">
      <div class="todo-title">{{ todo.title }}</div>
      <div class="todo-meta">
        <span v-if="showPath && path">{{ path }}</span>
        <span v-if="todo.isDone && todo.doneAt">Done {{ doneText }}</span>
        <span v-if="todo.dueDate" :class="{ overdue: overdue }">📅 {{ dueText }}</span>
        <span v-if="todo.remindAt && !todo.isDone">⏰ {{ remindText }}</span>
        <span v-if="todo.repeatRule">🔁 {{ todo.repeatRule }}</span>
        <span v-if="todo.steps.length">☑ {{ stepsDone }}/{{ todo.steps.length }}</span>
        <span v-if="todo.note">📝</span>
      </div>
    </div>
    <button class="todo-star" :class="{ on: todo.isImportant }" title="Important"
      @click.stop="$emit('star', todo.id)">{{ todo.isImportant ? '★' : '☆' }}</button>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { localDateString } from '../stores/todos.js'

const props = defineProps({
  todo: { type: Object, required: true },
  path: { type: String, default: '' },
  showPath: { type: Boolean, default: false },
  selected: { type: Boolean, default: false },
})
defineEmits(['toggle', 'open', 'star'])

const today = computed(() => localDateString())
const overdue = computed(() => !props.todo.isDone && props.todo.dueDate && props.todo.dueDate < today.value)
const stepsDone = computed(() => props.todo.steps.filter(s => s.done).length)

const dueText = computed(() => {
  const d = props.todo.dueDate
  if (d === today.value) return 'Today'
  const t = new Date(); t.setDate(t.getDate() + 1)
  if (d === localDateString(t)) return 'Tomorrow'
  const y = new Date(); y.setDate(y.getDate() - 1)
  if (d === localDateString(y)) return 'Yesterday'
  return new Date(d + 'T00:00:00').toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' })
})
const remindText = computed(() =>
  new Date(props.todo.remindAt * 1000).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }))
const doneText = computed(() =>
  new Date(props.todo.doneAt * 1000).toLocaleString(undefined, { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }))
</script>

<style lang="scss" scoped>
.todo-row {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 14px;
  margin-top: 8px;
  border: 1px solid var(--color-border);
  border-radius: 12px;
  background: var(--color-main-background);
  cursor: pointer;
  transition: box-shadow 0.2s, border-color 0.15s;

  &:hover { box-shadow: 0 4px 14px rgba(0,0,0,.12); }
  &.selected { border-color: var(--color-primary-element); }
  &.done { opacity: 0.6; .todo-title { text-decoration: line-through; } }
}

.todo-check {
  width: 20px;
  height: 20px;
  /* Nextcloud gives every button a ~44px min size, which stretched the circle into an oval. */
  min-width: 20px;
  min-height: 20px;
  max-width: 20px;
  max-height: 20px;
  box-sizing: border-box;
  flex-shrink: 0;
  border-radius: 50%;
  border: 2px solid var(--color-text-lighter);
  background: transparent;
  color: #fff;
  font-size: 12px;
  line-height: 1;
  padding: 0;
  cursor: pointer;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  &:hover { border-color: var(--color-primary-element); }
  &.checked { background: var(--color-primary-element); border-color: var(--color-primary-element); }
}

.todo-main { flex: 1; min-width: 0; }
.todo-title { font-size: 0.95rem; word-break: break-word; }
.todo-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 12px;
  margin-top: 2px;
  font-size: 0.75rem;
  color: var(--color-text-lighter);
  .overdue { color: var(--color-error, #e9322d); }
}

.todo-star {
  min-width: 0;
  min-height: 0;
  padding: 4px;
  background: none;
  border: none;
  font-size: 1.15rem;
  cursor: pointer;
  color: var(--color-text-lighter);
  &.on { color: #f59e0b; }
}
</style>
