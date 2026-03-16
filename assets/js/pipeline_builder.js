const GRID_SIZE = 20
const NODE_WIDTH = 128
const NODE_HEIGHT = 40
const VIEWPORT_PADDING = 24
const STATUS_VALUES = ["success", "fail", "retry", "partial_success"]
const FIDELITY_VALUES = [
  "full",
  "truncate",
  "compact",
  "summary:low",
  "summary:medium",
  "summary:high",
]
const NODE_TYPE_TO_SHAPE = {
  start: "Mdiamond",
  exit: "Msquare",
  codergen: "box",
  "wait.human": "hexagon",
  wait_for_human: "hexagon",
  conditional: "diamond",
  parallel: "component",
  "parallel.fan_in": "tripleoctagon",
  tool: "parallelogram",
  "stack.manager_loop": "house",
}
const COMMON_NODE_FIELDS = [
  "id",
  "label",
  "type",
  "class",
  "timeout",
  "maxRetries",
  "goalGate",
  "retryTarget",
  "fallbackRetryTarget",
  "fidelity",
  "threadId",
  "allowPartial",
]
const COMMON_NODE_ALLOWED_ATTRS = [
  "label",
  "class",
  "timeout",
  "max_retries",
  "goal_gate",
  "retry_target",
  "fallback_retry_target",
  "fidelity",
  "thread_id",
  "allow_partial",
]
const NODE_FIELDS_BY_TYPE = {
  start: [...COMMON_NODE_FIELDS, "edges"],
  exit: COMMON_NODE_FIELDS,
  tool: [
    ...COMMON_NODE_FIELDS,
    "command",
    "autoStatus",
    "edges",
  ],
  codergen: [
    ...COMMON_NODE_FIELDS,
    "prompt",
    "llmModel",
    "llmProvider",
    "reasoningEffort",
    "maxTokens",
    "temperature",
    "autoStatus",
    "edges",
  ],
  "wait.human": [
    ...COMMON_NODE_FIELDS,
    "prompt",
    "humanDefaultChoice",
    "humanTimeout",
    "humanInput",
    "humanMultiple",
    "humanRequired",
    "edges",
  ],
  wait_for_human: [
    ...COMMON_NODE_FIELDS,
    "prompt",
    "humanDefaultChoice",
    "humanTimeout",
    "humanInput",
    "humanMultiple",
    "humanRequired",
    "edges",
  ],
  conditional: [...COMMON_NODE_FIELDS, "edges"],
  parallel: [
    ...COMMON_NODE_FIELDS,
    "joinPolicy",
    "maxParallel",
    "k",
    "quorumRatio",
    "edges",
  ],
  "parallel.fan_in": [...COMMON_NODE_FIELDS, "edges"],
  "stack.manager_loop": [
    ...COMMON_NODE_FIELDS,
    "managerActions",
    "managerMaxCycles",
    "managerPollInterval",
    "managerStopCondition",
    "stackChildAutostart",
    "edges",
  ],
}
const NODE_ALLOWED_ATTRS_BY_TYPE = {
  start: COMMON_NODE_ALLOWED_ATTRS,
  exit: COMMON_NODE_ALLOWED_ATTRS,
  tool: [
    ...COMMON_NODE_ALLOWED_ATTRS,
    "tool_command",
    "command",
    "auto_status",
  ],
  codergen: [
    ...COMMON_NODE_ALLOWED_ATTRS,
    "prompt",
    "llm_model",
    "llm_provider",
    "reasoning_effort",
    "max_tokens",
    "temperature",
    "auto_status",
  ],
  "wait.human": [
    ...COMMON_NODE_ALLOWED_ATTRS,
    "prompt",
    "human.default_choice",
    "human.timeout",
    "human.input",
    "human.multiple",
    "human.required",
  ],
  wait_for_human: [
    ...COMMON_NODE_ALLOWED_ATTRS,
    "prompt",
    "human.default_choice",
    "human.timeout",
    "human.input",
    "human.multiple",
    "human.required",
  ],
  conditional: COMMON_NODE_ALLOWED_ATTRS,
  parallel: [
    ...COMMON_NODE_ALLOWED_ATTRS,
    "join_policy",
    "max_parallel",
    "k",
    "quorum_ratio",
  ],
  "parallel.fan_in": COMMON_NODE_ALLOWED_ATTRS,
  "stack.manager_loop": [
    ...COMMON_NODE_ALLOWED_ATTRS,
    "manager.actions",
    "manager.max_cycles",
    "manager.poll_interval",
    "manager.stop_condition",
    "stack.child_autostart",
  ],
}
const EDGE_ALLOWED_ATTRS = ["label", "weight", "fidelity", "thread_id", "loop_restart", "status", "condition"]
const NODE_TYPE_DEFINITIONS = [
  {
    type: "start",
    title: "Insert Start Node",
    subtitle: "Create the single workflow entry point.",
    keywords: ["start", "entry", "begin", "quick insert"],
  },
  {
    type: "tool",
    title: "Insert Tool Node",
    subtitle: "Run a shell command or tool step.",
    keywords: ["tool", "command", "shell", "quick insert"],
  },
  {
    type: "codergen",
    title: "Insert LLM Node",
    subtitle: "Add a codergen or LLM-backed step.",
    keywords: ["llm", "codergen", "model", "assistant", "quick insert"],
  },
  {
    type: "wait.human",
    title: "Insert Human Node",
    subtitle: "Pause for a human decision or input.",
    keywords: ["human", "approval", "wait", "review", "quick insert"],
  },
  {
    type: "conditional",
    title: "Insert Decision Node",
    subtitle: "Route to different paths from conditions.",
    keywords: ["decision", "conditional", "branch", "if", "quick insert"],
  },
  {
    type: "parallel",
    title: "Insert Parallel Node",
    subtitle: "Fan work out to concurrent paths.",
    keywords: ["parallel", "fan out", "concurrent", "quick insert"],
  },
  {
    type: "parallel.fan_in",
    title: "Insert Fan-In Node",
    subtitle: "Merge parallel branches back together.",
    keywords: ["fan in", "merge", "parallel", "join", "quick insert"],
  },
  {
    type: "stack.manager_loop",
    title: "Insert Manager Node",
    subtitle: "Supervise looped child work.",
    keywords: ["manager", "loop", "stack", "supervisor", "quick insert"],
  },
  {
    type: "exit",
    title: "Insert End Node",
    subtitle: "Create the single workflow exit point.",
    keywords: ["end", "exit", "finish", "done", "quick insert"],
  },
]

