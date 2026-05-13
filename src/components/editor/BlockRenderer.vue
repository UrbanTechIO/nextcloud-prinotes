<template>
  <div class="block-wrapper" @click.stop="$emit('focus')">

    <!-- Paragraph -->
    <div
      v-if="block.type === 'paragraph'"
      ref="paraEl"
      class="block-richtext paragraph-block"
      contenteditable="true"
      spellcheck="true"
      dir="ltr"
      @input="onRichInput"
      @keydown="onTextKeyDown"
      @paste.prevent="onPaste"
    />

    <!-- Heading -->
    <div
      v-else-if="block.type === 'heading'"
      ref="headingEl"
      class="block-richtext heading-block"
      :class="`h${block.level || 1}-heading`"
      contenteditable="true"
      spellcheck="true"
      dir="ltr"
      @input="onRichInput"
      @keydown="onTextKeyDown"
      @paste.prevent="onPaste"
    />

    <!-- Quote -->
    <div
      v-else-if="block.type === 'quote'"
      ref="quoteEl"
      class="block-richtext quote-block"
      contenteditable="true"
      spellcheck="true"
      dir="ltr"
      @input="onRichInput"
      @keydown="onTextKeyDown"
      @paste.prevent="onPaste"
    />

    <!-- Code block -->
    <div v-else-if="block.type === 'code'" class="block code-block">
      <select class="code-lang" :value="block.language" @change="onLangChange">
        <option v-for="lang in codeLangs" :key="lang" :value="lang">{{ lang }}</option>
      </select>
      <textarea
        ref="codeEl"
        class="code-textarea"
        dir="ltr"
        spellcheck="false"
        @input="onCodeInput"
        @keydown.tab.prevent="insertTab"
      />
    </div>

    <!-- Checklist -->
    <ul v-else-if="block.type === 'checklist'" class="block checklist-block">
      <li v-for="(item, i) in block.items" :key="i" class="checklist-item">
        <input type="checkbox" :checked="item.checked" @change="toggleCheck(i)" />
        <textarea
          :ref="el => { checkItemEls[i] = el }"
          class="block-textarea item-textarea"
          :class="{ checked: item.checked }"
          dir="ltr"
          rows="1"
          @focus="focusedCheckIdx = i"
          @blur="focusedCheckIdx = -1"
          @input="onCheckItemInput(i, $event)"
          @keydown="onCheckItemKeyDown(i, $event)"
        />
      </li>
    </ul>

    <!-- List (ordered / bullet) -->
    <component
      :is="block.ordered ? 'ol' : 'ul'"
      v-else-if="block.type === 'list'"
      class="block list-block"
    >
      <li v-for="(item, i) in block.items" :key="i" class="list-li">
        <textarea
          :ref="el => { listItemEls[i] = el }"
          class="block-textarea item-textarea"
          dir="ltr"
          rows="1"
          @focus="focusedListIdx = i"
          @blur="focusedListIdx = -1"
          @input="onListItemInput(i, $event)"
          @keydown="onListItemKeyDown(i, $event)"
        />
      </li>
    </component>

    <!-- Image -->
    <div v-else-if="block.type === 'image'" class="block image-block">
      <div
        class="image-frame"
        :class="{ 'image-frame--selected': isSelected }"
        ref="imgContainerEl"
        :style="imageLayout.frameStyle"
        @click.stop="$emit('focus')"
      >
        <img
          :src="block.data"
          :alt="block.caption || block.filename"
          class="note-image"
          :style="imageLayout.imgStyle"
          draggable="false"
          @load="onImageLoad"
        />

        <template v-if="isSelected">
          <div class="img-action-bar" @click.stop>
            <button class="img-action-btn" title="Rotate left 15°"  @click="rotateImage(-RAD15)">↺</button>
            <button class="img-action-btn" title="Rotate right 15°" @click="rotateImage(RAD15)">↷</button>
            <button class="img-action-btn" title="Reset to full width" @click="resetImageWidth">⟷</button>
            <button class="img-action-btn img-action-btn--danger" title="Delete image" @click="$emit('delete')">✕</button>
          </div>
          <div class="img-resize-handle" title="Drag to resize" @mousedown.prevent.stop="startResize" />
        </template>
      </div>

      <input
        v-model="imageCaption"
        class="image-caption"
        placeholder="Caption (optional)"
        @click.stop
        @input="$emit('update', { ...block, caption: imageCaption })"
      />
    </div>

    <!-- Drawing -->
    <div v-else-if="block.type === 'drawing'" class="block drawing-block">
      <div class="drawing-toolbar">
        <button class="drawing-btn" title="Edit drawing" @click.stop="$emit('edit-drawing', block, index)">✏ Edit</button>
        <button class="drawing-btn danger" title="Delete" @click.stop="$emit('delete')">✕</button>
      </div>
      <img :src="block.data" class="drawing-image" alt="Drawing" />
    </div>

    <!-- Divider -->
    <div
      v-else-if="block.type === 'divider'"
      class="block divider-block-wrap"
      tabindex="0"
      @click.stop="$event.currentTarget.focus()"
      @keydown.backspace.prevent="$emit('delete')"
      @keydown.delete.prevent="$emit('delete')"
    >
      <hr class="divider-line" />
    </div>
  </div>
