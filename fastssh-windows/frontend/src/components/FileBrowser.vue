<script setup>
import { ref, onMounted } from 'vue'

const props = defineProps(['sessionId'])

const remotePath = ref('/')
const remoteFiles = ref([])
const loading = ref(false)
const status = ref('')

onMounted(() => {
  loadRemoteDir('/')
})

async function loadRemoteDir(path) {
  loading.value = true
  try {
    const files = await window.go.main.App.ListRemoteDir(props.sessionId, path)
    remoteFiles.value = files || []
    remotePath.value = path
  } catch (e) {
    status.value = 'Error: ' + e.toString()
  }
  loading.value = false
}

function navigateTo(item) {
  if (item.isDir) {
    loadRemoteDir(item.path)
  }
}

function goUp() {
  const parts = remotePath.value.split('/').filter(Boolean)
  parts.pop()
  loadRemoteDir('/' + parts.join('/'))
}

async function uploadFile() {
  // Use Wails file dialog
  try {
    const path = await window.runtime.OpenFileDialog({ title: 'Select file to upload' })
    if (!path) return
    const filename = path.split(/[/\\]/).pop()
    const remoteDest = remotePath.value + '/' + filename
    status.value = 'Uploading ' + filename + '...'
    await window.go.main.App.UploadFile(props.sessionId, path, remoteDest)
    status.value = 'Uploaded ' + filename
    loadRemoteDir(remotePath.value)
  } catch (e) {
    status.value = 'Upload failed: ' + e.toString()
  }
}

async function downloadFile(item) {
  try {
    const path = await window.runtime.SaveFileDialog({ title: 'Save as', defaultFilename: item.name })
    if (!path) return
    status.value = 'Downloading ' + item.name + '...'
    await window.go.main.App.DownloadFile(props.sessionId, item.path, path)
    status.value = 'Downloaded ' + item.name
  } catch (e) {
    status.value = 'Download failed: ' + e.toString()
  }
}

async function createFolder() {
  const name = prompt('Folder name:', 'new_folder')
  if (!name) return
  try {
    await window.go.main.App.MkdirRemote(props.sessionId, remotePath.value + '/' + name)
    loadRemoteDir(remotePath.value)
  } catch (e) {
    status.value = 'Create folder failed: ' + e.toString()
  }
}

async function deleteItem(item) {
  if (!confirm('Delete ' + item.name + '?')) return
  try {
    await window.go.main.App.RemoveRemote(props.sessionId, item.path)
    loadRemoteDir(remotePath.value)
  } catch (e) {
    status.value = 'Delete failed: ' + e.toString()
  }
}

function formatSize(bytes) {
  if (bytes < 1024) return bytes + ' B'
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB'
  if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + ' MB'
  return (bytes / 1024 / 1024 / 1024).toFixed(1) + ' GB'
}
</script>

<template>
  <div class="file-browser">
    <!-- Toolbar -->
    <div class="toolbar">
      <button @click="goUp" title="Go up">⬆</button>
      <input class="path-input" v-model="remotePath" @keydown.enter="loadRemoteDir(remotePath)" />
      <button @click="loadRemoteDir(remotePath)" title="Refresh">🔄</button>
      <button @click="uploadFile" title="Upload">⬆ Upload</button>
      <button @click="createFolder" title="New Folder">📁 New</button>
    </div>

    <!-- File List -->
    <div class="file-list scrollbar">
      <div class="file-header">
        <span class="col-name">Name</span>
        <span class="col-size">Size</span>
        <span class="col-time">Modified</span>
        <span class="col-actions"></span>
      </div>
      <div v-if="loading" class="loading">Loading...</div>
      <div v-for="item in remoteFiles" :key="item.path"
           class="file-row" @dblclick="navigateTo(item)">
        <span class="col-name">
          <span class="icon">{{ item.isDir ? '📁' : '📄' }}</span>
          {{ item.name }}
        </span>
        <span class="col-size">{{ item.isDir ? '-' : formatSize(item.size) }}</span>
        <span class="col-time">{{ item.modTime?.substring(0, 16).replace('T', ' ') }}</span>
        <span class="col-actions">
          <button v-if="!item.isDir" @click="downloadFile(item)" title="Download">⬇</button>
          <button @click="deleteItem(item)" title="Delete">✕</button>
        </span>
      </div>
    </div>

    <!-- Status -->
    <div class="status-bar" v-if="status">{{ status }}</div>
  </div>
</template>

<style scoped>
.file-browser {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.toolbar {
  display: flex;
  gap: 6px;
  padding: 8px;
  border-bottom: 1px solid var(--border);
  align-items: center;
}

.toolbar button {
  background: var(--bg-tertiary);
  color: var(--text-primary);
  font-size: 11px;
  padding: 5px 10px;
  white-space: nowrap;
}

.path-input {
  flex: 1;
  font-family: monospace;
  font-size: 12px;
}

.file-list {
  flex: 1;
  overflow-y: auto;
  padding: 4px 8px;
}

.file-header {
  display: flex;
  padding: 6px 8px;
  font-size: 11px;
  font-weight: 600;
  color: var(--text-secondary);
  border-bottom: 1px solid var(--border);
}

.file-row {
  display: flex;
  align-items: center;
  padding: 5px 8px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 12px;
}

.file-row:hover {
  background: var(--bg-tertiary);
}

.col-name { flex: 3; display: flex; align-items: center; gap: 6px; }
.col-size { flex: 1; color: var(--text-secondary); font-size: 11px; }
.col-time { flex: 2; color: var(--text-secondary); font-size: 11px; }
.col-actions { flex: 0.5; display: flex; gap: 4px; }

.col-actions button {
  background: transparent;
  color: var(--text-secondary);
  font-size: 11px;
  padding: 2px 5px;
}

.col-actions button:hover {
  color: var(--red);
}

.icon { font-size: 14px; }

.loading {
  text-align: center;
  padding: 20px;
  color: var(--text-secondary);
}

.status-bar {
  padding: 4px 10px;
  font-size: 11px;
  color: var(--text-secondary);
  border-top: 1px solid var(--border);
  background: var(--bg-secondary);
}
</style>
