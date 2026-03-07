const GRID_SIZE = 20
const NODE_WIDTH = 128
const NODE_HEIGHT = 40
const VIEWPORT_PADDING = 24
const STATUS_VALUES = ["success", "fail", "retry", "partial_success"]
const NODE_TYPE_TO_SHAPE = {
  start: "Mdiamond",
  exit: "Msquare",
  codergen: "box",
  "wait.human": "hexagon",
  conditional: "diamond",
  parallel: "component",
  "parallel.fan_in": "tripleoctagon",
  tool: "parallelogram",
  "stack.manager_loop": "house",
}

const PipelineBuilder = {
  mounted() {
    this.dotEl = document.getElementById("pipeline-dot")
    this.canvas = document.getElementById("builder-canvas")
    this.edgesSvg = document.getElementById("builder-edges")

    if (!this.dotEl || !this.canvas || !this.edgesSvg) return

    this.state = this.parseDot(this.dotEl.value)
    this.connectMode = false
    this.pendingSource = null
    this.edgeDragSource = null
    this.edgeDragLine = null
    this.nextId = 1
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
    this.propAutoStatus = document.getElementById("node-prop-auto-status")
    this.propAllowPartial = document.getElementById("node-prop-allow-partial")
    this.propConnectionsList = document.getElementById("node-connections-list")
    this.propAddConnection = document.getElementById("node-prop-add-connection")
    this.currentEditingNodeId = null
    this.graphGoal = document.getElementById("graph-goal")
    this.graphLabel = document.getElementById("graph-label")
    this.graphModelStylesheet = document.getElementById("graph-model-stylesheet")
    this.graphDefaultMaxRetry = document.getElementById("graph-default-max-retry")
    this.graphDefaultFidelity = document.getElementById("graph-default-fidelity")
    this.graphRetryTarget = document.getElementById("graph-retry-target")
    this.graphFallbackRetryTarget = document.getElementById("graph-fallback-retry-target")
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
      command: document.getElementById("node-prop-wrap-command"),
      goalGate: document.getElementById("node-prop-wrap-goal-gate"),
      autoStatus: document.getElementById("node-prop-wrap-auto-status"),
      allowPartial: document.getElementById("node-prop-wrap-allow-partial"),
      connections: document.getElementById("node-prop-wrap-connections"),
    }

    this.addStartBtn?.addEventListener("click", () => this.addNode("start"))
    this.addToolBtn?.addEventListener("click", () => this.addNode("tool"))
    this.addEndBtn?.addEventListener("click", () => this.addNode("exit"))
    this.clearEdgesBtn?.addEventListener("click", () => {
      this.state.edges = []
      this.sync()
    })

    this.connectBtn?.addEventListener("click", () => {
      this.connectMode = !this.connectMode
      this.pendingSource = null
      this.connectBtn.dataset.active = this.connectMode ? "true" : "false"
      this.connectBtn.textContent = this.connectMode ? "Adding Edges..." : "Add Edges"
    })

    this.applyDotBtn?.addEventListener("click", () => {
      const parsed = this.parseDot(this.dotEl.value)
      this.state = parsed
      this.fitNodesInViewport()
      this.populateGraphFields()
      this.sync(false)
    })

    this.propType?.addEventListener("change", () => this.applyNodeTypeVisibility())
    this.propSave?.addEventListener("click", () => this.saveNodeProperties())
    this.propAddConnection?.addEventListener("click", () => this.addConnectionRow())
    this.bindGraphInputs()
    this.bindPanelToggles()

    this.dotEl.addEventListener("input", () => {
      window.clearTimeout(this.dotInputTimer)
      this.dotInputTimer = window.setTimeout(() => this.syncFromDotInput(), 180)
    })

    this.fitNodesInViewport()
    this.populateGraphFields()
    this.sync(false)
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
          const attrs = this.parseAttrs(edgeMatch[3] || "")
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
    const next = { ...(attrs || {}) }
    if (!next.label) next.label = id
    if (type === "tool" && !next.tool_command) next.tool_command = "echo hello world"
    return next
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
        this.writeDot()
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

  addNode(type) {
    if ((type === "start" || type === "exit") && this.hasType(type)) {
      window.alert(`Only one ${type} node is allowed.`)
      return
    }

    const id = `${type}_${this.nextId++}`
    this.state.nodes.push({
      id,
      type,
      attrs: this.normalizeNodeAttrs({ label: id }, type, id),
      x: 80 + this.state.nodes.length * 40,
      y: 60 + this.state.nodes.length * 30,
    })
    this.fitNodesInViewport()
    this.sync()
  },

  sync(writeDot = true) {
    this.positionDiamondAnchors()
    this.resolveNodeOverlaps()
    this.renderNodes()
    this.renderEdges()
    this.renderWorkflowSummary()
    this.updateAddButtons()
    if (writeDot) this.writeDot()
  },

  syncFromDotInput() {
    const dotText = this.dotEl?.value || ""
    const parsed = this.parseDot(dotText, { useFallback: false })

    // Ignore incomplete/partial DOT edits while the user is still typing.
    if (parsed.nodes.length === 0 && parsed.edges.length === 0) return

    this.state = {
      graphAttrs: parsed.graphAttrs || {},
      nodes: parsed.nodes || [],
      edges: parsed.edges || [],
    }
    this.fitNodesInViewport()
    this.populateGraphFields()
    this.sync(false)
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
      const el = document.createElement("button")
      el.type = "button"
      el.className = `builder-node builder-node-${node.type}`
      el.dataset.id = node.id
      const displayLabel = (node.attrs?.label || node.id).trim()
      el.textContent = displayLabel === node.id ? node.id : `${node.id} (${displayLabel})`
      el.style.left = `${node.x}px`
      el.style.top = `${node.y}px`

      el.addEventListener("mousedown", (event) => {
        if (this.connectMode) {
          this.beginEdgeDrag(event, node.id)
        } else {
          this.startDrag(event, node.id)
        }
      })
      el.addEventListener("mouseup", (event) => this.completeEdgeDrag(event, node.id))
      el.addEventListener("click", () => this.handleNodeClick(node.id))
      el.addEventListener("dblclick", (event) => {
        event.preventDefault()
        event.stopPropagation()
        this.openNodeProperties(node.id)
      })

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
      this.addEdge(this.edgeDragSource, targetId)
      this.sync()
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

    for (const edge of this.state.edges) {
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
      this.sync()
    }

    const up = () => {
      window.removeEventListener("mousemove", move)
      window.removeEventListener("mouseup", up)
    }

    window.addEventListener("mousemove", move)
    window.addEventListener("mouseup", up)
  },

  handleNodeClick(nodeId) {
    if (!this.connectMode) return

    if (!this.pendingSource) {
      this.pendingSource = nodeId
      return
    }

    if (this.pendingSource !== nodeId) {
      this.addEdge(this.pendingSource, nodeId)
    }

    this.pendingSource = null
    this.sync()
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
      const attrs = edge.attrs || {}
      const serialized = this.serializeAttrs(attrs)
      if (serialized) {
        lines.push(`  ${edge.from} -> ${edge.to} [${serialized}]`)
      } else {
        lines.push(`  ${edge.from} -> ${edge.to}`)
      }
    })
    lines.push("}")

    this.dotEl.value = lines.join("\n")
  },

  buildNodeAttrMap(node) {
    const attrs = { ...(node.attrs || {}) }
    const shape = NODE_TYPE_TO_SHAPE[node.type] || "box"
    attrs.shape = shape
    attrs.label = attrs.label || node.id
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
    this.propRetryTarget.value = attrs.retry_target || ""
    this.propFallbackRetryTarget.value = attrs.fallback_retry_target || ""
    this.propFidelity.value = attrs.fidelity || ""
    this.propThreadId.value = attrs.thread_id || ""
    this.propLlmModel.value = attrs.llm_model || ""
    this.propLlmProvider.value = attrs.llm_provider || ""
    this.propReasoningEffort.value = attrs.reasoning_effort || ""
    this.propAutoStatus.checked = this.boolAttr(attrs.auto_status)
    this.propAllowPartial.checked = this.boolAttr(attrs.allow_partial)
    this.propCommand.value = attrs.tool_command || "echo hello world"
    this.applyNodeTypeVisibility()
    this.renderConnectionsEditor(node.id)
    this.propsDialog.showModal()
  },

  applyNodeTypeVisibility() {
    if (!this.propType) return

    const type = this.propType.value
    const visible = new Set(["id", "label", "type", "class", "timeout"])

    if (type === "tool") {
      ;[
        "command",
        "maxRetries",
        "goalGate",
        "retryTarget",
        "fallbackRetryTarget",
        "fidelity",
        "threadId",
        "autoStatus",
        "allowPartial",
      ].forEach((field) => visible.add(field))
    }

    if (type === "codergen") {
      ;[
        "prompt",
        "maxRetries",
        "goalGate",
        "retryTarget",
        "fallbackRetryTarget",
        "fidelity",
        "threadId",
        "llmModel",
        "llmProvider",
        "reasoningEffort",
        "autoStatus",
        "allowPartial",
      ].forEach((field) => visible.add(field))
    }

    if (type === "wait.human") {
      ;["fidelity", "threadId", "retryTarget", "fallbackRetryTarget"].forEach((field) =>
        visible.add(field)
      )
    }

    if (type === "parallel" || type === "parallel.fan_in" || type === "stack.manager_loop" || type === "conditional") {
      ;["fidelity", "threadId"].forEach((field) => visible.add(field))
    }

    if (type !== "exit") {
      visible.add("connections")
    }

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

    node.type = this.propType?.value || node.type
    node.attrs = this.cleanEmptyAttrs({
      ...(node.attrs || {}),
      label,
      prompt: (this.propPrompt?.value || "").trim(),
      max_retries: (this.propMaxRetries?.value || "").trim(),
      goal_gate: this.propGoalGate?.checked ? true : "",
      retry_target: (this.propRetryTarget?.value || "").trim(),
      fallback_retry_target: (this.propFallbackRetryTarget?.value || "").trim(),
      fidelity: (this.propFidelity?.value || "").trim(),
      thread_id: (this.propThreadId?.value || "").trim(),
      class: (this.propClass?.value || "").trim(),
      timeout: (this.propTimeout?.value || "").trim(),
      llm_model: (this.propLlmModel?.value || "").trim(),
      llm_provider: (this.propLlmProvider?.value || "").trim(),
      reasoning_effort: (this.propReasoningEffort?.value || "").trim(),
      auto_status: this.propAutoStatus?.checked ? true : "",
      allow_partial: this.propAllowPartial?.checked ? true : "",
      tool_command:
        node.type === "tool"
          ? (this.propCommand?.value || "echo hello world").trim() || "echo hello world"
          : "",
    })

    const updatedConnections = this.readConnectionRows().map((connection) => ({
      from: node.id,
      to: connection.to,
      attrs: connection.attrs,
    }))

    this.state.edges = this.state.edges.filter((edge) => edge.from !== node.id).concat(updatedConnections)

    this.fitNodesInViewport()
    this.sync()
      this.propsDialog?.close()
  },

  addEdge(fromId, toId) {
    const exists = this.state.edges.some((edge) => edge.from === fromId && edge.to === toId)
    if (!exists) {
      this.state.edges.push({ from: fromId, to: toId, attrs: {} })
    }
  },

  renderConnectionsEditor(nodeId) {
    if (!this.propConnectionsList) return
    this.propConnectionsList.innerHTML = ""

    const outgoing = this.state.edges.filter((edge) => edge.from === nodeId)
    if (outgoing.length === 0) {
      this.addConnectionRow()
      return
    }

    outgoing.forEach((edge) => this.addConnectionRow(edge))
  },

  addConnectionRow(edge = null) {
    if (!this.propConnectionsList || !this.currentEditingNodeId) return

    const availableTargets = this.state.nodes.filter((node) => node.id !== this.currentEditingNodeId)
    if (availableTargets.length === 0) return

    const row = document.createElement("div")
    row.className = "grid grid-cols-12 gap-2 rounded border border-base-300 p-2"
    row.dataset.kind = "connection-row"

    const sourceId = this.currentEditingNodeId
    const selectedTo = edge?.to || availableTargets[0].id
    const attrs = edge?.attrs || {}
    const edgeCondition = (attrs.condition || "").trim().toLowerCase()
    const shorthandStatus = STATUS_VALUES.includes(edgeCondition) ? edgeCondition : ""
    const mode = shorthandStatus ? "status" : attrs.condition ? "condition" : attrs.status ? "status" : "default"
    const value = shorthandStatus || attrs.condition || attrs.status || ""
    const label = attrs.label || ""
    const weight = attrs.weight || ""
    const fidelity = attrs.fidelity || ""
    const threadId = attrs.thread_id || ""
    const loopRestart = this.boolAttr(attrs.loop_restart)

    const targetOptions = availableTargets
      .map((node) => `<option value="${node.id}" ${node.id === selectedTo ? "selected" : ""}>${node.id}</option>`)
      .join("")

    row.innerHTML = `
      <div class="col-span-5 grid grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-end gap-2">
        <div class="space-y-1">
          <label class="text-[10px] font-semibold uppercase text-base-content/70">Source</label>
          <div class="rounded border border-base-300 bg-base-200 px-2 py-1 text-xs font-medium text-base-content/80">
            ${sourceId}
          </div>
        </div>
        <div class="pb-1 text-xs font-semibold text-base-content/50">-&gt;</div>
        <div class="space-y-1">
          <label class="text-[10px] font-semibold uppercase text-base-content/70">Target</label>
          <select class="conn-target w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-xs">
            ${targetOptions}
          </select>
        </div>
      </div>
      <div class="col-span-3 space-y-1">
        <label class="text-[10px] font-semibold uppercase text-base-content/70">Rule</label>
        <select class="conn-mode w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-xs">
          <option value="default" ${mode === "default" ? "selected" : ""}>default</option>
          <option value="status" ${mode === "status" ? "selected" : ""}>status</option>
          <option value="condition" ${mode === "condition" ? "selected" : ""}>condition</option>
        </select>
      </div>
      <div class="col-span-3 space-y-1">
        <label class="text-[10px] font-semibold uppercase text-base-content/70">Value</label>
        <input class="conn-value-input w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-xs font-mono" value="${value.replace(/"/g, "&quot;")}" />
        <select class="conn-value-status w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-xs">
          <option value="success" ${value === "success" ? "selected" : ""}>success</option>
          <option value="fail" ${value === "fail" ? "selected" : ""}>fail</option>
          <option value="retry" ${value === "retry" ? "selected" : ""}>retry</option>
          <option value="partial_success" ${value === "partial_success" ? "selected" : ""}>partial_success</option>
        </select>
      </div>
      <div class="col-span-1 flex items-end justify-end">
        <button type="button" class="builder-btn conn-remove">x</button>
      </div>
      <div class="col-span-3 space-y-1">
        <label class="text-[10px] font-semibold uppercase text-base-content/70">Label</label>
        <input class="conn-label w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-xs" value="${label.replace(/"/g, "&quot;")}" />
      </div>
      <div class="col-span-2 space-y-1">
        <label class="text-[10px] font-semibold uppercase text-base-content/70">Weight</label>
        <input class="conn-weight w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-xs" value="${weight}" />
      </div>
      <div class="col-span-3 space-y-1">
        <label class="text-[10px] font-semibold uppercase text-base-content/70">Fidelity</label>
        <input class="conn-fidelity w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-xs" value="${fidelity}" />
      </div>
      <div class="col-span-3 space-y-1">
        <label class="text-[10px] font-semibold uppercase text-base-content/70">Thread ID</label>
        <input class="conn-thread-id w-full rounded border border-base-300 bg-base-100 px-2 py-1 text-xs" value="${threadId}" />
      </div>
      <label class="col-span-1 flex items-end gap-1 text-[10px] font-semibold uppercase text-base-content/70">
        <input class="conn-loop-restart" type="checkbox" ${loopRestart ? "checked" : ""} />
        loop
      </label>
    `

    const modeEl = row.querySelector(".conn-mode")
    const valueInputEl = row.querySelector(".conn-value-input")
    const valueStatusEl = row.querySelector(".conn-value-status")
    const removeEl = row.querySelector(".conn-remove")
    const refreshValueState = () => {
      if (modeEl.value === "status") {
        valueInputEl.style.display = "none"
        valueStatusEl.style.display = "block"
      } else if (modeEl.value === "condition") {
        valueInputEl.style.display = "block"
        valueStatusEl.style.display = "none"
        valueInputEl.disabled = false
        valueInputEl.placeholder = 'ex: outcome.status == "fail"'
      } else {
        valueInputEl.style.display = "none"
        valueStatusEl.style.display = "none"
      }
    }
    modeEl.addEventListener("change", refreshValueState)
    removeEl.addEventListener("click", () => {
      row.remove()
      if (this.propConnectionsList.children.length === 0) this.addConnectionRow()
    })
    refreshValueState()

    this.propConnectionsList.appendChild(row)
  },

  readConnectionRows() {
    if (!this.propConnectionsList) return []

    const rows = Array.from(this.propConnectionsList.querySelectorAll("[data-kind='connection-row']"))
    return rows
      .map((row) => {
        const to = row.querySelector(".conn-target")?.value || ""
        const mode = row.querySelector(".conn-mode")?.value || "default"
        const valueInput = (row.querySelector(".conn-value-input")?.value || "").trim()
        const valueStatus = (row.querySelector(".conn-value-status")?.value || "").trim()
        const lowered = valueInput.toLowerCase()
        const label = (row.querySelector(".conn-label")?.value || "").trim()
        const weight = (row.querySelector(".conn-weight")?.value || "").trim()
        const fidelity = (row.querySelector(".conn-fidelity")?.value || "").trim()
        const threadId = (row.querySelector(".conn-thread-id")?.value || "").trim()
        const loopRestart = row.querySelector(".conn-loop-restart")?.checked ? true : ""

        if (!to) return null
        const attrs = this.cleanEmptyAttrs({
          label,
          weight,
          fidelity,
          thread_id: threadId,
          loop_restart: loopRestart,
        })

        if (mode === "status") return { to, attrs: this.cleanEmptyAttrs({ ...attrs, status: valueStatus || "success" }) }
        if (mode === "condition") {
          if (STATUS_VALUES.includes(lowered)) return { to, attrs: this.cleanEmptyAttrs({ ...attrs, status: lowered }) }
          return { to, attrs: this.cleanEmptyAttrs({ ...attrs, condition: valueInput || "true" }) }
        }
        return { to, attrs }
      })
      .filter(Boolean)
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
