<template>
  <aside v-if="todo" class="todo-detail">
    <div class="detail-head">
      <span class="detail-path">{{ store.listPath(todo.listId) }}</span>
      <button class="btn btn-icon" title="Close" @click="$emit('close')">✕</button>
    </div>

    <div class="title-line">
      <button class="check" :class="{ checked: todo.isDone }" @click="store.toggleDone(todo.id)">
        <span v-if="todo.isDone">✓</span>
      </button>
      <input v-model="title" class="title-input" placeholder="Task title" @blur="saveTitle" @keydown.enter="$event.target.blur()" />
      <button class="star" :class="{ on: todo.isImportant }" title="Important"
        @click="store.updateTodo(todo.id, { isImportant: !todo.isImportant })">{{ todo.isImportant ? '★' : '☆' }}</button>
    </div>

    <div class="block">
      <div v-for="s in todo.steps" :key="s.id" class="step">
        <button class="check small" :class="{ checked: s.done }" @click="toggleStep(s.id)"><span v-if="s.done">✓</span></button>
        <input class="step-input" :class="{ done: s.done }" :value="s.text" @change="renameStep(s.id, $event.target.value)" />
        <button class="x" title="Remove step" @click="removeStep(s.id)">✕</button>
      </div>
      <input v-model="newStep" class="step-add" placeholder="+ Add step" @keydown.enter="addStep" />
    </div>

    <div class="block fields">
      <label>📅 Due
        <input type="date" class="p-input" :value="todo.dueDate || ''" @change="setDue($event.target.value)" />
      </label>
      <label>⏰ Remind me
        <input type="datetime-local" class="p-input" :value="remindLocal" @change="setRemind($event.target.value)" />
      </label>
      <label>🔁 Repeat
        <select class="p-input" :value="todo.repeatRule || ''" @change="setRepeat($event.target.value)">
          <option value="">Does not repeat</option>
          <option value="daily">Daily</option>
          <option value="weekdays">Weekdays</option>
          <option value="weekly">Weekly</option>
          <option value="monthly">Monthly</option>
          <option value="yearly">Yearly</option>
        </select>
      </label>
      <label>📁 Category
        <select class="p-input" :value="todo.listId" @change="store.updateTodo(todo.id, { listId: Number($event.target.value) })">
          <option v-for="l in store.lists" :key="l.id" :value="l.id">{{ store.listPath(l.id) }}</option>
        </select>
      </label>
    </div>

    <div class="block">
      <label class="note-label">📝 Note</label>
      <textarea v-model="note" class="p-input note" rows="4" placeholder="Add a note…" @blur="saveNote" />
    </div>

    <div class="detail-foot">
      <button class="btn btn-error" @click="remove">Delete task</button>
    </div>
  </aside>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import { useTodosStore } from '../stores/todos.js'

const props = defineProps({ todoId: { type: Number, default: null } })
const emit = defineEmits(['close'])
const store = useTodosStore()

const todo = computed(() => store.todos.find(t => t.id === props.todoId) ?? null)
const title = ref('')
const note = ref('')
const newStep = ref('')

watch(todo, (t, old) => {
  if (!t) return
  if (!old || old.id !== t.id) { title.value = t.title; note.value = t.note ?? '' }
}, { immediate: true })

const remindLocal = computed(() => {
  const r = todo.value?.remindAt
  if (!r) return ''
  const d = new Date(r * 1000)
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
})

function saveTitle() {
  const v = title.value.trim()
  if (!v) { title.value = todo.value.title; return }
  if (v !== todo.value.title) store.updateTodo(todo.value.id, { title: v })
}
function saveNote() {
  if ((note.value || '') !== (todo.value.note || '')) store.updateTodo(todo.value.id, { note: note.value || null })
}
function setDue(v) { store.updateTodo(todo.value.id, { dueDate: v || null }) }
function setRemind(v) {
  store.updateTodo(todo.value.id, { remindAt: v ? Math.floor(new Date(v).getTime() / 1000) : null })
}
function setRepeat(v) { store.updateTodo(todo.value.id, { repeatRule: v || null }) }

function pushSteps(steps) { store.updateTodo(todo.value.id, { steps }) }
function addStep() {
  const text = newStep.value.trim()
  if (!text) return
  pushSteps([...todo.value.steps, { id: 's' + Date.now(), text, done: false }])
  newStep.value = ''
}
function toggleStep(id) { pushSteps(todo.value.steps.map(s => s.id === id ? { ...s, done: !s.done } : s)) }
function renameStep(id, text) {
  const v = text.trim()
  pushSteps(v ? todo.value.steps.map(s => s.id === id ? { ...s, text: v } : s) : todo.value.steps.filter(s => s.id !== id))
}
function removeStep(id) { pushSteps(todo.value.steps.filter(s => s.id !== id)) }

function remove() {
  store.deleteTodo(todo.value.id)
  emit('close')
}
</script>

<style lang="scss" scoped>
.todo-detail {
  width: 340px;
  flex-shrink: 0;
  border-left: 1px solid var(--color-border);
  background: var(--color-main-background);
  padding: 14px 16px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.detail-head { display: flex; align-items: center; justify-content: space-between; font-size: 0.8rem; color: var(--color-text-lighter); }
.title-line { display: flex; align-items: center; gap: 10px; }
.title-input { flex: 1; font-size: 1.1rem; font-weight: 600; border: none; background: transparent; color: var(--color-main-text); outline: none; padding: 4px 0; }
.check {
  width: 22px; height: 22px; min-width: 22px; min-height: 22px; max-width: 22px; max-height: 22px; box-sizing: border-box;
  flex-shrink: 0; border-radius: 50%; padding: 0; cursor: pointer;
  border: 2px solid var(--color-text-lighter); background: transparent; color: #fff; font-size: 12px;
  display: inline-flex; align-items: center; justify-content: center;
  &.checked { background: var(--color-primary-element); border-color: var(--color-primary-element); }
  &.small { width: 16px; height: 16px; min-width: 16px; min-height: 16px; max-width: 16px; max-height: 16px; font-size: 10px; }
}
.star { min-width: 0; min-height: 0; background: none; border: none; font-size: 1.2rem; cursor: pointer; color: var(--color-text-lighter); &.on { color: #f59e0b; } }
.block { border: 1px solid var(--color-border); border-radius: 12px; padding: 10px 12px; }
.step { display: flex; align-items: center; gap: 8px; padding: 3px 0; }
.step-input { flex: 1; border: none; background: transparent; color: var(--color-main-text); outline: none; &.done { text-decoration: line-through; opacity: 0.6; } }
.step-add { width: 100%; border: none; background: transparent; color: var(--color-text-lighter); outline: none; padding: 6px 0 2px; }
.x { min-width: 0; min-height: 0; background: none; border: none; cursor: pointer; color: var(--color-text-lighter); &:hover { color: var(--color-error); } }
.fields { display: flex; flex-direction: column; gap: 10px; label { display: flex; flex-direction: column; gap: 4px; font-size: 0.82rem; } }
.note-label { font-size: 0.82rem; display: block; margin-bottom: 6px; }
.note { resize: vertical; }
.detail-foot { margin-top: auto; }
</style>