</template>

<script setup>
import { ref, watch, onMounted, nextTick } from 'vue'
import { useImageBlock } from '@/composables/useImageBlock.js'

const props = defineProps({
  block: { type: Object, required: true },
  index: { type: Number, required: true },
  isSelected: { type: Boolean, default: false },
})

const emit = defineEmits(['update', 'delete', 'focus', 'insert-after', 'edit-drawing'])

// Image logic in its own module scope (avoids esbuild '$' collision)
const {
  imageCaption,
  imgContainerEl,
  imageLayout,
  RAD15,
  onImageLoad,
  rotateImage,
  startResize,
  resetImageWidth,
} = useImageBlock(props, emit)

const codeLangs = ['plain', 'javascript', 'typescript', 'python', 'php', 'java', 'go', 'rust', 'bash', 'sql', 'html', 'css', 'json', 'yaml']

// ── Template refs ──────────────────────────────────────────────────────────
const paraEl       = ref(null)
const headingEl    = ref(null)
const quoteEl      = ref(null)
const codeEl       = ref(null)
const checkItemEls = ref([])
const listItemEls  = ref([])
const focusedCheckIdx = ref(-1)
const focusedListIdx  = ref(-1)

// ── Expose focus() so parent can programmatically focus this block ─────────
function focus() {
  const b = props.block
  if (b.type === 'paragraph')  { paraEl.value?.focus();           return }
  if (b.type === 'heading')    { headingEl.value?.focus();         return }
  if (b.type === 'quote')      { quoteEl.value?.focus();           return }
  if (b.type === 'code')       { codeEl.value?.focus();            return }
  if (b.type === 'checklist')  { checkItemEls.value[0]?.focus();   return }
  if (b.type === 'list')       { listItemEls.value[0]?.focus();    return }
}
defineExpose({ focus })

// ── Rich-text helpers ──────────────────────────────────────────────────────

// Accept both old web format { text } and quill op format { insert }
function normalizeOps(content) {
  if (!Array.isArray(content) || !content.length) return [{ insert: '' }]
  return content.map(item => {
    if (item.insert !== undefined) return item
    if (item.text  !== undefined) return { insert: item.text }
    return { insert: '' }
  })
}

// Convert rgb(r,g,b) string to #rrggbb hex
function rgbToHex(str) {
  const m = str?.match(/^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/)
  if (!m) return null
  return '#' + [m[1], m[2], m[3]].map(n => (+n).toString(16).padStart(2, '0')).join('')
}

// Convert quill ops → safe HTML for contenteditable innerHTML
function opsToHtml(ops) {
  let html = ''
  for (const op of normalizeOps(ops)) {
    if (typeof op.insert !== 'string') continue
    let t = op.insert
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
    const a = op.attributes || {}
    // Consolidate size + color into one span to avoid unnecessary nesting
    const styles = []
    if (a.size)  styles.push(`font-size:${a.size}px`)
    if (a.color) styles.push(`color:${a.color}`)
    if (styles.length) t = `<span style="${styles.join(';')}">${t}</span>`
    if (a.bold)      t = `<strong>${t}</strong>`
    if (a.italic)    t = `<em>${t}</em>`
    if (a.underline) t = `<u>${t}</u>`
    html += t
  }
  return html
}

