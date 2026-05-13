<template>
  <div class="markdown-editor-wrap">
    <div class="md-toolbar">
      <button class="md-btn" title="Bold (Ctrl+B)" @click="cmd('toggleBold')"><FormatBold :size="18"/></button>
      <button class="md-btn" title="Italic (Ctrl+I)" @click="cmd('toggleItalic')"><FormatItalic :size="18"/></button>
      <button class="md-btn" title="Strikethrough" @click="cmd('toggleStrikethrough')"><FormatStrikethrough :size="18"/></button>
      <div class="md-sep"/>
      <button class="md-btn" title="Heading 1" @click="cmd('toggleHeading1')"><FormatHeader1 :size="18"/></button>
      <button class="md-btn" title="Heading 2" @click="cmd('toggleHeading2')"><FormatHeader2 :size="18"/></button>
      <button class="md-btn" title="Heading 3" @click="cmd('toggleHeading3')"><FormatHeader3 :size="18"/></button>
      <div class="md-sep"/>
      <button class="md-btn" title="Quote" @click="cmd('toggleBlockquote')"><FormatQuoteClose :size="18"/></button>
      <button class="md-btn" title="Bullet list" @click="cmd('toggleUnorderedList')"><FormatListBulleted :size="18"/></button>
      <button class="md-btn" title="Numbered list" @click="cmd('toggleOrderedList')"><FormatListNumbered :size="18"/></button>
      <button class="md-btn" title="Code block" @click="cmd('toggleCodeBlock')"><CodeBraces :size="18"/></button>
      <button class="md-btn" title="Checklist" @click="insertChecklist"><CheckboxMarked :size="18"/></button>
      <div class="md-sep"/>
      <button class="md-btn" title="Insert link" @click="cmd('drawLink')"><LinkIcon :size="18"/></button>
      <button class="md-btn" title="Insert image" @click="fileInput.click()"><ImageIcon :size="18"/></button>
      <button class="md-btn" title="Drawing canvas" @click="showDrawing = true"><Draw :size="18"/></button>
      <button class="md-btn" title="Horizontal rule" @click="cmd('drawHorizontalRule')"><Minus :size="18"/></button>
      <div class="md-sep"/>
      <button class="md-btn" title="Undo" @click="cmd('undo')"><Undo :size="18"/></button>
      <button class="md-btn" title="Redo" @click="cmd('redo')"><Redo :size="18"/></button>
      <div class="md-sep"/>
      <button class="md-btn" :class="{ active: previewing }" title="Preview" @click="cmd('togglePreview')"><Eye :size="18"/></button>
    </div>

    <div class="md-editor-body" @click="onClickEditor">
      <textarea ref="textareaRef" />
    </div>

    <input ref="fileInput" type="file" accept="image/*" style="display:none" @change="onImageSelected" />
    <DrawingCanvas v-if="showDrawing" :initial-data="null" @save="onDrawingSave" @close="showDrawing = false" />
  </div>
</template>

<script setup>
import { ref, reactive, onMounted, onBeforeUnmount, watch } from 'vue'
import EasyMDE from 'easymde'
import 'easymde/dist/easymde.min.css'

import FormatBold from 'vue-material-design-icons/FormatBold.vue'
import FormatItalic from 'vue-material-design-icons/FormatItalic.vue'
import FormatStrikethrough from 'vue-material-design-icons/FormatStrikethrough.vue'
import FormatHeader1 from 'vue-material-design-icons/FormatHeader1.vue'
import FormatHeader2 from 'vue-material-design-icons/FormatHeader2.vue'
import FormatHeader3 from 'vue-material-design-icons/FormatHeader3.vue'
import FormatQuoteClose from 'vue-material-design-icons/FormatQuoteClose.vue'
import FormatListBulleted from 'vue-material-design-icons/FormatListBulleted.vue'
import FormatListNumbered from 'vue-material-design-icons/FormatListNumbered.vue'
import CodeBraces from 'vue-material-design-icons/CodeBraces.vue'
import LinkIcon from 'vue-material-design-icons/Link.vue'
import ImageIcon from 'vue-material-design-icons/Image.vue'
import Draw from 'vue-material-design-icons/Draw.vue'
import Minus from 'vue-material-design-icons/Minus.vue'
import Undo from 'vue-material-design-icons/Undo.vue'
import Redo from 'vue-material-design-icons/Redo.vue'
import Eye from 'vue-material-design-icons/Eye.vue'
import CheckboxMarked from 'vue-material-design-icons/CheckboxMarked.vue'
import DrawingCanvas from './DrawingCanvas.vue'

