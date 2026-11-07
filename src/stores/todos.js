import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import axios from '@nextcloud/axios'
import { generateUrl } from '@nextcloud/router'

const api = (path) => generateUrl(`/apps/prinotes/api${path}`)
const unwrap = (res) => res.data?.ocs?.data ?? res.data

export function localDateString(d = new Date()) {
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${m}-${day}`
}

const SMART = ['today', 'important', 'planned', 'all']
const UNDO_MS = 5000

export const useTodosStore = defineStore('todos', () => {
  const lists = ref([])
  const todos = ref([])
  const activeView = ref('today')
  const loading = ref(false)
  const error = ref(null)
  const lastDeleted = ref(null)
  let deleteTimer = null

  // ── Lists / tree ──────────────────────────────────────────────────────────
  const inbox = computed(() => lists.value.find(l => l.isSystem) ?? null)
  const tree = computed(() => {
    const top = lists.value.filter(l => !l.parentId)
    return top.map(l => ({ ...l, children: lists.value.filter(c => c.parentId === l.id) }))
  })
  function listById(id) { return lists.value.find(l => l.id === id) ?? null }
  function listPath(id) {
    const l = listById(id)
    if (!l) return ''
    const p = l.parentId ? listById(l.parentId) : null
    return p ? `${p.title} › ${l.title}` : l.title
  }
  function idsUnder(listId) {
    return [listId, ...lists.value.filter(l => l.parentId === listId).map(l => l.id)]
  }

  // ── Views ─────────────────────────────────────────────────────────────────
  function predicateFor(view) {
    const today = localDateString()
    if (view === 'today') return t => !!t.dueDate && t.dueDate <= today
    if (view === 'important') return t => t.isImportant
    if (view === 'planned') return t => !!t.dueDate
    if (view === 'all') return () => true
    const ids = idsUnder(view)
    return t => ids.includes(t.listId)
  }
  const weekAgo = () => Math.floor(Date.now() / 1000) - 7 * 86400

  function openFor(view) {
    const p = predicateFor(view)
    return todos.value.filter(t => !t.isDone && p(t)).sort(compareTodos)
  }
  function finishedFor(view) {
    const p = predicateFor(view)
    const smart = SMART.includes(view)
    return todos.value
      .filter(t => t.isDone && p(t) && (!smart || (t.doneAt ?? 0) >= weekAgo()))
      .sort((a, b) => (b.doneAt ?? 0) - (a.doneAt ?? 0))
  }
  function compareTodos(a, b) {
    const da = a.dueDate || '9999-99-99'
    const db = b.dueDate || '9999-99-99'
    if (da !== db) return da < db ? -1 : 1
    return a.id - b.id
  }
  function openCount(view) { return openFor(view).length }

  const openTodos = computed(() => openFor(activeView.value))
  const finishedTodos = computed(() => finishedFor(activeView.value))
  const viewTitle = computed(() => {
    const v = activeView.value
    if (v === 'today') return 'Today'
    if (v === 'important') return 'Important'
    if (v === 'planned') return 'Planned'
    if (v === 'all') return 'All tasks'
    return listById(v)?.title ?? 'To-Do'
  })

  // ── Loading ───────────────────────────────────────────────────────────────
  async function fetchAll() {
    loading.value = true
    error.value = null
    try {
      const [l, t] = await Promise.all([axios.get(api('/todo-lists')), axios.get(api('/todos'))])
      lists.value = unwrap(l)
      todos.value = unwrap(t)
    } catch (e) {
      error.value = e.message
    } finally {
      loading.value = false
    }
  }
  const init = fetchAll

  // ── Tasks ─────────────────────────────────────────────────────────────────
  function defaultListForView() {
    const v = activeView.value
    if (typeof v === 'number') return v
    return inbox.value?.id ?? null
  }

  async function addTodo(title, extra = {}) {
    const body = { title, listId: extra.listId ?? defaultListForView(), ...extra }
    if (activeView.value === 'today' && body.dueDate === undefined) body.dueDate = localDateString()
    if (activeView.value === 'important' && body.isImportant === undefined) body.isImportant = true
    const created = unwrap(await axios.post(api('/todos'), body))
    todos.value.push(created)
    return created
  }

  async function updateTodo(id, patch) {
    const i = todos.value.findIndex(t => t.id === id)
    if (i < 0) return
    const before = todos.value[i]
    todos.value[i] = { ...before, ...patch }
    try {
      const saved = unwrap(await axios.put(api(`/todos/${id}`), patch))
      const j = todos.value.findIndex(t => t.id === id)
      if (j >= 0) todos.value[j] = saved
    } catch (e) {
      const j = todos.value.findIndex(t => t.id === id)
      if (j >= 0) todos.value[j] = before
      error.value = e.message
      throw e
    }
  }

  async function toggleDone(id) {
    const t = todos.value.find(x => x.id === id)
    if (!t) return
    const repeating = !!t.repeatRule && !t.isDone
    await updateTodo(id, { isDone: !t.isDone })
    // The server spawns the next occurrence of a repeating task: pick it up.
    if (repeating) await fetchAll()
  }

  /** Removes the task now; the real DELETE is sent after UNDO_MS unless undoDelete() runs. */
  function deleteTodo(id) {
    const t = todos.value.find(x => x.id === id)
    if (!t) return
    flushDelete()
    todos.value = todos.value.filter(x => x.id !== id)
    lastDeleted.value = t
    deleteTimer = setTimeout(flushDelete, UNDO_MS)
  }
  async function flushDelete() {
    if (deleteTimer) { clearTimeout(deleteTimer); deleteTimer = null }
    const t = lastDeleted.value
    lastDeleted.value = null
    if (!t) return
    try { await axios.delete(api(`/todos/${t.id}`)) } catch (e) { error.value = e.message; await fetchAll() }
  }
  function undoDelete() {
    if (deleteTimer) { clearTimeout(deleteTimer); deleteTimer = null }
    if (lastDeleted.value) todos.value.push(lastDeleted.value)
    lastDeleted.value = null
  }

  // ── Lists ─────────────────────────────────────────────────────────────────
  async function addList(data) {
    const created = unwrap(await axios.post(api('/todo-lists'), data))
    lists.value.push(created)
    return created
  }
  async function updateList(id, data) {
    const saved = unwrap(await axios.put(api(`/todo-lists/${id}`), data))
    const i = lists.value.findIndex(l => l.id === id)
    if (i >= 0) lists.value[i] = saved
    return saved
  }
  async function deleteList(id) {
    await axios.delete(api(`/todo-lists/${id}`))
    if (activeView.value === id || idsUnder(id).includes(activeView.value)) activeView.value = 'today'
    await fetchAll()
  }
  function taskCountInList(id) {
    const ids = idsUnder(id)
    return todos.value.filter(t => ids.includes(t.listId)).length
  }

  return {
    lists, todos, activeView, loading, error, lastDeleted,
    inbox, tree, openTodos, finishedTodos, viewTitle,
    listById, listPath, openCount, taskCountInList,
    init, fetchAll, addTodo, updateTodo, toggleDone, deleteTodo, undoDelete,
    addList, updateList, deleteList,
  }
})
