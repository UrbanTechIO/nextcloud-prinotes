import { createApp, h } from 'vue'
import './styles/ui.scss'
import { RouterView } from 'vue-router'
import { createPinia } from 'pinia'
import { createRouter, createWebHashHistory } from 'vue-router'
import AppNavigation from './components/AppNavigation.vue'
import NoteList from './views/NoteList.vue'
import NoteEditor from './views/NoteEditor.vue'
import Settings from './views/Settings.vue'
import TrashView from './views/TrashView.vue'
import TodoView from './views/TodoView.vue'
import { useNotesStore } from './stores/notes.js'
import { useTodosStore } from './stores/todos.js'

const pinia = createPinia()

const router = createRouter({
  history: createWebHashHistory(),
  routes: [
    { path: '/', component: NoteList },
    { path: '/note/:id', component: NoteEditor },
    { path: '/note/new', component: NoteEditor },
    { path: '/settings', component: Settings },
    { path: '/trash', component: TrashView },
    { path: '/todo', component: TodoView },
    { path: '/todo/:view', component: TodoView },
  ],
})

// Mount sidebar into Nextcloud's #app-navigation — gets Nextcloud theming automatically
const navEl = document.getElementById('prinotes-nav')
if (navEl) {
  createApp(AppNavigation).use(pinia).use(router).mount(navEl)
}

// Mount content into Nextcloud's #app-content
const contentEl = document.getElementById('prinotes-content')
if (contentEl) {
  createApp({ render: () => h(RouterView) }).use(pinia).use(router).mount(contentEl)
}

// Bootstrap data — call after both apps mounted, pass pinia to use outside component
const store = useNotesStore(pinia)
store.init()
useTodosStore(pinia).init()
