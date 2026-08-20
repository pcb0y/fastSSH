<script setup>
import { ref, nextTick, watch } from 'vue'

const props = defineProps(['sessionId'])

const messages = ref([])
const inputText = ref('')
const isLoading = ref(false)
const messagesContainer = ref(null)
const maxIterations = 15

async function sendMessage() {
  const text = inputText.value.trim()
  if (!text || isLoading.value) return

  messages.value.push({ role: 'user', content: text })
  inputText.value = ''
  isLoading.value = true
  scrollToBottom()

  try {
    const config = await window.go.main.App.GetAIConfig()
    if (!config.apiKey && config.provider !== 'ollama') {
      messages.value.push({ role: 'error', content: 'AI not configured. Click ⚙ to set up.' })
      isLoading.value = false
      return
    }

    await runAgentLoop(config, text)
  } catch (e) {
    messages.value.push({ role: 'error', content: e.toString() })
  }

  isLoading.value = false
}

async function runAgentLoop(config, task) {
  const conversation = [{ role: 'user', content: task }]

  for (let i = 0; i < maxIterations; i++) {
    const response = await window.go.main.App.AIChat(config, conversation)

    if (response.type === 'command') {
      messages.value.push({ role: 'command', content: response.content })
      scrollToBottom()

      // Execute command
      let output = ''
      try {
        output = await window.go.main.App.ExecuteCommand(props.sessionId, response.content)
      } catch (e) {
        output = 'Error: ' + e.toString()
      }

      const trimmed = output.substring(0, 4000)
      messages.value.push({ role: 'output', content: trimmed || '(no output)' })
      scrollToBottom()

      // Feed back
      conversation.push({ role: 'assistant', content: '```command\n' + response.content + '\n```' })
      conversation.push({ role: 'user', content: 'Command output:\n' + (trimmed || '(no output)') })

    } else if (response.type === 'result') {
      messages.value.push({ role: 'result', content: response.content })
      scrollToBottom()
      return

    } else {
      messages.value.push({ role: 'error', content: response.content })
      return
    }

    // Small delay
    await new Promise(r => setTimeout(r, 500))
  }

  messages.value.push({ role: 'error', content: `Agent reached max iterations (${maxIterations}).` })
}

function scrollToBottom() {
  nextTick(() => {
    if (messagesContainer.value) {
      messagesContainer.value.scrollTop = messagesContainer.value.scrollHeight
    }
  })
}

function copyText(text) {
  navigator.clipboard.writeText(text)
}
</script>

<template>
  <div class="ai-panel">
    <div class="ai-header">
      <span>✨ AI Agent</span>
    </div>

    <div class="ai-messages scrollbar" ref="messagesContainer">
      <div v-for="(msg, i) in messages" :key="i" :class="'msg msg-' + msg.role">
        <div v-if="msg.role === 'user'" class="bubble user-bubble">{{ msg.content }}</div>
        <div v-else-if="msg.role === 'command'" class="bubble cmd-bubble">
          <span class="label">Command</span>
          <code>{{ msg.content }}</code>
        </div>
        <div v-else-if="msg.role === 'output'" class="bubble output-bubble">
          <span class="label">Output</span>
          <pre>{{ msg.content }}</pre>
        </div>
        <div v-else-if="msg.role === 'result'" class="bubble result-bubble">
          <span class="label">✓ Result</span>
          <pre>{{ msg.content }}</pre>
          <button class="copy-btn" @click="copyText(msg.content)">Copy</button>
        </div>
        <div v-else class="bubble error-bubble">⚠ {{ msg.content }}</div>
      </div>

      <div v-if="isLoading" class="loading">
        <span class="spinner"></span> Thinking...
      </div>
    </div>

    <div class="ai-input">
      <input
        v-model="inputText"
        placeholder="Describe what you want to do..."
        @keydown.enter="sendMessage"
        :disabled="isLoading"
      />
      <button @click="sendMessage" :disabled="!inputText.trim() || isLoading" class="send-btn">↑</button>
    </div>
  </div>
</template>

<style scoped>
.ai-panel {
  width: 340px;
  min-width: 340px;
  border-left: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  background: var(--bg-secondary);
}

.ai-header {
  padding: 10px 14px;
  font-weight: 600;
  border-bottom: 1px solid var(--border);
  color: var(--accent);
}

.ai-messages {
  flex: 1;
  overflow-y: auto;
  padding: 10px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.bubble {
  padding: 8px 10px;
  border-radius: 8px;
  font-size: 12px;
  word-break: break-word;
}

.user-bubble {
  background: rgba(203,166,247,0.15);
  align-self: flex-end;
  max-width: 85%;
}

.cmd-bubble {
  background: rgba(137,180,250,0.1);
  border: 1px solid rgba(137,180,250,0.2);
}

.cmd-bubble code {
  display: block;
  margin-top: 4px;
  font-family: monospace;
  color: var(--blue);
}

.output-bubble {
  background: var(--bg-tertiary);
}

.output-bubble pre {
  margin-top: 4px;
  font-family: monospace;
  font-size: 11px;
  max-height: 120px;
  overflow-y: auto;
  white-space: pre-wrap;
  color: var(--text-secondary);
}

.result-bubble {
  background: rgba(166,227,161,0.1);
  border: 1px solid rgba(166,227,161,0.2);
}

.result-bubble pre {
  margin-top: 4px;
  font-family: monospace;
  font-size: 12px;
  white-space: pre-wrap;
}

.copy-btn {
  margin-top: 6px;
  background: var(--bg-tertiary);
  color: var(--text-secondary);
  font-size: 11px;
  padding: 3px 8px;
}

.error-bubble {
  background: rgba(243,139,168,0.1);
  color: var(--orange);
}

.label {
  font-size: 10px;
  text-transform: uppercase;
  color: var(--text-secondary);
  font-weight: 600;
}

.loading {
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--text-secondary);
  font-size: 12px;
}

.spinner {
  width: 12px;
  height: 12px;
  border: 2px solid var(--border);
  border-top-color: var(--accent);
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.ai-input {
  display: flex;
  gap: 6px;
  padding: 10px;
  border-top: 1px solid var(--border);
}

.ai-input input {
  flex: 1;
}

.send-btn {
  background: var(--accent);
  color: var(--bg-primary);
  font-weight: bold;
  font-size: 14px;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
}

.send-btn:disabled {
  opacity: 0.4;
}
</style>