const props = defineProps({
  modelValue: { type: String, default: '' },
  readonly: { type: Boolean, default: false },
  startPreview: { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelValue', 'previewChange'])

const textareaRef = ref(null)
const fileInput = ref(null)
const previewing = ref(false)
const showDrawing = ref(false)
let mde = null

// ── Image token system ────────────────────────────────────────────────────────
// The editor stores short tokens like ![drawing](img:1).
// Actual base64 data lives in imgMap. This keeps raw base64 out of the editor.
const imgMap = reactive({})
let imgSeq = 0

function nextToken() { return `img:${++imgSeq}` }

function contentToEditor(content) {
  return content.replace(/!\[([^\]]*)\]\((data:image\/[^)]+)\)/g, (_, alt, src) => {
    let token = Object.keys(imgMap).find(k => imgMap[k] === src)
    if (!token) { token = nextToken(); imgMap[token] = src }
    return `![${alt}](${token})`
  })
}

function editorToContent(text) {
  return text.replace(/!\[([^\]]*)\]\((img:\d+)\)/g, (_, alt, token) => {
    const src = imgMap[token]
    return src ? `![${alt}](${src})` : `![${alt}](${token})`
  })
}

// ── Inline image widgets ──────────────────────────────────────────────────────
// Show actual image thumbnails inside the editor using addLineWidget.
let _widgets = []

function clearWidgets() {
  _widgets.forEach(w => w.clear())
  _widgets = []
}

function buildWidgets() {
  if (!mde) return
  clearWidgets()
  const doc = mde.codemirror.getDoc()
  const cm = mde.codemirror

  for (let i = 0; i < doc.lineCount(); i++) {
    const line = doc.getLine(i)
    if (!line) continue
    const m = line.match(/!\[[^\]]*\]\((img:\d+)\)/)
    if (!m) continue
    const src = imgMap[m[1]]
    if (!src) continue

    const lineIndex = i
    const token = m[1]

    const wrap = document.createElement('div')
    wrap.className = 'cm-img-widget'

    const img = document.createElement('img')
    img.src = src
    wrap.appendChild(img)

    const del = document.createElement('button')
    del.textContent = '✕'
    del.className = 'cm-img-del'
    wrap.appendChild(del)

    const widget = cm.addLineWidget(lineIndex, wrap)
    _widgets.push(widget)

    del.addEventListener('mousedown', (e) => {
      e.preventDefault()
      e.stopPropagation()
      // Remove token from imgMap
      delete imgMap[token]
      // Remove line from editor
      const text = mde.value()
      const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      const newText = text.replace(new RegExp(`!\\[[^\\]]*\\]\\(${escaped}\\)\\n?`), '')
      if (newText !== text) {
        const cursor = mde.codemirror.getCursor()
        mde.value(newText)
        mde.codemirror.setCursor(cursor)
        emit('update:modelValue', editorToContent(newText))
      }
    })
  }
}

// ── EasyMDE setup ─────────────────────────────────────────────────────────────
onMounted(() => {
  mde = new EasyMDE({
    element: textareaRef.value,
    initialValue: contentToEditor(props.modelValue),
    spellChecker: false,
    nativeSpellcheck: false,
    autoDownloadFontAwesome: false,
    toolbar: false,
    status: false,
    forceSync: true,
    tabSize: 4,
    shortcuts: { toggleSideBySide: null, togglePreview: null },
    // Expand img:N tokens to real data URIs before the preview renders,
    // so images and drawings show correctly in preview mode.
    previewRender: (plainText) => {
      const expanded = editorToContent(plainText)
      return mde.markdown(expanded)
    },
  })

  mde.codemirror.addKeyMap({ Home: 'goLineLeft', End: 'goLineRight' })
  mde.codemirror.on('change', () => {
    emit('update:modelValue', editorToContent(mde.value()))
    clearTimeout(mde._wt)
    mde._wt = setTimeout(buildWidgets, 300)
  })
  if (props.readonly) mde.codemirror.setOption('readOnly', true)
  mde.codemirror.clearHistory()

  document.querySelectorAll('.CodeMirror-code').forEach(el => {
    el.addEventListener('mousedown', onCheckboxClick)
  })

  setTimeout(buildWidgets, 150)

  // Start in preview mode for existing notes that already have content
  if (props.startPreview) {
    setTimeout(() => {
      if (mde && !previewing.value) {
        EasyMDE.togglePreview(mde)
        previewing.value = true
        emit('previewChange', true)
      }
    }, 80)
  } else {
    mde.codemirror.focus()
  }
})