// Walk a contenteditable element's DOM and extract quill ops
function domToOps(el) {
  const raw = []
  function walk(node, attrs) {
    if (node.nodeType === 3) {
      if (node.textContent) raw.push({ insert: node.textContent, _a: { ...attrs } })
      return
    }
    if (node.nodeType !== 1) return
    const tag = node.tagName.toLowerCase()
    if (tag === 'br') return
    const a = { ...attrs }
    if (tag === 'b' || tag === 'strong') a.bold = true
    if (tag === 'i' || tag === 'em')     a.italic = true
    if (tag === 'u')                     a.underline = true
    if (tag === 'span') {
      if (node.style.fontSize) a.size = node.style.fontSize.replace('px', '')
      if (node.style.color) {
        const c = rgbToHex(node.style.color) ?? node.style.color
        if (c && c !== 'inherit') a.color = c
      }
    }
    if (tag === 'font') {
      const c = node.getAttribute('color')
      if (c && c !== 'inherit') a.color = c
    }
    for (const child of node.childNodes) walk(child, a)
  }
  walk(el, {})

  // Merge consecutive runs with identical attrs; strip empty attr objects
  const result = []
  for (const { insert, _a } of raw) {
    const ca = {}
    if (_a.bold)      ca.bold = true
    if (_a.italic)    ca.italic = true
    if (_a.underline) ca.underline = true
    if (_a.size)      ca.size = _a.size
    if (_a.color)     ca.color = _a.color
    const hasAttrs = Object.keys(ca).length > 0
    const prev = result[result.length - 1]
    const sameKey = prev
      ? JSON.stringify(prev.attributes) === JSON.stringify(hasAttrs ? ca : undefined)
      : false
    if (sameKey) {
      prev.insert += insert
    } else {
      const op = { insert }
      if (hasAttrs) op.attributes = ca
      result.push(op)
    }
  }
  return result.length ? result : [{ insert: '' }]
}

// Set innerHTML only when not actively editing (prevents cursor disruption)
function syncContent(el, content) {
  if (!el) return
  if (document.activeElement === el) return
  el.innerHTML = opsToHtml(content)
}

// ── Rich-text event handlers ───────────────────────────────────────────────

function onRichInput(event) {
  emit('update', { ...props.block, content: domToOps(event.target) })
}

// Paste as plain text — avoids injecting external HTML/styles
function onPaste(event) {
  const text = event.clipboardData?.getData('text/plain') ?? ''
  document.execCommand('insertText', false, text)
}

function onTextKeyDown(event) {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault()
    emit('insert-after', 'paragraph')
  } else if (event.key === 'Backspace') {
    const text = domToOps(event.target).map(op => op.insert ?? '').join('')
    if (!text) {
      event.preventDefault()
      emit('delete')
    }
  }
}

// ── Mount: populate initial content ──────────────────────────────────────
onMounted(() => {
  syncContent(paraEl.value,    props.block.content)
  syncContent(headingEl.value, props.block.content)
  syncContent(quoteEl.value,   props.block.content)
  syncVal(codeEl.value, props.block.code ?? '')

  nextTick(() => {
    checkItemEls.value.forEach((el, i) => syncVal(el, props.block.items?.[i]?.text ?? ''))
    listItemEls.value.forEach((el, i)  => syncVal(el, props.block.items?.[i]?.text ?? ''))
  })
})

// ── External prop changes ─────────────────────────────────────────────────
watch(() => props.block.content, () => {
  syncContent(paraEl.value,    props.block.content)
  syncContent(headingEl.value, props.block.content)
  syncContent(quoteEl.value,   props.block.content)
}, { deep: true })

watch(() => props.block.code, v => syncVal(codeEl.value, v ?? ''))

watch(() => props.block.items, items => {
  items?.forEach((item, i) => {
    if (i !== focusedCheckIdx.value) syncVal(checkItemEls.value[i], item.text)
    if (i !== focusedListIdx.value)  syncVal(listItemEls.value[i],  item.text)
  })
}, { deep: true })

// ── Auto-resize textarea (code / list / checklist items) ──────────────────
function resize(el) {
  if (!el) return
  el.style.height = 'auto'
  el.style.height = el.scrollHeight + 'px'
}

function syncVal(el, text) {
  if (!el) return
  if (document.activeElement === el) return
  el.value = text ?? ''
  resize(el)
}

// ── Helpers ────────────────────────────────────────────────────────────────
function plainText(content) {
  if (!Array.isArray(content)) return ''
  return content.map(s => (s.insert ?? s.text ?? '')).join('')
}

// ── Code input ────────────────────────────────────────────────────────────
function onCodeInput(event) {
  resize(event.target)
  emit('update', { ...props.block, code: event.target.value })
}

function onLangChange(event) {
  emit('update', { ...props.block, language: event.target.value })
}

function insertTab(event) {
  const el    = event.target
  const start = el.selectionStart
  el.value = el.value.slice(0, start) + '  ' + el.value.slice(el.selectionEnd)
  el.selectionStart = el.selectionEnd = start + 2
  emit('update', { ...props.block, code: el.value })
}