const PipelineBuilder = {
  mounted() {
    this.dotEl = document.getElementById("pipeline-dot")
    this.canvas = document.getElementById("builder-canvas")
    this.edgesSvg = document.getElementById("builder-edges")

    if (!this.dotEl || !this.canvas || !this.edgesSvg) return

    this.csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
    this.state = {graphAttrs: {}, nodes: [], edges: []}
    this.connectMode = false
    this.pendingSource = null
    this.edgeDragSource = null
    this.edgeDragLine = null
    this.nextId = 1
    this.analysisRequestId = 0
    this.selectedNodeId = null
    this.commandResults = []
    this.activeCommandIndex = 0
    this.commandUsage = this.loadCommandUsage()
    this.lastPointer = null
    this.shellEl = document.getElementById("builder-shell")
    this.summaryEl = document.getElementById("workflow-summary")
    this.toggleLeftBtn = document.getElementById("toggle-left-panel")
    this.toggleLeftCenterBtn = document.getElementById("toggle-left-panel-center")
    this.toggleRightBtn = document.getElementById("toggle-right-panel")
    this.toggleRightCenterBtn = document.getElementById("toggle-right-panel-center")
    this.leftCollapsed = false
    this.rightCollapsed = false

    this.addStartBtn = document.getElementById("add-start")
    this.addToolBtn = document.getElementById("add-tool")
    this.addLlmBtn = document.getElementById("add-llm")
    this.addWaitHumanBtn = document.getElementById("add-wait-human")
    this.addConditionalBtn = document.getElementById("add-conditional")
    this.addParallelBtn = document.getElementById("add-parallel")
    this.addParallelFanInBtn = document.getElementById("add-parallel-fan-in")
    this.addStackManagerLoopBtn = document.getElementById("add-stack-manager-loop")
    this.addEndBtn = document.getElementById("add-end")
    this.connectBtn = document.getElementById("connect-toggle")
    this.clearEdgesBtn = document.getElementById("clear-edges")
    this.applyDotBtn = document.getElementById("apply-dot")
    this.propsDialog = document.getElementById("node-properties-dialog")
    this.propId = document.getElementById("node-prop-id")
    this.propLabel = document.getElementById("node-prop-label")
    this.propType = document.getElementById("node-prop-type")
    this.propCommandWrap = document.getElementById("node-prop-wrap-command")
    this.propCommand = document.getElementById("node-prop-command")
    this.propSave = document.getElementById("node-prop-save")
    this.propDelete = document.getElementById("node-prop-delete")
    this.propPrompt = document.getElementById("node-prop-prompt")
    this.propMaxRetries = document.getElementById("node-prop-max-retries")
    this.propGoalGate = document.getElementById("node-prop-goal-gate")
    this.propRetryTarget = document.getElementById("node-prop-retry-target")
    this.propFallbackRetryTarget = document.getElementById("node-prop-fallback-retry-target")
    this.propFidelity = document.getElementById("node-prop-fidelity")
    this.propThreadId = document.getElementById("node-prop-thread-id")
    this.propClass = document.getElementById("node-prop-class")
    this.propTimeout = document.getElementById("node-prop-timeout")
    this.propLlmModel = document.getElementById("node-prop-llm-model")
    this.propLlmProvider = document.getElementById("node-prop-llm-provider")
    this.propReasoningEffort = document.getElementById("node-prop-reasoning-effort")
    this.propMaxTokens = document.getElementById("node-prop-max-tokens")
    this.propTemperature = document.getElementById("node-prop-temperature")
    this.propHumanDefaultChoice = document.getElementById("node-prop-human-default-choice")
    this.propHumanTimeout = document.getElementById("node-prop-human-timeout")
    this.propHumanInput = document.getElementById("node-prop-human-input")
    this.propHumanMultiple = document.getElementById("node-prop-human-multiple")
    this.propHumanRequired = document.getElementById("node-prop-human-required")
    this.propJoinPolicy = document.getElementById("node-prop-join-policy")
    this.propMaxParallel = document.getElementById("node-prop-max-parallel")
    this.propK = document.getElementById("node-prop-k")
    this.propQuorumRatio = document.getElementById("node-prop-quorum-ratio")
    this.propManagerActions = document.getElementById("node-prop-manager-actions")
    this.propManagerMaxCycles = document.getElementById("node-prop-manager-max-cycles")
    this.propManagerPollInterval = document.getElementById("node-prop-manager-poll-interval")
    this.propManagerStopCondition = document.getElementById("node-prop-manager-stop-condition")
    this.propStackChildAutostart = document.getElementById("node-prop-stack-child-autostart")
    this.propAutoStatus = document.getElementById("node-prop-auto-status")
    this.propAllowPartial = document.getElementById("node-prop-allow-partial")
    this.propEdgesList = document.getElementById("node-edges-list")
    this.propAddEdge = document.getElementById("node-prop-add-edge")
    this.currentEditingNodeId = null
    this.edgeDialog = document.getElementById("edge-properties-dialog")
    this.edgePropSource = document.getElementById("edge-prop-source")
    this.edgePropTarget = document.getElementById("edge-prop-target")
    this.edgePropMode = document.getElementById("edge-prop-mode")
    this.edgePropValueWrap = document.getElementById("edge-prop-value-wrap")
    this.edgePropValue = document.getElementById("edge-prop-value")
    this.edgePropStatusWrap = document.getElementById("edge-prop-status-wrap")
    this.edgePropStatus = document.getElementById("edge-prop-status")
    this.edgePropLabel = document.getElementById("edge-prop-label")
    this.edgePropWeight = document.getElementById("edge-prop-weight")
    this.edgePropFidelity = document.getElementById("edge-prop-fidelity")
    this.edgePropThreadId = document.getElementById("edge-prop-thread-id")
    this.edgePropLoopRestart = document.getElementById("edge-prop-loop-restart")
    this.edgePropSave = document.getElementById("edge-prop-save")
    this.edgePropDelete = document.getElementById("edge-prop-delete")
    this.currentEditingEdgeIndex = null
    this.reopenNodePropertiesId = null
    this.graphGoal = document.getElementById("graph-goal")
    this.graphLabel = document.getElementById("graph-label")
    this.graphModelStylesheet = document.getElementById("graph-model-stylesheet")
    this.graphDefaultMaxRetry = document.getElementById("graph-default-max-retry")
    this.graphDefaultFidelity = document.getElementById("graph-default-fidelity")
    this.graphRetryTarget = document.getElementById("graph-retry-target")
    this.graphFallbackRetryTarget = document.getElementById("graph-fallback-retry-target")
    this.authoringStatus = document.getElementById("builder-authoring-status")
    this.diagnosticsSummary = document.getElementById("builder-diagnostics-summary")
    this.diagnosticsList = document.getElementById("builder-diagnostics-list")
    this.autofixActions = document.getElementById("builder-autofix-actions")
    this.templateSelect = document.getElementById("builder-template-select")
    this.loadTemplateBtn = document.getElementById("builder-load-template")
    this.formatDotBtn = document.getElementById("builder-format-dot")
    this.commandPaletteBtn = document.getElementById("open-command-palette")
    this.commandPaletteSecondaryBtn = document.getElementById("open-command-palette-secondary")
    this.commandPaletteDialog = document.getElementById("builder-command-palette")
    this.closeCommandPaletteBtn = document.getElementById("close-command-palette")
    this.commandSearchInput = document.getElementById("builder-command-search")
    this.commandResultsEl = document.getElementById("builder-command-results")
    this.commandEmptyEl = document.getElementById("builder-command-empty")
    this.shortcutsBtn = document.getElementById("open-builder-shortcuts")
    this.shortcutsDialog = document.getElementById("builder-shortcuts-dialog")
    this.closeShortcutsBtn = document.getElementById("close-builder-shortcuts")
    this.runPipelineBtn = document.getElementById("run-pipeline")
    this.savePipelineLibraryBtn = document.getElementById("save-pipeline-library")
    this.submitPipelineBtn = document.getElementById("submit-pipeline")
    this.openCreateLink = document.getElementById("open-create-dialog")
    this.openLibraryLink = document.querySelector('a[href="/library"]')
    this.nodeFieldWraps = {
      id: document.getElementById("node-prop-wrap-id"),
      label: document.getElementById("node-prop-wrap-label"),
      type: document.getElementById("node-prop-wrap-type"),
      prompt: document.getElementById("node-prop-wrap-prompt"),
      class: document.getElementById("node-prop-wrap-class"),
      timeout: document.getElementById("node-prop-wrap-timeout"),
      maxRetries: document.getElementById("node-prop-wrap-max-retries"),
      fidelity: document.getElementById("node-prop-wrap-fidelity"),
      threadId: document.getElementById("node-prop-wrap-thread-id"),
      retryTarget: document.getElementById("node-prop-wrap-retry-target"),
      fallbackRetryTarget: document.getElementById("node-prop-wrap-fallback-retry-target"),
      llmModel: document.getElementById("node-prop-wrap-llm-model"),
      llmProvider: document.getElementById("node-prop-wrap-llm-provider"),
      reasoningEffort: document.getElementById("node-prop-wrap-reasoning-effort"),
      maxTokens: document.getElementById("node-prop-wrap-max-tokens"),
      temperature: document.getElementById("node-prop-wrap-temperature"),
      command: document.getElementById("node-prop-wrap-command"),
      humanDefaultChoice: document.getElementById("node-prop-wrap-human-default-choice"),
      humanTimeout: document.getElementById("node-prop-wrap-human-timeout"),
      humanInput: document.getElementById("node-prop-wrap-human-input"),
      humanMultiple: document.getElementById("node-prop-wrap-human-multiple"),
      humanRequired: document.getElementById("node-prop-wrap-human-required"),
      joinPolicy: document.getElementById("node-prop-wrap-join-policy"),
      maxParallel: document.getElementById("node-prop-wrap-max-parallel"),
      k: document.getElementById("node-prop-wrap-k"),
      quorumRatio: document.getElementById("node-prop-wrap-quorum-ratio"),
      managerActions: document.getElementById("node-prop-wrap-manager-actions"),
      managerMaxCycles: document.getElementById("node-prop-wrap-manager-max-cycles"),
      managerPollInterval: document.getElementById("node-prop-wrap-manager-poll-interval"),
      managerStopCondition: document.getElementById("node-prop-wrap-manager-stop-condition"),
      stackChildAutostart: document.getElementById("node-prop-wrap-stack-child-autostart"),
      goalGate: document.getElementById("node-prop-wrap-goal-gate"),
      autoStatus: document.getElementById("node-prop-wrap-auto-status"),
      allowPartial: document.getElementById("node-prop-wrap-allow-partial"),
      edges: document.getElementById("node-prop-wrap-edges"),
    }

    this.addStartBtn?.addEventListener("click", () => this.addNode("start"))
    this.addToolBtn?.addEventListener("click", () => this.addNode("tool"))
    this.addLlmBtn?.addEventListener("click", () => this.addNode("codergen"))
    this.addWaitHumanBtn?.addEventListener("click", () => this.addNode("wait.human"))
    this.addConditionalBtn?.addEventListener("click", () => this.addNode("conditional"))
    this.addParallelBtn?.addEventListener("click", () => this.addNode("parallel"))
    this.addParallelFanInBtn?.addEventListener("click", () => this.addNode("parallel.fan_in"))
    this.addStackManagerLoopBtn?.addEventListener("click", () => this.addNode("stack.manager_loop"))
    this.addEndBtn?.addEventListener("click", () => this.addNode("exit"))
    this.clearEdgesBtn?.addEventListener("click", () => {
      this.state.edges = []
      this.sync({ writeDot: true, canonicalize: true })
    })

    this.connectBtn?.addEventListener("click", () => this.toggleConnectMode())

    this.applyDotBtn?.addEventListener("click", () => {
      this.analyzeDot(this.dotEl.value, { preservePositions: true, fit: true })
    })

    this.bindNodePropertyControls()
    this.edgePropSource?.addEventListener("change", () => this.populateEdgeTargetOptions())
    this.edgePropMode?.addEventListener("change", () => this.updateEdgeDialogValueVisibility())
    this.edgePropSave?.addEventListener("click", () => this.saveEdgeProperties())
    this.edgePropDelete?.addEventListener("click", () => this.deleteCurrentEdge())
    this.edgeDialog?.addEventListener("close", () => this.handleEdgeDialogClose())
    this.bindGraphInputs()
    this.bindPanelToggles()
    this.bindAuthoringControls()
    this.bindCommandPalette()
    this.bindCanvasTracking()
    this.bindKeyboardShortcuts()

    this.bindDotInput()

    this.renderDiagnostics([], [])
    this.loadTemplates()
    this.lastExternalDotValue = this.dotEl.value
    this.analyzeDot(this.dotEl.value, { preservePositions: false, fit: true })
  },

  updated() {
    this.dotEl = document.getElementById("pipeline-dot")
    if (!this.dotEl) return
    this.bindDotInput()
    this.bindNodePropertyControls()

    const nextDot = this.dotEl.value
    if (nextDot === this.lastExternalDotValue) return

    this.lastExternalDotValue = nextDot
    this.syncFromDotInput()
  },

  destroyed() {
    window.removeEventListener("keydown", this.boundKeydown)
    window.removeEventListener("builder:command-palette:open", this.boundOpenPalette)
    window.removeEventListener("builder:shortcuts:open", this.boundOpenShortcuts)
  },

  bindDotInput() {
    if (!this.dotEl || this.dotEl.dataset.builderBound === "true") return

    this.dotEl.dataset.builderBound = "true"
    this.dotEl.addEventListener("input", () => {
      window.clearTimeout(this.dotInputTimer)
      this.dotInputTimer = window.setTimeout(() => this.syncFromDotInput(), 220)
    })
  },

  bindAuthoringControls() {
    if (this.loadTemplateBtn && this.loadTemplateBtn.dataset.builderBound !== "true") {
      this.loadTemplateBtn.dataset.builderBound = "true"
      this.loadTemplateBtn.addEventListener("click", () => this.applyTemplate())
    }

    if (this.formatDotBtn && this.formatDotBtn.dataset.builderBound !== "true") {
      this.formatDotBtn.dataset.builderBound = "true"
      this.formatDotBtn.addEventListener("click", () => this.runTransform("format"))
    }
  },

  bindCanvasTracking() {
    if (!this.canvas || this.canvas.dataset.pointerBound === "true") return

    this.canvas.dataset.pointerBound = "true"
    const trackPointer = (event) => {
      const rect = this.canvas.getBoundingClientRect()
      this.lastPointer = {
        x: event.clientX - rect.left,
        y: event.clientY - rect.top,
        inside: event.clientX >= rect.left &&
          event.clientX <= rect.right &&
          event.clientY >= rect.top &&
          event.clientY <= rect.bottom,
      }
    }

    this.canvas.addEventListener("mousemove", trackPointer)
    this.canvas.addEventListener("mousedown", trackPointer)
    this.canvas.addEventListener("click", (event) => {
      if (event.target !== this.canvas) return
      if (this.selectedNodeId) {
        this.selectedNodeId = null
        this.sync({ writeDot: false, canonicalize: false })
      }
    })
  },

  bindCommandPalette() {
    if (this.commandPaletteBtn && this.commandPaletteBtn.dataset.builderBound !== "true") {
      this.commandPaletteBtn.dataset.builderBound = "true"
      this.commandPaletteBtn.addEventListener("click", () => this.openCommandPalette())
    }

    if (this.commandPaletteSecondaryBtn && this.commandPaletteSecondaryBtn.dataset.builderBound !== "true") {
      this.commandPaletteSecondaryBtn.dataset.builderBound = "true"
      this.commandPaletteSecondaryBtn.addEventListener("click", () => this.openCommandPalette())
    }

    if (this.closeCommandPaletteBtn && this.closeCommandPaletteBtn.dataset.builderBound !== "true") {
      this.closeCommandPaletteBtn.dataset.builderBound = "true"
      this.closeCommandPaletteBtn.addEventListener("click", () => this.closeCommandPalette())
    }

    if (this.commandSearchInput && this.commandSearchInput.dataset.builderBound !== "true") {
      this.commandSearchInput.dataset.builderBound = "true"
      this.commandSearchInput.addEventListener("input", () => this.refreshCommandPalette())
      this.commandSearchInput.addEventListener("keydown", (event) => this.handleCommandSearchKeydown(event))
    }

    if (this.commandPaletteDialog && this.commandPaletteDialog.dataset.builderBound !== "true") {
      this.commandPaletteDialog.dataset.builderBound = "true"
      this.commandPaletteDialog.addEventListener("click", (event) => {
        if (event.target === this.commandPaletteDialog) this.closeCommandPalette()
      })
      this.commandPaletteDialog.addEventListener("close", () => this.handlePaletteClose())
    }

    if (this.shortcutsBtn && this.shortcutsBtn.dataset.builderBound !== "true") {
      this.shortcutsBtn.dataset.builderBound = "true"
      this.shortcutsBtn.addEventListener("click", () => this.openShortcutsDialog())
    }

    if (this.closeShortcutsBtn && this.closeShortcutsBtn.dataset.builderBound !== "true") {
      this.closeShortcutsBtn.dataset.builderBound = "true"
      this.closeShortcutsBtn.addEventListener("click", () => this.closeShortcutsDialog())
    }

    if (this.shortcutsDialog && this.shortcutsDialog.dataset.builderBound !== "true") {
      this.shortcutsDialog.dataset.builderBound = "true"
      this.shortcutsDialog.addEventListener("click", (event) => {
        if (event.target === this.shortcutsDialog) this.closeShortcutsDialog()
      })
    }

    this.boundOpenPalette = () => this.openCommandPalette()
    this.boundOpenShortcuts = () => this.openShortcutsDialog()
    window.addEventListener("builder:command-palette:open", this.boundOpenPalette)
    window.addEventListener("builder:shortcuts:open", this.boundOpenShortcuts)
  },

  bindKeyboardShortcuts() {
    if (this.boundKeydown) return

    this.boundKeydown = (event) => {
      if (event.defaultPrevented) return

      const key = (event.key || "").toLowerCase()
      if ((event.ctrlKey || event.metaKey) && key === "k") {
        event.preventDefault()
        this.openCommandPalette()
        return
      }

      if (key === "escape") {
        if (this.commandPaletteDialog?.open) {
          event.preventDefault()
          this.closeCommandPalette()
          return
        }

        if (this.shortcutsDialog?.open) {
          event.preventDefault()
          this.closeShortcutsDialog()
        }
        return
      }

      if (this.commandPaletteDialog?.open || this.shortcutsDialog?.open) return
      if (this.isEditingField(event.target)) return

      if (event.shiftKey && key === "a") {
        event.preventDefault()
        this.openCommandPalette({ query: "insert " })
        return
      }

      if (event.shiftKey && key === "f") {
        event.preventDefault()
        this.executeBuilderAction("format-dot")
        return
      }

      if (event.shiftKey && key === "r") {
        event.preventDefault()
        this.executeBuilderAction("run-pipeline")
        return
      }

      if (!event.shiftKey && !event.altKey && !event.ctrlKey && !event.metaKey) {
        if (key === "c") {
          event.preventDefault()
          this.executeBuilderAction("toggle-connect-mode")
          return
        }

        if (key === "f") {
          event.preventDefault()
          this.executeBuilderAction("fit-view")
          return
        }

        if (key === "i") {
          event.preventDefault()
          this.executeBuilderAction("open-inspector")
          return
        }

        if (key === "?") {
          event.preventDefault()
          this.openShortcutsDialog()
        }
      }

      if ((key === "backspace" || key === "delete") && this.selectedNodeId) {
        event.preventDefault()
        this.executeBuilderAction("delete-selection")
      }
    }

    window.addEventListener("keydown", this.boundKeydown)
  },

  isEditingField(target) {
    if (!(target instanceof HTMLElement)) return false
    if (target.isContentEditable) return true
    return !!target.closest("input, textarea, select, [contenteditable='true']")
  },

  loadCommandUsage() {
    try {
      return JSON.parse(window.localStorage.getItem("builder-command-usage") || "{}")
    } catch (_error) {
      return {}
    }
  },

  persistCommandUsage() {
    try {
      window.localStorage.setItem("builder-command-usage", JSON.stringify(this.commandUsage || {}))
    } catch (_error) {
      // Ignore storage failures so the builder still works in private mode.
    }
  },

  trackCommandUsage(actionId) {
    this.commandUsage[actionId] = (this.commandUsage[actionId] || 0) + 1
    this.persistCommandUsage()
  },

  getInsertPosition(preferred = null) {
    if (preferred) return this.normalizeInsertPosition(preferred)
    if (this.lastPointer?.inside) return this.normalizeInsertPosition(this.lastPointer)
    return this.getViewportCenterPosition()
  },

  getViewportCenterPosition() {
    if (!this.canvas) return { x: 80, y: 60 }

    return this.normalizeInsertPosition({
      x: this.canvas.clientWidth / 2 - NODE_WIDTH / 2,
      y: this.canvas.clientHeight / 2 - NODE_HEIGHT / 2,
    })
  },

  normalizeInsertPosition(position) {
    const node = {
      x: Math.round((position?.x || 0) / GRID_SIZE) * GRID_SIZE,
      y: Math.round((position?.y || 0) / GRID_SIZE) * GRID_SIZE,
    }

    this.clampNodeToViewport(node)
    return node
  },

  getActionDefinitions() {
    const currentTemplateLabel = this.templateSelect?.selectedOptions?.[0]?.textContent?.trim() || "selected template"
    const insertActions = NODE_TYPE_DEFINITIONS.map((definition) => ({
      id: `insert-${definition.type}`,
      kind: "insert",
      category: "Insert",
      title: definition.title,
      subtitle: definition.subtitle,
      type: definition.type,
      keywords: definition.keywords,
      available: () => this.canInsertType(definition.type),
      score: (query) => this.scoreInsertAction(definition, query),
      execute: () => this.addNode(definition.type, { position: this.getInsertPosition() }),
    }))

    const actionEntries = [
      {
        id: "open-create",
        kind: "action",
        category: "Authoring",
        title: "Open Create With AI",
        subtitle: "Jump to the AI drafting flow.",
        shortcut: "Create",
        keywords: ["create", "ai", "draft", "generate"],
        execute: () => this.openCreateLink?.click(),
      },
      {
        id: "load-template",
        kind: "action",
        category: "Authoring",
        title: "Load Selected Template",
        subtitle: `Apply ${currentTemplateLabel}.`,
        keywords: ["template", "preset", "library", "load"],
        available: () => !!this.templateSelect?.value,
        execute: () => this.applyTemplate(),
      },
      {
        id: "format-dot",
        kind: "action",
        category: "Authoring",
        title: "Format DOT",
        subtitle: "Round-trip the current draft through the canonical formatter.",
        shortcut: "Shift+F",
        keywords: ["format", "dot", "canonical", "lint"],
        execute: () => this.runTransform("format"),
      },
      {
        id: "toggle-connect-mode",
        kind: "action",
        category: "Canvas",
        title: this.connectMode ? "Disable Connect Mode" : "Enable Connect Mode",
        subtitle: "Switch between dragging nodes and drawing edges.",
        shortcut: "C",
        keywords: ["connect", "edge", "wiring", "mode"],
        execute: () => this.toggleConnectMode(),
      },
      {
        id: "fit-view",
        kind: "action",
        category: "Canvas",
        title: "Fit Nodes In View",
        subtitle: "Recenter the current graph inside the canvas.",
        shortcut: "F",
        keywords: ["fit", "view", "recenter", "canvas"],
        execute: () => this.fitView(),
      },
      {
        id: "open-inspector",
        kind: "action",
        category: "Canvas",
        title: "Open Selected Inspector",
        subtitle: this.selectedNodeId ? `Inspect ${this.selectedNodeId}.` : "Select a node, then open the inspector.",
        shortcut: "I",
        keywords: ["inspector", "properties", "node", "edit"],
        available: () => !!this.selectedNodeId,
        execute: () => this.openNodeProperties(this.selectedNodeId),
      },
      {
        id: "delete-selection",
        kind: "action",
        category: "Canvas",
        title: "Delete Selected Node",
        subtitle: this.selectedNodeId ? `Remove ${this.selectedNodeId} from the canvas.` : "Select a node, then delete it.",
        shortcut: "Backspace",
        keywords: ["delete", "remove", "selection", "node"],
        available: () => !!this.selectedNodeId,
        execute: () => this.deleteNode(this.selectedNodeId),
      },
      {
        id: "run-pipeline",
        kind: "action",
        category: "Run",
        title: "Run Pipeline",
        subtitle: "Submit the current builder draft via /run.",
        shortcut: "Shift+R",
        keywords: ["run", "execute", "pipeline", "test"],
        execute: () => this.runPipelineBtn?.click(),
      },
      {
        id: "submit-pipeline",
        kind: "action",
        category: "Run",
        title: "Submit Pipeline via /pipelines",
        subtitle: "Send the draft to the pipeline endpoint.",
        keywords: ["submit", "pipelines", "publish"],
        execute: () => this.submitPipelineBtn?.click(),
      },
      {
        id: "save-library",
        kind: "action",
        category: "Run",
        title: "Save To Library",
        subtitle: "Store the current builder state as a reusable entry.",
        keywords: ["save", "library", "preset"],
        execute: () => this.savePipelineLibraryBtn?.click(),
      },
      {
        id: "open-library",
        kind: "action",
        category: "Run",
        title: "Open Library",
        subtitle: "Browse saved pipeline entries.",
        keywords: ["library", "browse", "saved"],
        execute: () => this.openLibraryLink?.click(),
      },
      {
        id: "open-shortcuts",
        kind: "action",
        category: "Help",
        title: "Open Shortcut Cheat Sheet",
        subtitle: "Review the keyboard-first builder controls.",
        shortcut: "?",
        keywords: ["help", "shortcuts", "cheat sheet", "keyboard"],
        execute: () => this.openShortcutsDialog(),
      },
    ]

    return [...insertActions, ...actionEntries]
  },

  canInsertType(type) {
    if (type === "start" || type === "exit") return !this.hasType(type)
    return true
  },

  scoreInsertAction(definition, query) {
    const lowerQuery = (query || "").trim().toLowerCase()
    const haystack = [definition.title, definition.subtitle, ...(definition.keywords || []), definition.type]
      .join(" ")
      .toLowerCase()

    let score = this.commandUsage[`insert-${definition.type}`] || 0
    if (!this.canInsertType(definition.type)) score -= 1000
    if (lowerQuery.length === 0) score += 20
    if (lowerQuery.includes("insert")) score += 8
    if (lowerQuery.includes(definition.type)) score += 10
    if (haystack.includes(lowerQuery)) score += 12
    if ((definition.title || "").toLowerCase().startsWith(lowerQuery)) score += 16
    return score
  },

  filterCommandResults(query = "") {
    const normalized = query.trim().toLowerCase()

    return this.getActionDefinitions()
      .filter((entry) => (typeof entry.available === "function" ? entry.available() : true))
      .map((entry) => {
        const searchable = [entry.title, entry.subtitle, ...(entry.keywords || []), entry.category, entry.type || ""]
          .join(" ")
          .toLowerCase()

        let score = this.commandUsage[entry.id] || 0
        if (typeof entry.score === "function") score += entry.score(normalized)
        if (normalized.length === 0) score += entry.kind === "insert" ? 6 : 2
        if (searchable.includes(normalized)) score += 10
        if ((entry.title || "").toLowerCase().startsWith(normalized)) score += 14
        if ((entry.type || "").toLowerCase() === normalized) score += 16

        return {...entry, searchable, score}
      })
      .filter((entry) => normalized.length === 0 || entry.searchable.includes(normalized) || entry.score > 0)
      .sort((a, b) => b.score - a.score || a.title.localeCompare(b.title))
      .slice(0, 12)
  },

  openCommandPalette(options = {}) {
    if (!this.commandPaletteDialog) return

    const nextQuery = options.query ?? this.commandSearchInput?.value ?? ""
    if (!this.commandPaletteDialog.open) this.commandPaletteDialog.showModal()
    if (this.commandSearchInput) this.commandSearchInput.value = nextQuery
    this.refreshCommandPalette()
    window.requestAnimationFrame(() => this.commandSearchInput?.focus())
  },

  closeCommandPalette() {
    if (this.commandPaletteDialog?.open) this.commandPaletteDialog.close()
  },

  handlePaletteClose() {
    this.commandResults = []
    this.activeCommandIndex = 0
    if (this.commandResultsEl) this.commandResultsEl.innerHTML = ""
    this.commandPaletteBtn?.focus()
  },

  refreshCommandPalette() {
    this.commandResults = this.filterCommandResults(this.commandSearchInput?.value || "")
    this.activeCommandIndex = Math.min(this.activeCommandIndex, Math.max(0, this.commandResults.length - 1))
    this.renderCommandResults()
  },

  renderCommandResults() {
    if (!this.commandResultsEl) return

    if (this.commandEmptyEl) {
      this.commandEmptyEl.classList.toggle("hidden", this.commandResults.length > 0)
    }

    this.commandResultsEl.innerHTML = this.commandResults.map((entry, index) => `
      <button
        type="button"
        class="builder-command-result ${index === this.activeCommandIndex ? "is-active" : ""}"
        data-command-id="${this.escapeHtml(entry.id)}"
        role="option"
        aria-selected="${index === this.activeCommandIndex ? "true" : "false"}"
      >
        <span class="builder-command-result-meta">
          <span class="builder-command-result-category">${this.escapeHtml(entry.category)}</span>
          ${entry.shortcut ? `<span class="builder-shortcut-pill">${this.escapeHtml(entry.shortcut)}</span>` : ""}
        </span>
        <span class="builder-command-result-title">${this.escapeHtml(entry.title)}</span>
        <span class="builder-command-result-subtitle">${this.escapeHtml(entry.subtitle || "")}</span>
      </button>
    `).join("")

    this.commandResultsEl.querySelectorAll("[data-command-id]").forEach((element, index) => {
      element.addEventListener("mouseenter", () => {
        this.activeCommandIndex = index
        this.renderCommandResults()
      })
      element.addEventListener("click", () => {
        const actionId = element.getAttribute("data-command-id") || ""
        this.executeBuilderAction(actionId)
      })
    })
  },

  handleCommandSearchKeydown(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.activeCommandIndex = Math.min(this.activeCommandIndex + 1, this.commandResults.length - 1)
      this.renderCommandResults()
      return
    }

    if (event.key === "ArrowUp") {
      event.preventDefault()
      this.activeCommandIndex = Math.max(this.activeCommandIndex - 1, 0)
      this.renderCommandResults()
      return
    }

    if (event.key === "Enter") {
      event.preventDefault()
      const entry = this.commandResults[this.activeCommandIndex]
      if (entry) this.executeBuilderAction(entry.id)
    }
  },

  executeBuilderAction(actionId) {
    const entry = this.getActionDefinitions().find((item) => item.id === actionId)
    if (!entry) return
    if (typeof entry.available === "function" && !entry.available()) return

    this.trackCommandUsage(actionId)
    this.closeCommandPalette()
    entry.execute()
  },

  openShortcutsDialog() {
    if (!this.shortcutsDialog?.open) this.shortcutsDialog?.showModal()
  },

  closeShortcutsDialog() {
    if (this.shortcutsDialog?.open) this.shortcutsDialog.close()
  },

  async requestJson(url, payload) {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-csrf-token": this.csrfToken,
      },
      body: JSON.stringify(payload),
    })

    let body = {}

    try {
      body = await response.json()
    } catch (_error) {
      body = {}
    }

    return { ok: response.ok, body }
  },

  async loadTemplates() {
    if (!this.templateSelect) return

    try {
      const response = await fetch("/api/authoring/templates", {
        headers: { accept: "application/json" },
      })
      const body = await response.json()
      const templates = body.templates || []

      this.templateSelect.innerHTML = [
        `<option value="">Choose a template</option>`,
        ...templates.map((template) => (
          `<option value="${this.escapeHtml(template.id)}">${this.escapeHtml(template.name)}</option>`
        )),
      ].join("")
    } catch (_error) {
      this.templateSelect.innerHTML = `<option value="">Template load failed</option>`
    }
  },

  async applyTemplate() {
    const templateId = this.templateSelect?.value || ""
    if (templateId === "") return

    this.setAuthoringStatus("Loading Template", false)
    const response = await this.requestJson("/api/authoring/transform", {
      action: "apply_template",
      template_id: templateId,
    })

    if (response.ok && response.body.graph) {
      this.applyCanonicalPayload(response.body, { preservePositions: false, fit: true })
      return
    }

    this.handleAuthoringError(response.body)
  },

  async runTransform(action, extra = {}) {
    this.setAuthoringStatus("Applying Transform", false)
    const response = await this.requestJson("/api/authoring/transform", {
      action,
      dot: this.getDraftDot(),
      ...extra,
    })

    if (response.ok && response.body.graph) {
      this.applyCanonicalPayload(response.body, { preservePositions: true, fit: true })
      return
    }

    this.handleAuthoringError(response.body)
  },

  async analyzeDot(dotText, options = {}) {
    const requestId = ++this.analysisRequestId
    this.setAuthoringStatus("Syncing", false)

    const response = await this.requestJson("/api/authoring/analyze", { dot: dotText })
    if (requestId !== this.analysisRequestId) return

    if (response.ok && response.body.graph) {
      this.applyCanonicalPayload(response.body, options)
      return
    }

    this.handleAuthoringError(response.body)
  },

  applyCanonicalPayload(payload, options = {}) {
    const preservePositions = options.preservePositions !== false
    const fit = options.fit === true
    const previousPositions = new Map(
      (this.state.nodes || []).map((node) => [node.id, { x: node.x, y: node.y }])
    )

    const graph = payload.graph || {}
    const nodeEntries = Object.values(graph.nodes || {})

    this.state = {
      graphAttrs: graph.attrs || {},
      nodes: nodeEntries.map((node, index) => {
        const previous = preservePositions ? previousPositions.get(node.id) : null
        return {
          id: node.id,
          type: node.type,
          attrs: node.attrs || {},
          x: previous?.x ?? 60 + index * 170,
          y: previous?.y ?? 80 + (index % 2) * 120,
        }
      }),
      edges: (graph.edges || []).map((edge) => ({
        from: edge.from,
        to: edge.to,
        attrs: edge.attrs || {},
      })),
    }

    if (this.selectedNodeId && !this.state.nodes.some((node) => node.id === this.selectedNodeId)) {
      this.selectedNodeId = null
    }

    if (fit) this.fitNodesInViewport()
    this.populateGraphFields()
    this.renderDiagnostics(payload.diagnostics || [], payload.autofixes || [])
    this.sync({ writeDot: false })

    if (this.dotEl && typeof payload.dot === "string") {
      this.dotEl.value = payload.dot
      this.lastExternalDotValue = payload.dot
    }

    this.setAuthoringStatus("Canonical", true)
  },

  handleAuthoringError(body) {
    this.renderDiagnostics(body?.diagnostics || [], body?.autofixes || [])
    this.setAuthoringStatus("Needs Repair", false)
  },

  setAuthoringStatus(label, ok) {
    if (!this.authoringStatus) return
    this.authoringStatus.textContent = label
    this.authoringStatus.className = [
      "rounded-full border px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.18em]",
      ok ? "border-emerald-300 bg-emerald-50 text-emerald-700" : "border-amber-300 bg-amber-50 text-amber-700",
    ].join(" ")
  },

  renderDiagnostics(diagnostics, autofixes) {
    if (this.diagnosticsSummary) {
      const counts = diagnostics.reduce((acc, diag) => {
        const severity = diag.severity || "info"
        acc[severity] = (acc[severity] || 0) + 1
        return acc
      }, {})

      const parts = ["error", "warning", "info"]
        .filter((severity) => counts[severity])
        .map((severity) => `${counts[severity]} ${severity}${counts[severity] === 1 ? "" : "s"}`)

      this.diagnosticsSummary.textContent =
        parts.length > 0 ? parts.join(" | ") : "No validator findings. Builder matches the canonical graph."
    }

    if (this.autofixActions) {
      this.autofixActions.innerHTML = (autofixes || []).map((fix) => (
        `<button type="button" class="builder-btn builder-autofix-btn" data-fix-id="${this.escapeHtml(fix.id)}">${this.escapeHtml(fix.label)}</button>`
      )).join("")

      this.autofixActions.querySelectorAll("[data-fix-id]").forEach((button) => {
        button.addEventListener("click", () => this.runTransform("apply_fix", { fix_id: button.dataset.fixId }))
      })
    }

    if (this.diagnosticsList) {
      if (!diagnostics || diagnostics.length === 0) {
        this.diagnosticsList.innerHTML = `
          <div class="rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-2 text-emerald-700">
            DOT parses cleanly and validator diagnostics are empty.
          </div>
        `
        return
      }

      this.diagnosticsList.innerHTML = diagnostics.map((diag) => {
        const severity = diag.severity || "info"
        const color =
          severity === "error"
            ? "border-red-300 bg-red-50 text-red-700"
            : severity === "warning"
              ? "border-amber-300 bg-amber-50 text-amber-800"
              : "border-sky-300 bg-sky-50 text-sky-700"
        const location = diag.node_id
          ? `node ${diag.node_id}`
          : diag.edge?.from && diag.edge?.to
            ? `edge ${diag.edge.from} -> ${diag.edge.to}`
            : "graph"

        return `
          <div class="rounded-lg border px-3 py-2 ${color}">
            <div class="flex items-center justify-between gap-3">
              <span class="font-semibold uppercase tracking-[0.16em]">${this.escapeHtml(severity)}</span>
              <span class="text-[11px] uppercase tracking-[0.16em]">${this.escapeHtml(location)}</span>
            </div>
            <p class="mt-1">${this.escapeHtml(diag.message || "")}</p>
          </div>
        `
      }).join("")
    }
  },

  bindNodePropertyControls() {
    this.propsDialog = document.getElementById("node-properties-dialog")
    this.propType = document.getElementById("node-prop-type")
    this.propSave = document.getElementById("node-prop-save")
    this.propDelete = document.getElementById("node-prop-delete")
    this.propAddEdge = document.getElementById("node-prop-add-edge")

    if (this.propType && this.propType.dataset.builderBound !== "true") {
      this.propType.dataset.builderBound = "true"
      this.propType.addEventListener("change", () => this.applyNodeTypeVisibility())
    }

    if (this.propSave && this.propSave.dataset.builderBound !== "true") {
      this.propSave.dataset.builderBound = "true"
      this.propSave.addEventListener("click", () => this.saveNodeProperties())
    }

    if (this.propDelete && this.propDelete.dataset.builderBound !== "true") {
      this.propDelete.dataset.builderBound = "true"
      this.propDelete.addEventListener("click", () => this.deleteCurrentNode())
    }

    if (this.propAddEdge && this.propAddEdge.dataset.builderBound !== "true") {
      this.propAddEdge.dataset.builderBound = "true"
      this.propAddEdge.addEventListener("click", () => this.startEdgeFromNodeDialog())
    }
  },

  parseDot(dotText, options = {}) {
    const useFallback = options.useFallback !== false
    const lines = dotText
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("digraph") && line !== "{" && line !== "}")

    const graphAttrs = {}
    const nodes = []
    const edges = []

    for (const line of lines) {
      if (line.startsWith("graph ")) {
        const graphMatch = line.match(/^graph\s*\[(.+)\]/)
        if (graphMatch) Object.assign(graphAttrs, this.parseAttrs(graphMatch[1]))
        continue
      }

      if (line.includes("->")) {
        const edgeMatch = line.match(/^([A-Za-z0-9_]+)\s*->\s*([A-Za-z0-9_]+)(?:\s*\[(.+)\])?/)
        if (edgeMatch) {
          const attrs = this.sanitizeEdgeAttrs(this.parseAttrs(edgeMatch[3] || ""))
          edges.push({
            from: edgeMatch[1],
            to: edgeMatch[2],
            attrs,
          })
        }
        continue
      }

      const nodeMatch = line.match(/^([A-Za-z0-9_]+)\s*\[(.+)\]/)
      if (!nodeMatch) continue

      const id = nodeMatch[1]
      const attrs = this.parseAttrs(nodeMatch[2])
      const type = attrs.type || this.typeFromShape(attrs.shape)
      const node = {
        id,
        type,
        attrs: this.normalizeNodeAttrs(attrs, type, id),
        x: 60 + nodes.length * 170,
        y: 80 + (nodes.length % 2) * 120,
      }
      nodes.push(node)
    }

    // Ensure graph has minimally useful nodes.
    if (nodes.length === 0 && useFallback) {
      return {
        graphAttrs: {
          goal: graphAttrs.goal || "Hello World",
          label: graphAttrs.label || "hello-world",
          ...graphAttrs,
        },
        nodes: [
          { id: "start", type: "start", attrs: { label: "start" }, x: 80, y: 120 },
          {
            id: "hello",
            type: "tool",
            attrs: { label: "hello", tool_command: "echo hello world" },
            x: 280,
            y: 120,
          },
          {
            id: "goodbye",
            type: "tool",
            attrs: { label: "goodbye", tool_command: "echo the end of the world is near" },
            x: 280,
            y: 240,
          },
          { id: "done", type: "exit", attrs: { label: "done" }, x: 500, y: 180 },
        ],
        edges: [
          { from: "start", to: "hello", attrs: {} },
          { from: "hello", to: "done", attrs: { status: "success" } },
          { from: "hello", to: "goodbye", attrs: { status: "fail" } },
          { from: "goodbye", to: "done", attrs: {} },
        ],
      }
    }

    return { graphAttrs, nodes, edges }
  },

  parseAttrs(attrText) {
    const attrs = {}
    attrText.split(",").forEach((entry) => {
      const parts = entry.split("=")
      if (parts.length < 2) return
      const key = parts[0].trim()
      const value = parts.slice(1).join("=").trim().replace(/^"/, "").replace(/"$/, "")
      attrs[key] = value
    })
    return attrs
  },

  typeFromShape(shape) {
    if (shape === "Mdiamond") return "start"
    if (shape === "Msquare") return "exit"
    if (shape === "parallelogram") return "tool"
    if (shape === "hexagon") return "wait.human"
    if (shape === "diamond") return "conditional"
    if (shape === "component") return "parallel"
    if (shape === "tripleoctagon") return "parallel.fan_in"
    if (shape === "house") return "stack.manager_loop"
    if (shape === "box") return "codergen"
    return "tool"
  },

  normalizeNodeAttrs(attrs, type, id) {
    const next = this.sanitizeNodeAttrs(attrs, type, id)
    if (!next.label) next.label = id
    if (type === "tool" && !next.tool_command) next.tool_command = "echo hello world"
    return next
  },

  sanitizeNodeAttrs(attrs, type, id) {
    const allowed = new Set(NODE_ALLOWED_ATTRS_BY_TYPE[type] || [])
    const next = {}

    Object.entries(attrs || {}).forEach(([key, rawValue]) => {
      if (key === "shape" || key === "type" || !allowed.has(key)) return
      const value = this.normalizeNodeAttrValue(key, rawValue)
      if (value !== "" && value !== null && value !== undefined) next[key] = value
    })

    if (!next.label) next.label = id
    return next
  },

  sanitizeEdgeAttrs(attrs) {
    const next = {}

    Object.entries(attrs || {}).forEach(([key, rawValue]) => {
      if (!EDGE_ALLOWED_ATTRS.includes(key)) return
      const value = this.normalizeEdgeAttrValue(key, rawValue)
      if (value !== "" && value !== null && value !== undefined) next[key] = value
    })

    return next
  },

  normalizeNodeAttrValue(key, value) {
    if (value === null || value === undefined) return ""
    if (["goal_gate", "auto_status", "allow_partial", "human.multiple", "human.required", "stack.child_autostart"].includes(key)) {
      return this.boolAttr(value) ? true : ""
    }

    const text = `${value}`.trim()
    if (text === "") return ""

    if (key === "reasoning_effort") return ["low", "medium", "high"].includes(text) ? text : ""
    if (key === "fidelity") return FIDELITY_VALUES.includes(text) ? text : ""
    if (key === "human.input") {
      return [
        "text",
        "textarea",
        "checkbox",
        "boolean",
        "confirmation",
        "single_select",
        "multi_select",
        "radio",
        "select",
      ].includes(text)
        ? text
        : ""
    }
    if (key === "join_policy") return ["wait_all", "first_success", "k_of_n", "quorum"].includes(text) ? text : ""
    if (key === "max_retries") return /^\d+$/.test(text) ? text : ""
    if (["max_tokens", "max_parallel", "k", "manager.max_cycles"].includes(key)) return /^[1-9]\d*$/.test(text) ? text : ""
    if (key === "temperature") return this.isNumberString(text) ? text : ""
    if (key === "quorum_ratio") return this.isNumberString(text) ? text : ""

    return text
  },

  normalizeEdgeAttrValue(key, value) {
    if (value === null || value === undefined) return ""
    if (key === "loop_restart") return this.boolAttr(value) ? true : ""

    const text = `${value}`.trim()
    if (text === "") return ""
    if (key === "status") return STATUS_VALUES.includes(text) ? text : ""
    if (key === "fidelity") return FIDELITY_VALUES.includes(text) ? text : ""
    if (key === "weight") return /^-?\d+$/.test(text) ? text : ""

    return text
  },

  bindGraphInputs() {
    const graphControls = [
      this.graphGoal,
      this.graphLabel,
      this.graphModelStylesheet,
      this.graphDefaultMaxRetry,
      this.graphDefaultFidelity,
      this.graphRetryTarget,
      this.graphFallbackRetryTarget,
    ]

    graphControls.forEach((el) => {
      el?.addEventListener("input", () => {
        this.state.graphAttrs = this.readGraphFields()
        this.sync({ writeDot: true, canonicalize: true })
      })
    })
  },

  populateGraphFields() {
    const attrs = this.state.graphAttrs || {}
    if (this.graphGoal) this.graphGoal.value = attrs.goal || ""
    if (this.graphLabel) this.graphLabel.value = attrs.label || ""
    if (this.graphModelStylesheet) this.graphModelStylesheet.value = attrs.model_stylesheet || ""
    if (this.graphDefaultMaxRetry) this.graphDefaultMaxRetry.value = attrs.default_max_retry || ""
    if (this.graphDefaultFidelity) this.graphDefaultFidelity.value = attrs.default_fidelity || ""
    if (this.graphRetryTarget) this.graphRetryTarget.value = attrs.retry_target || ""
    if (this.graphFallbackRetryTarget) this.graphFallbackRetryTarget.value = attrs.fallback_retry_target || ""
  },

  readGraphFields() {
    return this.cleanEmptyAttrs({
      goal: this.graphGoal?.value?.trim() || "",
      label: this.graphLabel?.value?.trim() || "",
      model_stylesheet: this.graphModelStylesheet?.value?.trim() || "",
      default_max_retry: this.graphDefaultMaxRetry?.value?.trim() || "",
      default_fidelity: this.graphDefaultFidelity?.value?.trim() || "",
      retry_target: this.graphRetryTarget?.value?.trim() || "",
      fallback_retry_target: this.graphFallbackRetryTarget?.value?.trim() || "",
    })
  },

  addNode(type, options = {}) {
    if ((type === "start" || type === "exit") && this.hasType(type)) {
      window.alert(`Only one ${type} node is allowed.`)
      return
    }

    const id = `${type}_${this.nextId++}`
    const position = this.getInsertPosition(options.position)
    this.state.nodes.push({
      id,
      type,
      attrs: this.normalizeNodeAttrs({ label: id }, type, id),
      x: position.x,
      y: position.y,
    })
    this.selectedNodeId = id
    this.sync({ writeDot: true, canonicalize: true })
  },

  sync(options = {}) {
    const writeDot = options.writeDot !== false
    const canonicalize = options.canonicalize === true
    this.positionDiamondAnchors()
    this.resolveNodeOverlaps()
    this.renderNodes()
    this.renderEdges()
    this.renderWorkflowSummary()
    this.updateAddButtons()
    if (this.commandPaletteDialog?.open) this.refreshCommandPalette()
    if (writeDot) this.writeDot()
    if (canonicalize) this.analyzeDot(this.getDraftDot(), { preservePositions: true, fit: false })
  },

  syncFromDotInput() {
    const dotText = this.dotEl?.value || ""
    this.analyzeDot(dotText, { preservePositions: true, fit: true })
  },

  toggleConnectMode(force = null) {
    this.connectMode = force === null ? !this.connectMode : !!force
    this.pendingSource = null
    if (this.connectBtn) {
      this.connectBtn.dataset.active = this.connectMode ? "true" : "false"
      this.connectBtn.textContent = this.connectMode ? "Adding Edges..." : "Add Edges"
    }
  },

  fitView() {
    this.fitNodesInViewport()
    this.sync({ writeDot: true, canonicalize: false })
  },

  bindPanelToggles() {
    const toggleLeft = () => {
      this.leftCollapsed = !this.leftCollapsed
      this.applyPanelState()
    }

    const toggleRight = () => {
      this.rightCollapsed = !this.rightCollapsed
      this.applyPanelState()
    }

    this.toggleLeftBtn?.addEventListener("click", toggleLeft)
    this.toggleLeftCenterBtn?.addEventListener("click", toggleLeft)
    this.toggleRightBtn?.addEventListener("click", toggleRight)
    this.toggleRightCenterBtn?.addEventListener("click", toggleRight)
    this.applyPanelState()
  },

  applyPanelState() {
    if (!this.shellEl) return
    this.shellEl.classList.toggle("left-collapsed", this.leftCollapsed)
    this.shellEl.classList.toggle("right-collapsed", this.rightCollapsed)

    const leftText = this.leftCollapsed ? "Show Left" : "Hide Left"
    const rightText = this.rightCollapsed ? "Show Right" : "Hide Right"

    if (this.toggleLeftBtn) this.toggleLeftBtn.textContent = leftText
    if (this.toggleLeftCenterBtn) this.toggleLeftCenterBtn.textContent = leftText
    if (this.toggleRightBtn) this.toggleRightBtn.textContent = rightText
    if (this.toggleRightCenterBtn) this.toggleRightCenterBtn.textContent = rightText
  },

  renderWorkflowSummary() {
    if (!this.summaryEl) return

    const graphLabel = this.state.graphAttrs?.label || "attractor"
    const graphGoal = this.state.graphAttrs?.goal || "No goal set yet."
    const edgeLines = this.state.edges.map((edge) => {
      const detail =
        edge.attrs?.status ? ` when ${edge.attrs.status}` : edge.attrs?.condition ? ` if ${edge.attrs.condition}` : ""
      return `From ${edge.from}, go to ${edge.to}${detail}.`
    })

    const sectionDetails = this.state.nodes.map((node) => {
      const label = node.attrs?.label || node.id
      if (node.type === "tool") {
        const cmd = node.attrs?.tool_command || "No command set"
        return `${label}: this section outputs/runs: ${cmd}`
      }

      if (node.type === "start") return `${label}: this section starts the workflow.`
      if (node.type === "exit") return `${label}: this section finishes the workflow.`
      if (node.type === "wait.human") return `${label}: this section waits for a human choice.`
      if (node.type === "wait_for_human") return `${label}: this section waits for a human choice.`
      if (node.type === "conditional") return `${label}: this section checks conditions to choose a path.`
      if (node.type === "parallel") return `${label}: this section runs multiple paths at the same time.`
      if (node.type === "parallel.fan_in") return `${label}: this section combines results from parallel paths.`
      if (node.type === "stack.manager_loop") return `${label}: this section supervises looped child work.`

      return `${label}: this section runs an LLM/codergen step.`
    })

    const headerLines = [
      `Workflow: ${this.escapeHtml(graphLabel)}`,
      `Goal: ${this.escapeHtml(graphGoal)}`,
    ]

    this.summaryEl.innerHTML = `
      <div class="builder-summary">
        <div class="builder-summary-meta">
          ${headerLines.map((line) => `<p>${line}</p>`).join("")}
        </div>
        <div class="builder-summary-block">
          <p class="builder-summary-title">Flow in plain speak:</p>
          <div class="builder-summary-lines">
            ${
              edgeLines.map((line) => `<p>${this.escapeHtml(line)}</p>`).join("") ||
              "<p>No edges yet.</p>"
            }
          </div>
        </div>
        <div class="builder-summary-block">
          <p class="builder-summary-title">What each section does:</p>
          <div class="builder-summary-lines">
            ${
              sectionDetails.map((line) => `<p>${this.escapeHtml(line)}</p>`).join("") ||
              "<p>No sections yet.</p>"
            }
          </div>
        </div>
      </div>
    `
  },

  positionDiamondAnchors() {
    if (!this.state?.nodes?.length) return
    const start = this.state.nodes.find((node) => node.type === "start")
    const done = this.state.nodes.find((node) => node.type === "exit")
    const others = this.state.nodes.filter((node) => node !== start && node !== done)
    if (!start || !done || others.length === 0) return

    const minX = Math.min(...others.map((node) => node.x))
    const maxX = Math.max(...others.map((node) => node.x))
    const centerX = Math.round(((minX + maxX) / 2) / GRID_SIZE) * GRID_SIZE
    const minY = Math.min(...others.map((node) => node.y))
    const maxY = Math.max(...others.map((node) => node.y))

    start.x = centerX
    start.y = Math.max(0, minY - 140)
    done.x = centerX
    done.y = maxY + 140
    this.clampNodeToViewport(start)
    this.clampNodeToViewport(done)
  },

  resolveNodeOverlaps() {
    if (!this.state?.nodes?.length) return

    const spacingX = NODE_WIDTH + GRID_SIZE * 2
    const spacingY = NODE_HEIGHT + GRID_SIZE * 2
    const protectedIds = new Set(
      this.state.nodes.filter((node) => node.type === "start" || node.type === "exit").map((node) => node.id)
    )

    for (let pass = 0; pass < 8; pass++) {
      let movedAny = false

      for (let i = 0; i < this.state.nodes.length; i++) {
        for (let j = i + 1; j < this.state.nodes.length; j++) {
          const a = this.state.nodes[i]
          const b = this.state.nodes[j]

          const overlapX = Math.abs(a.x - b.x) < NODE_WIDTH
          const overlapY = Math.abs(a.y - b.y) < NODE_HEIGHT
          if (!overlapX || !overlapY) continue

          let mover = b
          if (protectedIds.has(b.id) && !protectedIds.has(a.id)) mover = a

          mover.y += spacingY
          this.clampNodeToViewport(mover)

          // If clamping pinned the node in-place, push sideways instead.
          if (Math.abs(mover.y - a.y) < NODE_HEIGHT && Math.abs(mover.y - b.y) < NODE_HEIGHT) {
            mover.x += spacingX
            this.clampNodeToViewport(mover)
          }

          movedAny = true
        }
      }

      if (!movedAny) break
    }
  },

  escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;")
  },

  renderNodes() {
    this.canvas.innerHTML = ""
    for (const node of this.state.nodes) {
      const el = document.createElement("div")
      el.className = `builder-node builder-node-${node.type}`
      if (node.id === this.selectedNodeId) el.classList.add("builder-node-selected")
      el.dataset.id = node.id
      const displayLabel = (node.attrs?.label || node.id).trim()
      el.style.left = `${node.x}px`
      el.style.top = `${node.y}px`

      const label = document.createElement("button")
      label.type = "button"
      label.className = "builder-node-label"
      label.textContent = displayLabel === node.id ? node.id : `${node.id} (${displayLabel})`

      const deleteBtn = document.createElement("button")
      deleteBtn.type = "button"
      deleteBtn.className = "builder-node-delete"
      deleteBtn.setAttribute("aria-label", `Delete node ${node.id}`)
      deleteBtn.textContent = "x"

      label.addEventListener("mousedown", (event) => {
        if (this.connectMode) {
          this.beginEdgeDrag(event, node.id)
        } else {
          this.startDrag(event, node.id)
        }
      })
      label.addEventListener("mouseup", (event) => this.completeEdgeDrag(event, node.id))
      label.addEventListener("click", () => this.handleNodeClick(node.id))
      label.addEventListener("dblclick", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.openNodeProperties(node.id)
      })
      deleteBtn.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.deleteNode(node.id)
      })
      deleteBtn.addEventListener("mousedown", (event) => {
        event.preventDefault()
        event.stopPropagation()
      })
      deleteBtn.addEventListener("mouseup", (event) => {
        event.preventDefault()
        event.stopPropagation()
      })

      el.appendChild(label)
      el.appendChild(deleteBtn)

      this.canvas.appendChild(el)
    }
  },

  beginEdgeDrag(event, nodeId) {
    if (!this.connectMode) return
    event.preventDefault()
    event.stopPropagation()

    const sourceNode = this.state.nodes.find((node) => node.id === nodeId)
    if (!sourceNode) return

    this.edgeDragSource = nodeId

    const line = document.createElementNS("http://www.w3.org/2000/svg", "line")
    line.classList.add("builder-edge-preview")
    line.setAttribute("x1", `${sourceNode.x + 64}`)
    line.setAttribute("y1", `${sourceNode.y + 20}`)
    line.setAttribute("x2", `${sourceNode.x + 64}`)
    line.setAttribute("y2", `${sourceNode.y + 20}`)
    this.edgesSvg.appendChild(line)
    this.edgeDragLine = line

    this.boundEdgeDragMove = (moveEvent) => this.updateEdgeDrag(moveEvent)
    this.boundEdgeDragEnd = () => this.cancelEdgeDrag()
    window.addEventListener("mousemove", this.boundEdgeDragMove)
    window.addEventListener("mouseup", this.boundEdgeDragEnd, { once: true })
  },

  updateEdgeDrag(event) {
    if (!this.edgeDragLine || !this.edgesSvg) return
    const rect = this.edgesSvg.getBoundingClientRect()
    this.edgeDragLine.setAttribute("x2", `${event.clientX - rect.left}`)
    this.edgeDragLine.setAttribute("y2", `${event.clientY - rect.top}`)
  },

  completeEdgeDrag(event, targetId) {
    if (!this.connectMode || !this.edgeDragSource) return
    event.preventDefault()
    event.stopPropagation()

    if (targetId && targetId !== this.edgeDragSource) {
      this.addEdge(this.edgeDragSource, targetId, { openDialog: true })
      this.sync({ writeDot: true, canonicalize: true })
    }

    this.cancelEdgeDrag()
  },

  cancelEdgeDrag() {
    if (this.boundEdgeDragMove) {
      window.removeEventListener("mousemove", this.boundEdgeDragMove)
    }

    if (this.edgeDragLine) {
      this.edgeDragLine.remove()
    }

    this.edgeDragLine = null
    this.edgeDragSource = null
    this.boundEdgeDragMove = null
    this.boundEdgeDragEnd = null
  },

  renderEdges() {
    const existing = this.edgesSvg.querySelectorAll("line.builder-edge")
    existing.forEach((line) => line.remove())

    for (const [edgeIndex, edge] of this.state.edges.entries()) {
      const from = this.state.nodes.find((node) => node.id === edge.from)
      const to = this.state.nodes.find((node) => node.id === edge.to)
      if (!from || !to) continue

      const line = document.createElementNS("http://www.w3.org/2000/svg", "line")
      line.classList.add("builder-edge")
      line.setAttribute("x1", `${from.x + 64}`)
      line.setAttribute("y1", `${from.y + 20}`)
      line.setAttribute("x2", `${to.x + 64}`)
      line.setAttribute("y2", `${to.y + 20}`)
      line.setAttribute("marker-end", "url(#builder-arrow)")
      line.dataset.edgeIndex = `${edgeIndex}`
      line.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.openEdgeProperties(edgeIndex)
      })
      this.edgesSvg.appendChild(line)
    }
  },

  startDrag(event, nodeId) {
    if (this.connectMode) return
    event.preventDefault()

    const node = this.state.nodes.find((entry) => entry.id === nodeId)
    if (!node) return

    const startX = event.clientX
    const startY = event.clientY
    const nodeX = node.x
    const nodeY = node.y

    const move = (moveEvent) => {
      const dx = moveEvent.clientX - startX
      const dy = moveEvent.clientY - startY
      node.x = Math.round((nodeX + dx) / GRID_SIZE) * GRID_SIZE
      node.y = Math.round((nodeY + dy) / GRID_SIZE) * GRID_SIZE
      this.clampNodeToViewport(node)
      this.sync({ writeDot: false })
    }

    const up = () => {
      window.removeEventListener("mousemove", move)
      window.removeEventListener("mouseup", up)
    }

    window.addEventListener("mousemove", move)
    window.addEventListener("mouseup", up)
  },

  handleNodeClick(nodeId) {
    this.selectedNodeId = nodeId

    if (!this.connectMode) return

    if (!this.pendingSource) {
      this.pendingSource = nodeId
      return
    }

    if (this.pendingSource !== nodeId) {
      this.addEdge(this.pendingSource, nodeId, { openDialog: true })
    }

    this.pendingSource = null
    this.sync({ writeDot: true, canonicalize: true })
  },

  writeDot() {
    const lines = []
    lines.push("digraph attractor {")

    const graphLine = this.serializeAttrLine("graph", this.state.graphAttrs || {})
    if (graphLine) lines.push(`  ${graphLine}`)

    this.state.nodes.forEach((node) => {
      const attrs = this.buildNodeAttrMap(node)
      lines.push(`  ${node.id} [${this.serializeAttrs(attrs)}]`)
    })

    lines.push("")
    this.state.edges.forEach((edge) => {
      const attrs = this.sanitizeEdgeAttrs(edge.attrs || {})
      const serialized = this.serializeAttrs(attrs)
      if (serialized) {
        lines.push(`  ${edge.from} -> ${edge.to} [${serialized}]`)
      } else {
        lines.push(`  ${edge.from} -> ${edge.to}`)
      }
    })
    lines.push("}")

    this.dotEl.value = lines.join("\n")
    this.lastExternalDotValue = this.dotEl.value
  },

  getDraftDot() {
    this.writeDot()
    return this.dotEl?.value || ""
  },

  buildNodeAttrMap(node) {
    const attrs = this.sanitizeNodeAttrs(node.attrs, node.type, node.id)
    const shape = NODE_TYPE_TO_SHAPE[node.type] || "box"
    const impliedType = this.typeFromShape(shape)
    attrs.shape = shape
    attrs.label = attrs.label || node.id
    if (node.type && node.type !== impliedType) attrs.type = node.type
    if (node.type === "tool") attrs.tool_command = attrs.tool_command || "echo hello world"
    if (node.type === "exit") delete attrs.type
    if (node.type === "start") delete attrs.type
    if (node.type !== "tool") delete attrs.tool_command
    return this.cleanEmptyAttrs(attrs)
  },

  serializeAttrLine(prefix, attrs) {
    const serialized = this.serializeAttrs(this.cleanEmptyAttrs({ ...(attrs || {}) }))
    return serialized ? `${prefix} [${serialized}]` : ""
  },

  serializeAttrs(attrs) {
    const entries = Object.entries(attrs || {})
    if (entries.length === 0) return ""
    return entries
      .map(([key, value]) => `${key}=${this.serializeAttrValue(value)}`)
      .join(", ")
  },

  serializeAttrValue(value) {
    if (typeof value === "boolean") return value ? "true" : "false"
    if (typeof value === "number") return `${value}`
    const asString = `${value}`
    if (/^-?\d+(\.\d+)?$/.test(asString)) return asString
    return `"${asString.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`
  },

  cleanEmptyAttrs(attrs) {
    return Object.fromEntries(
      Object.entries(attrs || {}).filter(([_, value]) => value !== "" && value !== null && value !== undefined)
    )
  },

  boolAttr(value) {
    if (value === true) return true
    if (typeof value === "string") return value.toLowerCase() === "true"
    return false
  },

  isNumberString(value) {
    return /^-?\d+(\.\d+)?$/.test(`${value}`.trim())
  },

  fitNodesInViewport() {
    if (!this.canvas || this.state.nodes.length === 0) return

    const width = Math.max(this.canvas.clientWidth, NODE_WIDTH + VIEWPORT_PADDING * 2)
    const height = Math.max(this.canvas.clientHeight, NODE_HEIGHT + VIEWPORT_PADDING * 2)

    const minX = Math.min(...this.state.nodes.map((node) => node.x))
    const minY = Math.min(...this.state.nodes.map((node) => node.y))
    const maxX = Math.max(...this.state.nodes.map((node) => node.x + NODE_WIDTH))
    const maxY = Math.max(...this.state.nodes.map((node) => node.y + NODE_HEIGHT))

    const boundsW = Math.max(1, maxX - minX)
    const boundsH = Math.max(1, maxY - minY)
    const availW = Math.max(1, width - VIEWPORT_PADDING * 2)
    const availH = Math.max(1, height - VIEWPORT_PADDING * 2)
    const scale = Math.min(1, availW / boundsW, availH / boundsH)

    this.state.nodes.forEach((node) => {
      node.x = Math.round((node.x - minX) * scale + VIEWPORT_PADDING)
      node.y = Math.round((node.y - minY) * scale + VIEWPORT_PADDING)
      this.clampNodeToViewport(node)
    })
  },

  clampNodeToViewport(node) {
    if (!this.canvas) return

    const maxX = Math.max(0, this.canvas.clientWidth - NODE_WIDTH)
    const maxY = Math.max(0, this.canvas.clientHeight - NODE_HEIGHT)
    node.x = Math.min(Math.max(0, node.x), maxX)
    node.y = Math.min(Math.max(0, node.y), maxY)
  },

  openNodeProperties(nodeId) {
    if (!this.propsDialog) return
    const node = this.state.nodes.find((entry) => entry.id === nodeId)
    if (!node) return

    this.selectedNodeId = nodeId
    const attrs = node.attrs || {}
    this.currentEditingNodeId = nodeId
    this.propId.value = node.id
    this.propLabel.value = attrs.label || node.id
    this.propType.value = node.type
    this.propPrompt.value = attrs.prompt || ""
    this.propClass.value = attrs.class || ""
    this.propTimeout.value = attrs.timeout || ""
    this.propMaxRetries.value = attrs.max_retries || ""
    this.propGoalGate.checked = this.boolAttr(attrs.goal_gate)
    this.populateNodeTargetSelects(node.id, attrs.retry_target || "", attrs.fallback_retry_target || "")
    this.propFidelity.value = attrs.fidelity || ""
    this.propThreadId.value = attrs.thread_id || ""
    this.propLlmModel.value = attrs.llm_model || ""
    this.propLlmProvider.value = attrs.llm_provider || ""
    this.propReasoningEffort.value = attrs.reasoning_effort || ""
    this.propMaxTokens.value = attrs.max_tokens || ""
    this.propTemperature.value = attrs.temperature || ""
    this.propHumanDefaultChoice.value = attrs["human.default_choice"] || ""
    this.propHumanTimeout.value = attrs["human.timeout"] || ""
    this.propHumanInput.value = attrs["human.input"] || ""
    this.propHumanMultiple.checked = this.boolAttr(attrs["human.multiple"])
    this.propHumanRequired.checked = this.boolAttr(attrs["human.required"])
    this.propJoinPolicy.value = attrs.join_policy || ""
    this.propMaxParallel.value = attrs.max_parallel || ""
    this.propK.value = attrs.k || ""
    this.propQuorumRatio.value = attrs.quorum_ratio || ""
    this.propManagerActions.value = attrs["manager.actions"] || ""
    this.propManagerMaxCycles.value = attrs["manager.max_cycles"] || ""
    this.propManagerPollInterval.value = attrs["manager.poll_interval"] || ""
    this.propManagerStopCondition.value = attrs["manager.stop_condition"] || ""
    this.propStackChildAutostart.checked = this.boolAttr(attrs["stack.child_autostart"])
    this.propAutoStatus.checked = this.boolAttr(attrs.auto_status)
    this.propAllowPartial.checked = this.boolAttr(attrs.allow_partial)
    this.propCommand.value = attrs.tool_command || attrs.command || "echo hello world"
    this.applyNodeTypeVisibility()
    this.renderEdgesEditor(node.id)
    this.propsDialog.showModal()
  },

  applyNodeTypeVisibility() {
    if (!this.propType) return

    const type = this.propType.value
    const visible = new Set(NODE_FIELDS_BY_TYPE[type] || NODE_FIELDS_BY_TYPE.codergen)

    if (type !== "exit") visible.add("edges")

    Object.entries(this.nodeFieldWraps || {}).forEach(([key, element]) => {
      if (!element) return
      element.style.display = visible.has(key) ? "" : "none"
    })
  },

  saveNodeProperties() {
    if (!this.currentEditingNodeId) return
    const node = this.state.nodes.find((entry) => entry.id === this.currentEditingNodeId)
    if (!node) return

    const oldId = node.id
    const newIdRaw = (this.propId?.value || "").trim()
    const newId = newIdRaw.replace(/[^A-Za-z0-9_]/g, "_")
    if (!newId) return

    const duplicate = this.state.nodes.some(
      (entry) => entry.id === newId && entry.id !== this.currentEditingNodeId
    )

    if (duplicate) return

    const requestedType = this.propType?.value || node.type
    if (
      (requestedType === "start" || requestedType === "exit") &&
      this.state.nodes.some((entry) => entry.id !== node.id && entry.type === requestedType)
    ) {
      window.alert(`Only one ${requestedType} node is allowed.`)
      return
    }

    if (newId !== this.currentEditingNodeId) {
      this.state.edges = this.state.edges.map((edge) => ({
        from: edge.from === this.currentEditingNodeId ? newId : edge.from,
        to: edge.to === this.currentEditingNodeId ? newId : edge.to,
        attrs: { ...(edge.attrs || {}) },
      }))
      node.id = newId
      this.currentEditingNodeId = newId
    }

    const inputLabel = (this.propLabel?.value || "").trim()
    const label = inputLabel === "" || inputLabel === oldId ? node.id : inputLabel

    node.type = requestedType
    node.attrs = this.sanitizeNodeAttrs(this.readNodePropertyAttrs(label, requestedType), requestedType, node.id)

    this.fitNodesInViewport()
    this.sync({ writeDot: true, canonicalize: true })
    this.propsDialog?.close()
  },

  deleteCurrentNode() {
    if (!this.currentEditingNodeId) return
    this.deleteNode(this.currentEditingNodeId)
    this.propsDialog?.close()
  },

  deleteNode(nodeId) {
    const nodeIndex = this.state.nodes.findIndex((entry) => entry.id === nodeId)
    if (nodeIndex === -1) return

    this.state.nodes.splice(nodeIndex, 1)
    this.state.edges = this.state.edges.filter((edge) => edge.from !== nodeId && edge.to !== nodeId)

    this.state.nodes.forEach((node) => {
      if (node.attrs?.retry_target === nodeId) delete node.attrs.retry_target
      if (node.attrs?.fallback_retry_target === nodeId) delete node.attrs.fallback_retry_target
    })

    if (this.state.graphAttrs?.retry_target === nodeId) delete this.state.graphAttrs.retry_target
    if (this.state.graphAttrs?.fallback_retry_target === nodeId) {
      delete this.state.graphAttrs.fallback_retry_target
    }

    if (this.currentEditingNodeId === nodeId) this.currentEditingNodeId = null
    if (this.reopenNodePropertiesId === nodeId) this.reopenNodePropertiesId = null
    if (this.selectedNodeId === nodeId) this.selectedNodeId = null
    if (this.edgeDragSource === nodeId) this.cancelEdgeDrag()
    this.sync({ writeDot: true, canonicalize: true })
  },

  readNodePropertyAttrs(label, nodeType) {
    return this.cleanEmptyAttrs({
      label,
      prompt: (this.propPrompt?.value || "").trim(),
      class: (this.propClass?.value || "").trim(),
      timeout: (this.propTimeout?.value || "").trim(),
      max_retries: (this.propMaxRetries?.value || "").trim(),
      goal_gate: this.propGoalGate?.checked ? true : "",
      retry_target: (this.propRetryTarget?.value || "").trim(),
      fallback_retry_target: (this.propFallbackRetryTarget?.value || "").trim(),
      fidelity: (this.propFidelity?.value || "").trim(),
      thread_id: (this.propThreadId?.value || "").trim(),
      llm_model: (this.propLlmModel?.value || "").trim(),
      llm_provider: (this.propLlmProvider?.value || "").trim(),
      reasoning_effort: (this.propReasoningEffort?.value || "").trim(),
      max_tokens: (this.propMaxTokens?.value || "").trim(),
      temperature: (this.propTemperature?.value || "").trim(),
      tool_command: nodeType === "tool" ? (this.propCommand?.value || "echo hello world").trim() || "echo hello world" : "",
      auto_status: this.propAutoStatus?.checked ? true : "",
      allow_partial: this.propAllowPartial?.checked ? true : "",
      "human.default_choice": (this.propHumanDefaultChoice?.value || "").trim(),
      "human.timeout": (this.propHumanTimeout?.value || "").trim(),
      "human.input": (this.propHumanInput?.value || "").trim(),
      "human.multiple": this.propHumanMultiple?.checked ? true : "",
      "human.required": this.propHumanRequired?.checked ? true : "",
      join_policy: (this.propJoinPolicy?.value || "").trim(),
      max_parallel: (this.propMaxParallel?.value || "").trim(),
      k: (this.propK?.value || "").trim(),
      quorum_ratio: (this.propQuorumRatio?.value || "").trim(),
      "manager.actions": (this.propManagerActions?.value || "").trim(),
      "manager.max_cycles": (this.propManagerMaxCycles?.value || "").trim(),
      "manager.poll_interval": (this.propManagerPollInterval?.value || "").trim(),
      "manager.stop_condition": (this.propManagerStopCondition?.value || "").trim(),
      "stack.child_autostart": this.propStackChildAutostart?.checked ? true : "",
    })
  },

  populateNodeTargetSelects(nodeId, retryTarget, fallbackRetryTarget) {
    const options = this.state.nodes
      .filter((node) => node.id !== nodeId)
      .map((node) => node.id)

    this.populateSelect(this.propRetryTarget, options, retryTarget, "(none)")
    this.populateSelect(this.propFallbackRetryTarget, options, fallbackRetryTarget, "(none)")
  },

  populateSelect(selectEl, values, selectedValue, emptyLabel = "(default)") {
    if (!selectEl) return

    const options = [`<option value="">${emptyLabel}</option>`]
    values.forEach((value) => {
      const selected = value === selectedValue ? "selected" : ""
      options.push(`<option value="${this.escapeHtml(value)}" ${selected}>${this.escapeHtml(value)}</option>`)
    })
    selectEl.innerHTML = options.join("")
    selectEl.value = selectedValue || ""
  },

  addEdge(fromId, toId, options = {}) {
    const { openDialog = false, reopenNodeId = null } = options
    let edgeIndex = this.state.edges.findIndex((edge) => edge.from === fromId && edge.to === toId)

    if (edgeIndex === -1) {
      this.state.edges.push({ from: fromId, to: toId, attrs: {} })
      edgeIndex = this.state.edges.length - 1
    }

    if (openDialog) this.openEdgeProperties(edgeIndex, { reopenNodeId })
    return edgeIndex
  },

  renderEdgesEditor(nodeId) {
    if (!this.propEdgesList) return
    this.propEdgesList.innerHTML = ""

    const outgoing = this.state.edges
      .map((edge, index) => ({ edge, index }))
      .filter(({ edge }) => edge.from === nodeId)

    if (outgoing.length === 0) {
      this.propEdgesList.innerHTML = `
        <div class="rounded border border-dashed border-base-300 px-3 py-2 text-xs text-base-content/60">
          No outgoing edges yet.
        </div>
      `
      return
    }

    outgoing.forEach(({ edge, index }) => {
      const row = document.createElement("div")
      row.className = "flex items-center justify-between gap-3 rounded border border-base-300 p-2"
      row.innerHTML = `
        <div class="min-w-0">
          <div class="text-xs font-semibold">${this.escapeHtml(edge.from)} -&gt; ${this.escapeHtml(edge.to)}</div>
          <div class="text-[11px] text-base-content/60">${this.escapeHtml(this.describeEdgeRule(edge.attrs || {}))}</div>
        </div>
        <div class="flex items-center gap-2">
          <button type="button" class="builder-btn edge-edit">Edit Edge</button>
          <button type="button" class="builder-btn edge-remove">Remove</button>
        </div>
      `

      row.querySelector(".edge-edit")?.addEventListener("click", () => {
        this.openEdgeProperties(index, { reopenNodeId: nodeId })
      })
      row.querySelector(".edge-remove")?.addEventListener("click", () => {
        this.removeEdge(index, { sync: true })
        this.renderEdgesEditor(nodeId)
      })

      this.propEdgesList.appendChild(row)
    })
  },

  startEdgeFromNodeDialog() {
    if (!this.currentEditingNodeId) return
    const availableTargets = this.state.nodes.filter((node) => node.id !== this.currentEditingNodeId)
    if (availableTargets.length === 0) return
    const edgeIndex = this.addEdge(this.currentEditingNodeId, availableTargets[0].id)
    this.sync({ writeDot: false })
    this.openEdgeProperties(edgeIndex, { reopenNodeId: this.currentEditingNodeId })
  },

  openEdgeProperties(edgeIndex, options = {}) {
    if (!this.edgeDialog) return
    const edge = this.state.edges[edgeIndex]
    if (!edge) return

    this.currentEditingEdgeIndex = edgeIndex
    this.reopenNodePropertiesId = options.reopenNodeId || null

    this.populateEdgeSourceOptions(edge.from)
    this.populateEdgeTargetOptions(edge.to)

    const attrs = edge.attrs || {}
    const edgeCondition = (attrs.condition || "").trim().toLowerCase()
    const shorthandStatus = STATUS_VALUES.includes(edgeCondition) ? edgeCondition : ""
    const mode = shorthandStatus ? "status" : attrs.condition ? "condition" : attrs.status ? "status" : "default"

    this.edgePropMode.value = mode
    this.edgePropValue.value = shorthandStatus ? "" : attrs.condition || ""
    this.edgePropStatus.value = attrs.status || shorthandStatus || "success"
    this.edgePropLabel.value = attrs.label || ""
    this.edgePropWeight.value = attrs.weight || ""
    this.edgePropFidelity.value = attrs.fidelity || ""
    this.edgePropThreadId.value = attrs.thread_id || ""
    this.edgePropLoopRestart.checked = this.boolAttr(attrs.loop_restart)
    this.updateEdgeDialogValueVisibility()

    if (this.propsDialog?.open) this.propsDialog.close()
    this.edgeDialog.showModal()
  },

  populateEdgeSourceOptions(selectedValue) {
    const options = this.state.nodes.map((node) => node.id)
    this.populateSelect(this.edgePropSource, options, selectedValue, "(select source)")
  },

  populateEdgeTargetOptions(selectedValue = "") {
    if (!this.edgePropTarget) return
    const sourceValue = this.edgePropSource?.value || ""
    const options = this.state.nodes.filter((node) => node.id !== sourceValue).map((node) => node.id)
    const nextSelected = options.includes(selectedValue) ? selectedValue : options[0] || ""
    this.populateSelect(this.edgePropTarget, options, nextSelected, "(select target)")
  },

  updateEdgeDialogValueVisibility() {
    const mode = this.edgePropMode?.value || "default"
    if (this.edgePropStatusWrap) this.edgePropStatusWrap.style.display = mode === "status" ? "" : "none"
    if (this.edgePropValueWrap) this.edgePropValueWrap.style.display = mode === "condition" ? "" : "none"
    if (this.edgePropValue) {
      this.edgePropValue.placeholder = mode === "condition" ? 'ex: outcome.status == "fail"' : ""
    }
  },

  saveEdgeProperties() {
    if (this.currentEditingEdgeIndex === null) return
    const edge = this.state.edges[this.currentEditingEdgeIndex]
    if (!edge) return

    const from = (this.edgePropSource?.value || "").trim()
    const to = (this.edgePropTarget?.value || "").trim()
    if (!from || !to || from === to) {
      window.alert("Edge source and target must be different nodes.")
      return
    }

    const duplicate = this.state.edges.some(
      (entry, index) => index !== this.currentEditingEdgeIndex && entry.from === from && entry.to === to
    )
    if (duplicate) {
      window.alert("An edge between those nodes already exists.")
      return
    }

    const mode = this.edgePropMode?.value || "default"
    edge.from = from
    edge.to = to
    edge.attrs = this.sanitizeEdgeAttrs(
      this.cleanEmptyAttrs({
        label: (this.edgePropLabel?.value || "").trim(),
        weight: (this.edgePropWeight?.value || "").trim(),
        fidelity: (this.edgePropFidelity?.value || "").trim(),
        thread_id: (this.edgePropThreadId?.value || "").trim(),
        loop_restart: this.edgePropLoopRestart?.checked ? true : "",
        status: mode === "status" ? (this.edgePropStatus?.value || "success").trim() : "",
        condition: mode === "condition" ? ((this.edgePropValue?.value || "").trim() || "true") : "",
      })
    )

    this.sync({ writeDot: true, canonicalize: true })
    this.edgeDialog?.close()
  },

  deleteCurrentEdge() {
    if (this.currentEditingEdgeIndex === null) return
    this.removeEdge(this.currentEditingEdgeIndex, { sync: true, reopenNodeId: this.reopenNodePropertiesId })
    this.edgeDialog?.close()
  },

  removeEdge(edgeIndex, options = {}) {
    const { sync = true, reopenNodeId = null } = options
    if (edgeIndex < 0 || edgeIndex >= this.state.edges.length) return
    this.state.edges.splice(edgeIndex, 1)
    this.currentEditingEdgeIndex = null
    this.reopenNodePropertiesId = reopenNodeId
    if (sync) this.sync({ writeDot: true, canonicalize: true })
  },

  handleEdgeDialogClose() {
    const reopenNodeId = this.reopenNodePropertiesId
    this.currentEditingEdgeIndex = null
    this.reopenNodePropertiesId = null
    if (reopenNodeId) this.openNodeProperties(reopenNodeId)
  },

  describeEdgeRule(attrs = {}) {
    if (attrs.status) return `status = ${attrs.status}`
    if (attrs.condition) return `condition = ${attrs.condition}`
    return "default route"
  },

  hasType(type) {
    return this.state.nodes.some((node) => node.type === type)
  },

  updateAddButtons() {
    if (this.addStartBtn) this.addStartBtn.disabled = this.hasType("start")
    if (this.addEndBtn) this.addEndBtn.disabled = this.hasType("exit")
  },
}

export { PipelineBuilder }