onBeforeUnmount(() => {
  document.querySelectorAll('.CodeMirror-code').forEach(el => {
    el.removeEventListener('mousedown', onCheckboxClick)
  })
  clearWidgets()
  if (mde) { mde.toTextArea(); mde = null }
})

watch(() => props.modelValue, (val) => {
  if (!mde) return
  const editorVal = contentToEditor(val)
  if (editorVal !== mde.value()) {
    const cursor = mde.codemirror.getCursor()
    mde.value(editorVal)
    mde.codemirror.setCursor(cursor)
    setTimeout(buildWidgets, 150)
  }
})

watch(() => props.readonly, (val) => {
  if (mde) mde.codemirror.setOption('readOnly', val)
})

// ── Commands ──────────────────────────────────────────────────────────────────
function cmd(name) {
  if (!mde) return
  if (name === 'undo') { mde.codemirror.undo(); return }
  if (name === 'redo') { mde.codemirror.redo(); return }
  if (name === 'togglePreview') {
    EasyMDE.togglePreview(mde)
    previewing.value = !previewing.value
    emit('previewChange', previewing.value)
    return
  }
  EasyMDE[name]?.(mde)
  mde.codemirror.focus()
}

function onClickEditor(event) {
  if (!mde || previewing.value) return
  if (!event.target.closest('.CodeMirror')) {
    mde.codemirror.setCursor(mde.codemirror.lineCount(), 0)
    mde.codemirror.focus()
  }
}

function insertChecklist() {
  insertAtCursor('- [ ] ')
  emit('update:modelValue', editorToContent(mde.value()))
}

function onCheckboxClick(event) {
  const el = event.target.closest('.cm-formatting-task')
  if (!el || !mde) return
  event.preventDefault()
  event.stopImmediatePropagation()
  const doc = mde.codemirror.getDoc()
  const domLine = el.closest('.CodeMirror-line')
  const index = Array.from(domLine.parentElement.children).indexOf(domLine)
  const line = doc.getLineHandle(index)
  if (!line) return
  const isChecked = el.textContent.includes('x')
  doc.replaceRange(
    isChecked ? '[ ]' : '[x]',
    { line: index, ch: line.text.indexOf('[') },
    { line: index, ch: line.text.indexOf(']') + 1 },
  )
}

function insertAtCursor(text) {
  if (!mde) return
  mde.codemirror.getDoc().replaceRange(text, mde.codemirror.getCursor())
  mde.codemirror.focus()
}

function onImageSelected(event) {
  const file = event.target.files[0]
  if (!file) return
  const reader = new FileReader()
  reader.onload = (e) => {
    const token = nextToken()
    imgMap[token] = e.target.result
    insertAtCursor(`![${file.name}](${token})\n`)
    emit('update:modelValue', editorToContent(mde.value()))
    setTimeout(buildWidgets, 150)
  }
  reader.readAsDataURL(file)
  event.target.value = ''
}

// Exposed so parent can programmatically exit preview (e.g. "Edit" button)
defineExpose({
  exitPreview() {
    if (mde && previewing.value) {
      EasyMDE.togglePreview(mde)
      previewing.value = false
      emit('previewChange', false)
      mde.codemirror.focus()
    }
  },
})

function onDrawingSave(result) {
  showDrawing.value = false
  const token = nextToken()
  imgMap[token] = result.dataUrl
  insertAtCursor(`![drawing](${token})\n`)
  emit('update:modelValue', editorToContent(mde.value()))
  setTimeout(buildWidgets, 150)
}
</script>