// ── Checklist ──────────────────────────────────────────────────────────────
function toggleCheck(i) {
  const items = props.block.items.map((item, idx) =>
    idx === i ? { ...item, checked: !item.checked } : item
  )
  emit('update', { ...props.block, items })
}

function onCheckItemInput(i, event) {
  resize(event.target)
  const items = props.block.items.map((item, idx) =>
    idx === i ? { ...item, text: event.target.value } : item
  )
  emit('update', { ...props.block, items })
}

function onCheckItemKeyDown(i, event) {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault()
    const items = [...props.block.items]
    items.splice(i + 1, 0, { text: '', checked: false })
    emit('update', { ...props.block, items })
    nextTick(() => checkItemEls.value[i + 1]?.focus())
  } else if (event.key === 'Backspace' && !event.target.value) {
    event.preventDefault()
    if (props.block.items.length > 1) {
      const items = props.block.items.filter((_, idx) => idx !== i)
      emit('update', { ...props.block, items })
      nextTick(() => checkItemEls.value[Math.max(0, i - 1)]?.focus())
    } else {
      emit('delete')
    }
  }
}

// ── List ───────────────────────────────────────────────────────────────────
function onListItemInput(i, event) {
  resize(event.target)
  const items = props.block.items.map((item, idx) =>
    idx === i ? { ...item, text: event.target.value } : item
  )
  emit('update', { ...props.block, items })
}

function onListItemKeyDown(i, event) {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault()
    const items = [...props.block.items]
    items.splice(i + 1, 0, { text: '' })
    emit('update', { ...props.block, items })
    nextTick(() => listItemEls.value[i + 1]?.focus())
  } else if (event.key === 'Backspace' && !event.target.value) {
    event.preventDefault()
    if (props.block.items.length > 1) {
      const items = props.block.items.filter((_, idx) => idx !== i)
      emit('update', { ...props.block, items })
      nextTick(() => listItemEls.value[Math.max(0, i - 1)]?.focus())
    } else {
      emit('delete')
    }
  }
}
</script>

<style lang="scss" scoped>
.block-wrapper {
  margin: 0;
}

// ── Rich-text contenteditable base (paragraph / heading / quote) ───────────
.block-richtext {
  display: block;
  width: 100%;
  background: transparent;
  border: none;
  outline: none;
  font-family: inherit;
  direction: ltr !important;
  text-align: left !important;
  color: var(--color-main-text);
  caret-color: var(--color-primary-element);
  padding: 0;
  margin: 0;
  line-height: 1.4;
  box-sizing: border-box;
  word-break: break-word;
  white-space: pre-wrap;
  min-height: 1.4em;
  cursor: text;

  &:focus { outline: none; }

  // Inline formatting rendered by opsToHtml / execCommand
  :deep(strong) { font-weight: 700; }
  :deep(em)     { font-style: italic; }
  :deep(u)      { text-decoration: underline; }
  :deep(span)   { display: inline; }
}

// ── Shared textarea base (code, list items, checklist items) ──────────────
.block-textarea {
  display: block;
  width: 100%;
  background: transparent;
  border: none;
  outline: none;
  resize: none;
  overflow: hidden;
  font-family: inherit;
  direction: ltr !important;
  text-align: left !important;
  unicode-bidi: isolate;
  color: var(--color-main-text);
  caret-color: var(--color-primary-element);
  padding: 0;
  margin: 0;
  line-height: 1.4;
  box-sizing: border-box;
}

.paragraph-block {
  font-size: 1rem;
  padding: 1px 0;
}

.heading-block {
  font-weight: 700;
  margin: 3px 0 1px;
  &.h1-heading { font-size: 1.8rem; line-height: 1.3; }
  &.h2-heading { font-size: 1.4rem; line-height: 1.3; }
  &.h3-heading { font-size: 1.15rem; }
}

.quote-block {
  border-left: 3px solid var(--color-primary-element);
  padding-left: 16px;
  color: var(--color-text-lighter);
  font-style: italic;
  margin: 1px 0;
}

// ── Code block ─────────────────────────────────────────────────────────────
.code-block {
  background: var(--color-background-dark);
  border-radius: var(--border-radius);
  overflow: hidden;
  margin: 8px 0;

  .code-lang {
    background: var(--color-border);
    border: none;
    padding: 4px 8px;
    font-size: 0.78rem;
    width: 100%;
  }

  .code-textarea {
    display: block;
    width: 100%;
    background: transparent;
    border: none;
    outline: none;
    resize: none;
    overflow: hidden;
    padding: 16px;
    font-family: 'Fira Code', 'Consolas', monospace;
    font-size: 0.88rem;
    line-height: 1.6;
    color: var(--color-main-text);
    box-sizing: border-box;
  }
}

