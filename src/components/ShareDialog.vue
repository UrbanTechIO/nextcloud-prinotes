<template>
  <PModal title="Share Note" size="large" @close="$emit('close')">
    <div class="share-dialog">
      <div v-if="shares.length" class="existing-shares">
        <h4>Active Shares</h4>
        <div v-for="share in shares" :key="share.id" class="share-item">
          <div class="share-info">
            <span>{{ share.shareType === 'user' ? '👤' : '🔗' }}</span>
            <span>{{ share.sharedWith || 'Public link' }}</span>
            <span class="share-perm">({{ share.permissions }})</span>
          </div>
          <div class="share-actions">
            <button v-if="share.shareType === 'public'" class="btn" style="padding:4px 10px;font-size:0.8rem"
              @click="copyLink(share.token)">Copy link</button>
            <button class="btn" style="padding:4px 10px;font-size:0.8rem"
              @click="copyShareableMessage(share)">Share via…</button>
            <button class="btn btn-error" style="padding:4px 10px;font-size:0.8rem"
              @click="removeShare(share.id)">Remove</button>
          </div>
        </div>
      </div>

      <div class="new-share">
        <h4>Add Share</h4>
        <div class="share-type-toggle">
          <button class="btn" :class="{ active: newShareType === 'user' }" @click="newShareType = 'user'">
            Share with user
          </button>
          <button class="btn" :class="{ active: newShareType === 'public' }" @click="newShareType = 'public'">
            Public link
          </button>
        </div>

        <div v-if="newShareType === 'user'" class="form-field">
          <label>Username</label>
          <input v-model="sharedWithUser" class="p-input" placeholder="Nextcloud username" />
        </div>

        <div class="form-row" style="margin-top:10px">
          <label>Permissions</label>
          <select v-model="sharePermissions" class="p-select">
            <option value="read">Read only</option>
            <option value="write">Read &amp; Write</option>
          </select>
        </div>

        <button class="btn btn-primary" style="margin-top:12px" @click="addShare" :disabled="!canAdd">
          Create Share
        </button>
      </div>

      <div class="external-share">
        <h4>Share externally</h4>
        <p class="hint">First create a public link above, then share via:</p>
        <div class="ext-buttons">
          <button class="btn" @click="shareVia('whatsapp')" :disabled="!publicToken">WhatsApp</button>
          <button class="btn" @click="shareVia('telegram')" :disabled="!publicToken">Telegram</button>
          <button class="btn" @click="shareVia('email')" :disabled="!publicToken">Email</button>
          <button class="btn" @click="shareVia('copy')" :disabled="!publicToken">Copy link</button>
        </div>
      </div>
    </div>
  </PModal>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import PModal from './ui/PModal.vue'
import { useNotesStore } from '../stores/notes.js'

const props = defineProps({ note: { type: Object, required: true } })
const emit = defineEmits(['close'])

const store = useNotesStore()
const shares = ref([])
const newShareType = ref('user')
const sharedWithUser = ref('')
const sharePermissions = ref('read')

const publicToken = computed(() => shares.value.find(s => s.shareType === 'public')?.token ?? null)
const canAdd = computed(() => newShareType.value === 'user' ? sharedWithUser.value.trim().length > 0 : true)

onMounted(async () => { shares.value = await store.getShares(props.note.id) })

async function addShare() {
  const data = {
    shareType: newShareType.value,
    permissions: sharePermissions.value,
    sharedWith: newShareType.value === 'user' ? sharedWithUser.value.trim() : null,
  }
  shares.value.push(await store.createShare(props.note.id, data))
  sharedWithUser.value = ''
}

async function removeShare(shareId) {
  await store.deleteShare(props.note.id, shareId)
  shares.value = shares.value.filter(s => s.id !== shareId)
}

function copyLink(token) {
  navigator.clipboard.writeText(`${window.location.origin}/index.php/apps/prinotes/share/${token}`)
}

function copyShareableMessage(share) {
  const url = share.token ? `${window.location.origin}/index.php/apps/prinotes/share/${share.token}` : ''
  navigator.clipboard.writeText(`Check out my note: ${url}`)
}

function shareVia(method) {
  const url = `${window.location.origin}/index.php/apps/prinotes/share/${publicToken.value}`
  const text = `Check out my note: ${url}`
  const targets = {
    whatsapp: `https://wa.me/?text=${encodeURIComponent(text)}`,
    telegram: `https://t.me/share/url?url=${encodeURIComponent(url)}&text=${encodeURIComponent(props.note.title)}`,
    email: `mailto:?subject=${encodeURIComponent(props.note.title)}&body=${encodeURIComponent(text)}`,
  }
  if (method === 'copy') navigator.clipboard.writeText(url)
  else window.open(targets[method], '_blank')
}
</script>

<style lang="scss" scoped>
.share-dialog { min-width: 400px; }
h4 { font-size: 0.88rem; font-weight: 600; color: var(--color-text-lighter); text-transform: uppercase; margin: 16px 0 8px; &:first-child { margin-top: 0; } }
.existing-shares { margin-bottom: 16px; }
.share-item { display: flex; align-items: center; justify-content: space-between; padding: 8px; border: 1px solid var(--color-border); border-radius: var(--border-radius, 6px); margin-bottom: 6px; }
.share-info { display: flex; align-items: center; gap: 8px; font-size: 0.9rem; }
.share-perm { color: var(--color-text-lighter); font-size: 0.8rem; }
.share-actions { display: flex; gap: 6px; }
.share-type-toggle { display: flex; gap: 8px; margin-bottom: 12px; }
.form-field { display: flex; flex-direction: column; gap: 4px; label { font-size: 0.88rem; } }
.form-row { display: flex; align-items: center; gap: 12px; label { font-size: 0.88rem; } }
.external-share { margin-top: 16px; padding-top: 16px; border-top: 1px solid var(--color-border); .hint { font-size: 0.82rem; color: var(--color-text-lighter); margin-bottom: 8px; } }
.ext-buttons { display: flex; gap: 8px; flex-wrap: wrap; }
</style>
