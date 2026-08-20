<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import '@xterm/xterm/css/xterm.css'

const props = defineProps(['sessionId'])
const termRef = ref(null)
let term = null
let fitAddon = null
let resizeObserver = null

onMounted(() => {
  term = new Terminal({
    theme: {
      background: '#1e1e2e',
      foreground: '#cdd6f4',
      cursor: '#f5e0dc',
      selectionBackground: '#45475a',
      black: '#45475a',
      red: '#f38ba8',
      green: '#a6e3a1',
      yellow: '#f9e2af',
      blue: '#89b4fa',
      magenta: '#cba6f7',
      cyan: '#94e2d5',
      white: '#bac2de',
    },
    fontSize: 14,
    fontFamily: "'JetBrains Mono', 'Cascadia Code', 'Consolas', monospace",
    cursorBlink: true,
    scrollback: 5000,
  })

  fitAddon = new FitAddon()
  term.loadAddon(fitAddon)
  term.open(termRef.value)
  fitAddon.fit()

  // Send input to backend
  term.onData((data) => {
    window.go.main.App.SendTerminalInput(props.sessionId, data)
  })

  // Receive output from backend
  window.runtime.EventsOn('terminal-output-' + props.sessionId, (output) => {
    term.write(output)
  })

  // Handle resize
  term.onResize(({ cols, rows }) => {
    window.go.main.App.ResizeTerminal(props.sessionId, cols, rows)
  })

  // Observe container resize
  resizeObserver = new ResizeObserver(() => {
    if (fitAddon) fitAddon.fit()
  })
  resizeObserver.observe(termRef.value)
})

onUnmounted(() => {
  if (resizeObserver) resizeObserver.disconnect()
  window.runtime.EventsOff('terminal-output-' + props.sessionId)
  if (term) term.dispose()
})
</script>

<template>
  <div class="terminal-container" ref="termRef"></div>
</template>

<style scoped>
.terminal-container {
  width: 100%;
  height: 100%;
  padding: 4px;
}
</style>