// ── Checklist ──────────────────────────────────────────────────────────────
.checklist-block {
  list-style: none;
  padding: 0;
  margin: 0;
}

.checklist-item {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 0;

  input[type='checkbox'] {
    width: 14px;
    height: 14px;
    cursor: pointer;
    flex-shrink: 0;
    margin-top: 3px;
  }
}

.item-textarea {
  flex: 1;
  min-width: 0;
  line-height: 1.4;

  &.checked {
    text-decoration: line-through;
    color: var(--color-text-lighter);
  }
}

// ── List ───────────────────────────────────────────────────────────────────
.list-block {
  padding-left: 20px;
  margin: 0;
}

.list-li {
  padding: 0;

  .item-textarea {
    line-height: 1.2;
  }
}

// ── Image ──────────────────────────────────────────────────────────────────
.image-block {
  margin: 12px 0;
  max-width: 100%;
  overflow: hidden;

  .image-frame {
    position: relative;
    display: block;
    min-width: 80px;
    max-width: 100%;
    cursor: pointer;
    outline: 3px solid transparent;
    outline-offset: 3px;
    border-radius: 4px;
    transition: outline-color 0.15s;
    overflow: visible;

    &:hover { outline-color: var(--color-border); }

    &.image-frame--selected {
      outline-color: var(--color-primary-element);
      cursor: default;
    }
  }

  .note-image {
    display: block;
    width: 100%;
    max-width: 100%;
    height: auto;
    pointer-events: none;
    user-select: none;
  }

  .img-action-bar {
    position: absolute;
    top: 8px;
    right: 8px;
    display: flex;
    gap: 4px;
    z-index: 10;
    background: rgba(0, 0, 0, 0.65);
    border-radius: 6px;
    padding: 4px 6px;
    backdrop-filter: blur(4px);
  }

  .img-action-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 30px;
    height: 28px;
    border: none;
    border-radius: 4px;
    background: transparent;
    color: #fff;
    font-size: 1rem;
    cursor: pointer;
    transition: background 0.1s;

    &:hover { background: rgba(255, 255, 255, 0.2); }
    &.img-action-btn--danger { color: #ff6b6b; }
    &.img-action-btn--danger:hover { background: rgba(255, 107, 107, 0.2); }
  }

  .img-resize-handle {
    position: absolute;
    bottom: 6px;
    right: 6px;
    width: 20px;
    height: 20px;
    cursor: se-resize;
    z-index: 10;
    border-radius: 3px;
    background: var(--color-primary-element);
    opacity: 0.8;
    transition: opacity 0.15s;

    &::after {
      content: '';
      position: absolute;
      bottom: 4px;
      right: 4px;
      width: 8px;
      height: 8px;
      border-right: 2px solid #fff;
      border-bottom: 2px solid #fff;
    }

    &:hover { opacity: 1; }
  }

  .image-caption {
    display: block;
    width: 100%;
    border: none;
    background: transparent;
    font-size: 0.82rem;
    color: var(--color-text-lighter);
    text-align: center;
    padding: 6px 10px;
    outline: none;
    box-sizing: border-box;
  }
}

// ── Drawing ────────────────────────────────────────────────────────────────
.drawing-block {
  margin: 12px 0;
  border: 1px solid var(--color-border);
  border-radius: var(--border-radius);
  overflow: hidden;

  .drawing-toolbar {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 6px 10px;
    background: var(--color-background-dark);
    border-bottom: 1px solid var(--color-border);
  }

  .drawing-btn {
    display: inline-flex;
    align-items: center;
    gap: 3px;
    padding: 3px 8px;
    border: 1px solid var(--color-border);
    border-radius: 4px;
    background: var(--color-main-background);
    color: var(--color-main-text);
    font-size: 0.78rem;
    cursor: pointer;
    &:hover { background: var(--color-background-hover); }
    &.danger { color: var(--color-error); border-color: var(--color-error); }
  }

  .drawing-image {
    max-width: 100%;
    display: block;
  }
}

// ── Divider ────────────────────────────────────────────────────────────────
.divider-block-wrap {
  outline: none;
  border-radius: 4px;
  padding: 4px 0;
  cursor: pointer;
  &:focus { box-shadow: 0 0 0 2px var(--color-primary, #2563eb44); }
}
.divider-line {
  border: none;
  border-top: 2px solid var(--color-border);
  margin: 8px 0;
  pointer-events: none;
}

.block {
  outline: none;
  width: 100%;
  min-height: 1.5em;
}
</style>
