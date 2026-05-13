import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import axios from '@nextcloud/axios'
import { generateUrl } from '@nextcloud/router'

const api = (path) => generateUrl(`/apps/prinotes/api${path}`)

export const useNotesStore = defineStore('notes', () => {
  const notes = ref([])
  const notebooks = ref([])
  const tags = ref([])
  const reminders = ref([])
  const settings = ref({})
  const loading = ref(false)
  const error = ref(null)
  const activeNotebookId = ref(null)
  const activeTagId = ref(null)
  const showArchived = ref(false)
  const showTrash = ref(false)
  const searchQuery = ref('')

  // ── Computed ─────────────────────────────────────────────────────────────
  const filteredNotes = computed(() => {
    let list = notes.value
    if (searchQuery.value.length >= 2) {
      const q = searchQuery.value.toLowerCase()
      list = list.filter(n =>
        n.title.toLowerCase().includes(q) ||
        (n.preview || '').toLowerCase().includes(q) ||
        n.tags.some(t => t.name.toLowerCase().includes(q))
      )
    }
    return list
  })

  const pinnedNotes = computed(() => filteredNotes.value.filter(n => n.isPinned))
  const unpinnedNotes = computed(() => filteredNotes.value.filter(n => !n.isPinned))

  // ── Notes ─────────────────────────────────────────────────────────────────
  async function fetchNotes() {
    loading.value = true
    error.value = null
    try {
      const params = {}
      if (activeNotebookId.value !== null) params.notebookId = activeNotebookId.value
      if (activeTagId.value !== null) params.tagId = activeTagId.value
      if (showTrash.value) params.trashed = true
      if (showArchived.value) params.archived = true

      if (searchQuery.value.length >= 2) {
        const { data } = await axios.get(api('/search'), { params: { q: searchQuery.value } })
        notes.value = data.ocs?.data ?? data
      } else {
        const { data } = await axios.get(api('/notes'), { params })
        notes.value = data.ocs?.data ?? data
      }
    } catch (e) {
      error.value = e.message
    } finally {
      loading.value = false
    }
  }

  const noteCache = new Map()

  async function getNote(id) {
    if (noteCache.has(id)) {
      const cached = noteCache.get(id)
      // Always fetch fresh for locked notes so lockPinHash is never stale
      if (cached.isLocked) {
        const { data } = await axios.get(api(`/notes/${id}`))
        const note = data.ocs?.data ?? data
        noteCache.set(id, note)
        return note
      }
      // If cached entry has no content field (populated from list endpoint which
      // excludes content), we must fetch the full note before returning
      if (!('content' in cached)) {
        const { data } = await axios.get(api(`/notes/${id}`))
        const note = data.ocs?.data ?? data
        noteCache.set(id, note)
        return note
      }
      // For non-locked notes with full data: return cached immediately, refresh in background
      axios.get(api(`/notes/${id}`)).then(({ data }) => {
        const note = data.ocs?.data ?? data
        noteCache.set(id, note)
      }).catch(() => {})
      return cached
    }
    const { data } = await axios.get(api(`/notes/${id}`))
    const note = data.ocs?.data ?? data
    noteCache.set(id, note)
    return note
  }

  function invalidateNote(id) { noteCache.delete(id) }

  /** Return cached note content without triggering a fetch. Used for card previews. */
  function peekNote(id) { return noteCache.get(id) ?? null }

  async function createNote(noteData = {}) {
    const { data } = await axios.post(api('/notes'), {
      title: '',
      content: JSON.stringify({ version: '1.0', blocks: [] }),
      ...noteData,
      notebookId: activeNotebookId.value ?? noteData.notebookId ?? null,
    })
    const note = data.ocs?.data ?? data
    notes.value.unshift(note)
    return note
  }

  async function updateNote(id, changes) {
    const { data } = await axios.put(api(`/notes/${id}`), changes)
    const updated = data.ocs?.data ?? data
    const idx = notes.value.findIndex(n => n.id === id)
    if (idx !== -1) notes.value[idx] = updated
    noteCache.set(id, updated)
    return updated
  }

  async function trashNote(id) {
    await axios.delete(api(`/notes/${id}`))
    notes.value = notes.value.filter(n => n.id !== id)
  }

  async function deleteNotePermanently(id) {
    await axios.delete(api(`/notes/${id}`), { params: { force: true } })
    notes.value = notes.value.filter(n => n.id !== id)
  }

  async function restoreNote(id) {
    const { data } = await axios.post(api(`/notes/${id}/restore`))
    const note = data.ocs?.data ?? data
    notes.value = notes.value.filter(n => n.id !== id)
    return note
  }

  async function getVersions(noteId) {
    const { data } = await axios.get(api(`/notes/${noteId}/versions`))
    return data.ocs?.data ?? data
  }

  async function restoreVersion(noteId, versionId) {
    const { data } = await axios.post(api(`/notes/${noteId}/versions/${versionId}/restore`))
    const note = data.ocs?.data ?? data
    const idx = notes.value.findIndex(n => n.id === noteId)
    if (idx !== -1) notes.value[idx] = note
    return note
  }

  // ── Notebooks ──────────────────────────────────────────────────────────────
  async function fetchNotebooks() {
    const { data } = await axios.get(api('/notebooks'))
    notebooks.value = data.ocs?.data ?? data
  }

  async function createNotebook(nbData) {
    const { data } = await axios.post(api('/notebooks'), nbData)
    const nb = data.ocs?.data ?? data
    notebooks.value.push(nb)
    return nb
  }

  async function updateNotebook(id, changes) {
    const { data } = await axios.put(api(`/notebooks/${id}`), changes)
    const nb = data.ocs?.data ?? data
    const idx = notebooks.value.findIndex(n => n.id === id)
    if (idx !== -1) notebooks.value[idx] = nb
    return nb
  }

  async function deleteNotebook(id) {
    await axios.delete(api(`/notebooks/${id}`))
    notebooks.value = notebooks.value.filter(n => n.id !== id)
    if (activeNotebookId.value === id) activeNotebookId.value = null
  }

  // ── Tags ───────────────────────────────────────────────────────────────────
  async function fetchTags() {
    const { data } = await axios.get(api('/tags'))
    tags.value = data.ocs?.data ?? data
  }

  async function createTag(tagData) {
    const { data } = await axios.post(api('/tags'), tagData)
    const tag = data.ocs?.data ?? data
    tags.value.push(tag)
    return tag
  }

  async function updateTag(id, changes) {
    const { data } = await axios.put(api(`/tags/${id}`), changes)
    const tag = data.ocs?.data ?? data
    const idx = tags.value.findIndex(t => t.id === id)
    if (idx !== -1) tags.value[idx] = tag
    return tag
  }

  async function deleteTag(id) {
    await axios.delete(api(`/tags/${id}`))
    tags.value = tags.value.filter(t => t.id !== id)
  }

  // ── Reminders ──────────────────────────────────────────────────────────────
  async function fetchReminders() {
    const { data } = await axios.get(api('/reminders'))
    reminders.value = data.ocs?.data ?? data
  }

  async function createReminder(reminderData) {
    const { data } = await axios.post(api('/reminders'), reminderData)
    const r = data.ocs?.data ?? data
    reminders.value.push(r)
    return r
  }

  async function deleteReminder(id) {
    await axios.delete(api(`/reminders/${id}`))
    reminders.value = reminders.value.filter(r => r.id !== id)
  }

  // ── Settings ───────────────────────────────────────────────────────────────
  async function fetchSettings() {
    const { data } = await axios.get(api('/settings'))
    settings.value = data.ocs?.data ?? data
  }

  async function saveSettings(changes) {
    const { data } = await axios.post(api('/settings'), changes)
    settings.value = data.ocs?.data ?? data
  }

  // ── Shares ──────────────────────────────────────────────────────────────────
  async function getShares(noteId) {
    const { data } = await axios.get(api(`/notes/${noteId}/shares`))
    return data.ocs?.data ?? data
  }

  async function createShare(noteId, shareData) {
    const { data } = await axios.post(api(`/notes/${noteId}/shares`), shareData)
    return data.ocs?.data ?? data
  }

  async function deleteShare(noteId, shareId) {
    await axios.delete(api(`/notes/${noteId}/shares/${shareId}`))
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  async function init() {
    await Promise.all([fetchNotebooks(), fetchTags(), fetchSettings()])
    await fetchNotes()
  }

  return {
    notes, notebooks, tags, reminders, settings, loading, error,
    activeNotebookId, activeTagId, showArchived, showTrash, searchQuery,
    filteredNotes, pinnedNotes, unpinnedNotes,
    fetchNotes, getNote, peekNote, createNote, updateNote, trashNote, deleteNotePermanently,
    restoreNote, getVersions, restoreVersion,
    fetchNotebooks, createNotebook, updateNotebook, deleteNotebook,
    fetchTags, createTag, updateTag, deleteTag,
    fetchReminders, createReminder, deleteReminder,
    fetchSettings, saveSettings,
    getShares, createShare, deleteShare,
    init,
  }
})
