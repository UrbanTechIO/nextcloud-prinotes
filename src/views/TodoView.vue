<template>
  <div class="todo-page">
    <div class="todo-main">
      <div class="todo-header">
        <h2>{{ store.viewTitle }}</h2>
        <span v-if="parentName" class="parent-name">{{ parentName }}</span>
        <button class="btn btn-primary new-btn" @click="focusAdd">+ New task</button>
      </div>

      <div class="chips">
        <button v-for="c in chips" :key="c.key" class="chip" :class="{ on: filter === c.key }" @click="filter = c.key">{{ c.label }}</button>
      </div>

      <div v-if="store.loading && !store.todos.length" class="empty">Loading…</div>

      <template v-if="filter !== 'done'">
        <TodoItem v-for="t in shownOpen" :key="t.id" :todo="t" :show-path="showPath" :path="store.listPath(t.listId)"
          :selected="t.id === selectedId" @toggle="store.toggleDone" @open="openTodo" @star="toggleStar" />
        <div v-if="!shownOpen.length && !store.loading" class="empty">{{ emptyText }}</div>
      </template>

      <input ref="addInput" v-model="newTitle" class="add-input" placeholder="+ Add a task…" @keydown.enter="add" />

      <div v-if="filter !== 'open' && store.finishedTodos.length" class="finished">
        <button class="finished-head" @click="showFinished = !showFinished">
          <span>{{ showFinished ? '▼' : '▶' }}</span> Finished <span class="n">({{ store.finishedTodos.length }})</span>
        </button>
        <template v-if="showFinished || filter === 'done'">
          <TodoItem v-for="t in store.finishedTodos" :key="t.id" :todo="t" :show-path="showPath" :path="store.listPath(t.listId)"
            :selected="t.id === selectedId" @toggle="store.toggleDone" @open="openTodo" @star="toggleStar" />
        </template>
      </div>
    </div>

    <TodoDetail v-if="selectedId" :todo-id="selectedId" @close="selectedId = null" />

    <div v-if="store.lastDeleted" class="snackbar">
      Task deleted <button class="undo" @click="store.undoDelete()">Undo</button>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted } from 'vue'
import { useRoute } from 'vue-router'
import TodoItem from '../components/TodoItem.vue'
import TodoDetail from '../components/TodoDetail.vue'
import { useTodosStore } from '../stores/todos.js'

const store = useTodosStore()
const route = useRoute()

const selectedId = ref(null)
const newTitle = ref('')
const addInput = ref(null)
const filter = ref('all')
const showFinished = ref(true)

const chips = [
  { key: 'all', label: 'All' },
  { key: 'open', label: 'Open' },
  { key: 'done', label: 'Done' },
  { key: 'reminder', label: '⏰ With reminder' },
]

function viewFromRoute() {
  const v = route.params.view
  if (!v) return 'today'
  return ['today', 'important', 'planned', 'all'].includes(v) ? v : (Number(v) || 'today')
}
onMounted(() => { store.activeView = viewFromRoute(); store.fetchAll() })
watch(() => route.params.view, () => { store.activeView = viewFromRoute(); selectedId.value = null; filter.value = 'all' })

const isSmart = computed(() => typeof store.activeView === 'string')
const parentName = computed(() => {
  if (isSmart.value) return ''
  const l = store.listById(store.activeView)
  return l?.parentId ? store.listById(l.parentId)?.title : ''
})
// Show each task's category on smart lists and on a parent that includes its sub-categories.
const showPath = computed(() => isSmart.value || store.lists.some(l => l.parentId === store.activeView))

const shownOpen = computed(() => filter.value === 'reminder'
  ? store.openTodos.filter(t => t.remindAt)
  : store.openTodos)

const emptyText = computed(() => ({
  today: 'Nothing due today. Enjoy.',
  important: 'No starred tasks.',
  planned: 'No tasks with a due date.',
}[store.activeView] ?? 'No open tasks here. Add one below.'))

async function add() {
  const title = newTitle.value.trim()
  if (!title) return
  newTitle.value = ''
  try { await store.addTodo(title) } catch { newTitle.value = title }
}
function focusAdd() { addInput.value?.focus() }
function openTodo(id) { selectedId.value = id }
function toggleStar(id) {
  const t = store.todos.find(x => x.id === id)
  if (t) store.updateTodo(id, { isImportant: !t.isImportant })
}
</script>

<style lang="scss" scoped>
.todo-page { display: flex; height: 100%; overflow: hidden; position: relative; }
.todo-main { flex: 1; min-width: 0; overflow-y: auto; padding: 18px 22px 80px; }
.todo-header { display: flex; align-items: baseline; gap: 10px; h2 { margin: 0; font-size: 1.5rem; } }
.parent-name { font-size: 0.85rem; color: var(--color-text-lighter); }
.new-btn { margin-left: auto; align-self: center; }
.chips { display: flex; gap: 6px; margin: 12px 0 4px; flex-wrap: wrap; }
.chip {
  border: 1px solid var(--color-border); background: transparent; color: var(--color-main-text);
  border-radius: 999px; padding: 3px 12px; font-size: 0.78rem; cursor: pointer;
  &.on { background: rgba(0, 130, 201, 0.25); border-color: var(--color-primary-element); }
}
.empty { margin: 28px 0; text-align: center; color: var(--color-text-lighter); }
.add-input {
  width: 100%; margin-top: 12px; padding: 10px 14px; box-sizing: border-box;
  border: 1px dashed var(--color-border); border-radius: 12px; background: transparent;
  color: var(--color-main-text); outline: none;
  &:focus { border-style: solid; border-color: var(--color-primary-element); }
}
.finished { margin-top: 18px; }
.finished-head {
  background: none; border: none; cursor: pointer; font-weight: 600; color: var(--color-main-text);
  display: flex; gap: 6px; align-items: center; padding: 4px 0;
  .n { font-weight: 400; opacity: 0.6; }
}
.snackbar {
  position: absolute; left: 50%; bottom: 22px; transform: translateX(-50%);
  background: #1e293b; color: #f1f5f9; border-radius: 10px; padding: 10px 16px;
  box-shadow: 0 6px 20px rgba(0, 0, 0, 0.35); display: flex; gap: 14px; align-items: center;
  .undo { background: none; border: none; color: #60a5fa; font-weight: 600; cursor: pointer; }
}
</style>