<style>
.markdown-editor-wrap {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.md-toolbar {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 4px 8px;
  border-bottom: 1px solid var(--color-border);
  background: var(--color-main-background);
  flex-wrap: wrap;
  flex-shrink: 0;
}

.md-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border: none;
  background: none;
  border-radius: 4px;
  cursor: pointer;
  color: var(--color-main-text);
  padding: 0;
  transition: background 0.15s;
}
.md-btn:hover { background: var(--color-background-hover); }
.md-btn.active { background: var(--color-primary-light, #dbedff); color: var(--color-primary-element, #0082c9); }

.md-sep {
  width: 1px;
  height: 20px;
  background: var(--color-border);
  margin: 0 4px;
}

.md-editor-body {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
}

/* Inline image widgets inside CodeMirror */
.cm-img-widget {
  position: relative;
  display: inline-block;
  margin: 4px 0 8px 0;
}
.cm-img-widget img {
  display: block;
  max-width: 300px;
  max-height: 200px;
  border-radius: 6px;
  border: 1px solid rgba(255,255,255,0.15);
}
.cm-img-del {
  position: absolute;
  top: 4px;
  right: 4px;
  background: rgba(0,0,0,0.75);
  color: #fff;
  border: none;
  border-radius: 3px;
  cursor: pointer;
  padding: 2px 7px;
  font-size: 12px;
  line-height: 1.4;
  opacity: 0;
  transition: opacity 0.15s;
}
.cm-img-widget:hover .cm-img-del { opacity: 1; }

/* EasyMDE overrides */
.markdown-editor-wrap .EasyMDEContainer {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.markdown-editor-wrap .CodeMirror {
  flex: 1;
  height: 100%;
  border: none !important;
  color: var(--color-main-text) !important;
  background-color: transparent !important;
  font-size: 1rem;
  line-height: 1.7;
  font-family: inherit;
  padding-bottom: 30vh;
}

.markdown-editor-wrap .CodeMirror-scroll { min-height: 200px; }
.markdown-editor-wrap .CodeMirror-cursor { border-color: var(--color-main-text); }
.markdown-editor-wrap .CodeMirror .CodeMirror-code { font-size: inherit; margin: 0; padding: 0; }
.markdown-editor-wrap .CodeMirror .CodeMirror-selectedtext {
  background-color: var(--color-primary-element) !important;
  color: var(--color-primary-element-text) !important;
  opacity: 1 !important;
}
.markdown-editor-wrap .CodeMirror .CodeMirror-selected { background: inherit !important; }
.markdown-editor-wrap .CodeMirror-code { width: 100% !important; border: none !important; background-color: inherit !important; }

.markdown-editor-wrap .CodeMirror .cm-formatting { opacity: 0.35; }
.markdown-editor-wrap .cm-s-easymde .cm-header-1 { font-size: 1.8rem; font-weight: 700; }
.markdown-editor-wrap .cm-s-easymde .cm-header-2 { font-size: 1.4rem; font-weight: 700; }
.markdown-editor-wrap .cm-s-easymde .cm-header-3 { font-size: 1.15rem; font-weight: 700; }
.markdown-editor-wrap .cm-s-easymde .cm-quote { color: var(--color-text-lighter); font-style: italic; }
.markdown-editor-wrap .CodeMirror .cm-link { color: var(--color-primary-element); }
.markdown-editor-wrap .CodeMirror .cm-comment { font-family: monospace; font-size: 0.9em; }

/* Hide dash before task list items */
.markdown-editor-wrap .CodeMirror-line:has(.cm-formatting-task) .cm-formatting-list {
  display: none;
}

/* Task list checkboxes */
.markdown-editor-wrap .CodeMirror .cm-formatting-task {
  position: relative;
  display: inline-block;
  width: 1.4em;
  color: transparent !important;
  cursor: pointer;
}
.markdown-editor-wrap .CodeMirror .cm-formatting-task::before {
  content: '';
  width: 15px;
  height: 15px;
  position: absolute;
  top: 3px;
  left: 2px;
  background: var(--color-main-background);
  border: 2px solid #c0c8d8;
  border-radius: 3px;
}
.markdown-editor-wrap .CodeMirror .cm-formatting-task.cm-property::before {
  background: var(--color-primary-element, #0082c9);
  border-color: var(--color-primary-element, #0082c9);
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'%3E%3Cpolyline points='2,6 5,9 10,3' stroke='white' stroke-width='2' fill='none' stroke-linecap='round'/%3E%3C/svg%3E");
  background-size: 12px;
  background-repeat: no-repeat;
  background-position: center;
}
.markdown-editor-wrap .CodeMirror .cm-formatting-task ~ span { opacity: 0.6; }
.markdown-editor-wrap .CodeMirror .cm-formatting-task.cm-property ~ span {
  opacity: 0.5;
  text-decoration: line-through;
}

/* Preview */
.markdown-editor-wrap .editor-preview {
  background: var(--color-main-background);
  color: var(--color-main-text);
  padding: 24px;
}
</style>
