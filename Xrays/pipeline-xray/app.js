/**
 * Pipeline X-Ray Studio — OpenIntelligence
 * Core engine: renders canonical pipeline, parses trace files,
 * drives Film Mode playback, and manages synchronized views.
 *
 * Zero dependencies. Runs from file:// or any static host.
 */

// ═══════════════════════════════════════════════════════════════
// STATE
// ═══════════════════════════════════════════════════════════════

const State = {
  mode: "canonical", // canonical | replay | debug
  qualityMode: "standard", // standard | deepThink | maximum
  pipeline: null, // loaded canonical-pipeline.json
  replayData: null, // parsed trace (replay or debug mode)
  activeStepId: null, // currently selected step
  filmMode: false,
  filmPlaying: false,
  filmIndex: 0,
  filmTimer: null,
  filmSpeed: 1,
  allSteps: [], // flat list of all steps (for film mode iteration)
};

// ═══════════════════════════════════════════════════════════════
// INIT
// ═══════════════════════════════════════════════════════════════

document.addEventListener("DOMContentLoaded", () => {
  loadCanonicalPipeline();
  bindEvents();
  renderCanonical();
  initWelcomeGuide();
});

function loadCanonicalPipeline() {
  if (typeof PIPELINE_DATA !== "undefined") {
    State.pipeline = PIPELINE_DATA;
  } else {
    showToast(
      "Pipeline data not found — include pipeline-data.js before app.js",
    );
    console.error(
      "PIPELINE_DATA not defined. Make sure pipeline-data.js is loaded.",
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// EVENT BINDING
// ═══════════════════════════════════════════════════════════════

function bindEvents() {
  // Mode tabs
  document.querySelectorAll(".mode-tab").forEach((tab) => {
    tab.addEventListener("click", () => switchMode(tab.dataset.mode));
  });

  // Quality mode
  document.getElementById("quality-mode").addEventListener("change", (e) => {
    State.qualityMode = e.target.value;
    renderWaterfall();
    renderDetailOverview();
  });

  // Film mode
  document
    .getElementById("btn-film-mode")
    .addEventListener("click", enterFilmMode);
  document
    .getElementById("btn-film-close")
    .addEventListener("click", exitFilmMode);
  document.getElementById("film-play").addEventListener("click", filmPlay);
  document.getElementById("film-pause").addEventListener("click", filmPause);
  document.getElementById("film-reset").addEventListener("click", filmReset);
  document
    .getElementById("film-speed-select")
    .addEventListener("change", (e) => {
      State.filmSpeed = parseFloat(e.target.value);
    });

  // Film presets
  document.querySelectorAll(".film-preset").forEach((btn) => {
    btn.addEventListener("click", () => {
      const duration = parseInt(btn.dataset.duration);
      document
        .querySelectorAll(".film-preset")
        .forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      filmPlayPreset(duration);
    });
  });

  // Back button in detail
  document
    .getElementById("btn-back-overview")
    .addEventListener("click", showOverview);

  // File drop & browse
  const dropZone = document.getElementById("drop-zone");
  const fileInput = document.getElementById("file-input");

  document
    .getElementById("btn-browse")
    .addEventListener("click", () => fileInput.click());
  fileInput.addEventListener("change", (e) => {
    if (e.target.files.length) handleFileLoad(e.target.files[0]);
  });

  // Drag-and-drop on the whole body when in replay/debug mode
  document.body.addEventListener("dragover", (e) => {
    e.preventDefault();
    if (State.mode !== "canonical") dropZone.classList.remove("hidden");
  });

  dropZone.addEventListener("dragleave", () =>
    dropZone.classList.add("hidden"),
  );
  dropZone.addEventListener("drop", (e) => {
    e.preventDefault();
    dropZone.classList.add("hidden");
    if (e.dataTransfer.files.length) handleFileLoad(e.dataTransfer.files[0]);
  });

  // Layout toggle (future: different view modes)
  document.getElementById("btn-layout").addEventListener("click", () => {
    showToast("Layout options coming soon");
  });

  // Demo trace buttons
  document.getElementById("btn-demo-standard").addEventListener("click", () => {
    loadDemoTrace("standard");
  });
  document.getElementById("btn-demo-deep").addEventListener("click", () => {
    loadDemoTrace("deepThink");
  });

  // Welcome guide dismiss
  document
    .getElementById("welcome-dismiss")
    .addEventListener("click", dismissWelcome);
}

// ═══════════════════════════════════════════════════════════════
// MODE SWITCHING
// ═══════════════════════════════════════════════════════════════

function switchMode(mode) {
  State.mode = mode;

  // Update tabs
  document
    .querySelectorAll(".mode-tab")
    .forEach((t) => t.classList.remove("active"));
  document
    .querySelector(`.mode-tab[data-mode="${mode}"]`)
    .classList.add("active");

  // Update badge
  const badge = document.getElementById("source-badge");
  const dot = badge.querySelector(".badge-dot");
  const label = badge.querySelector(".badge-label");
  const detail = badge.querySelector(".badge-detail");

  if (mode === "canonical") {
    dot.dataset.source = "canonical";
    label.textContent = "Public conceptual map";
    detail.textContent = `${State.allSteps.length}-step public overview`;
    document.getElementById("drop-zone").classList.add("hidden");
    renderCanonical();
  } else if (mode === "replay") {
    dot.dataset.source = "export";
    label.textContent = State.replayData
      ? "From PipelineTraceExporter"
      : "Awaiting trace file";
    detail.textContent = State.replayData
      ? `${State.replayData.events.length} events`
      : "Drop or browse a .txt export";
    if (!State.replayData)
      document.getElementById("drop-zone").classList.remove("hidden");
    else renderReplay();
  } else if (mode === "debug") {
    dot.dataset.source = "log";
    label.textContent = State.replayData
      ? "From pipeline_trace.log"
      : "Awaiting log file";
    detail.textContent = State.replayData
      ? `${State.replayData.queries.length} queries`
      : "Drop or browse a .log file";
    if (!State.replayData)
      document.getElementById("drop-zone").classList.remove("hidden");
    else renderDebugLog();
  }
}

// ═══════════════════════════════════════════════════════════════
// CANONICAL RENDERING
// ═══════════════════════════════════════════════════════════════

function renderCanonical() {
  if (!State.pipeline) return;
  flattenSteps();
  renderRibbon();
  renderWaterfall();
  renderDetailOverview();
}

function flattenSteps() {
  State.allSteps = [];
  for (const phase of State.pipeline.phases) {
    for (const step of phase.steps) {
      State.allSteps.push({
        ...step,
        phaseId: phase.id,
        phaseLabel: phase.label,
        phaseColor: phase.color,
      });
    }
  }
}

// ─── STAGE RIBBON ───

function renderRibbon() {
  const ribbon = document.getElementById("stage-ribbon");
  ribbon.innerHTML = "";

  for (const phase of State.pipeline.phases) {
    const phaseEl = document.createElement("div");
    phaseEl.className = "ribbon-phase";

    for (const step of phase.steps) {
      const btn = document.createElement("button");
      btn.className = "ribbon-step";
      btn.dataset.phase = phase.id;
      btn.dataset.stepId = step.id;
      btn.innerHTML = `<span class="step-number">Step ${step.stepNumber}</span>${step.shortName}`;
      btn.addEventListener("click", () => selectStep(step.id));

      if (step.conditional) {
        const condBadge = document.createElement("span");
        condBadge.className = "cond-badge";
        condBadge.textContent = step.conditional;
        btn.appendChild(condBadge);
      }

      phaseEl.appendChild(btn);
    }

    ribbon.appendChild(phaseEl);
  }
}

// ─── WATERFALL TIMELINE ───

function renderWaterfall() {
  const scroll = document.getElementById("waterfall-scroll");
  scroll.innerHTML = "";

  const showAgentic = State.qualityMode !== "standard";

  for (const phase of State.pipeline.phases) {
    const group = document.createElement("div");
    group.className = "wf-phase-group";

    // Phase header
    const label = document.createElement("div");
    label.className = "wf-phase-label";
    label.dataset.phase = phase.id;
    label.textContent = `${phase.label} — ${phase.description}`;
    group.appendChild(label);

    for (const step of phase.steps) {
      // Step row
      const row = document.createElement("div");
      row.className = "wf-step";
      row.dataset.stepId = step.id;
      if (State.activeStepId === step.id) row.classList.add("active");

      // Duration bar width: approximate relative proportion
      const barWidth = estimateBarWidth(step);

      row.innerHTML = `
        <div class="wf-step-number">Step ${step.stepNumber}</div>
        <div class="wf-step-info">
          <div class="wf-step-name">${step.name}${step.conditional ? ` <span class="cond-badge">${step.conditional}</span>` : ""}</div>
          <div class="wf-step-desc">${escapeHtml(step.description).substring(0, 80)}${step.description.length > 80 ? "…" : ""}</div>
        </div>
        <div class="wf-step-bar-container">
          <div class="wf-step-bar">
            <div class="wf-step-bar-fill" style="width: ${barWidth}%; background: ${step.color};"></div>
          </div>
          <div class="wf-step-duration">${step.typicalDuration || "—"}</div>
        </div>
      `;

      row.addEventListener("click", () => selectStep(step.id));
      group.appendChild(row);

      // Substeps
      if (step.substeps && step.substeps.length > 0) {
        const subs = document.createElement("div");
        subs.className = "wf-substeps";

        for (const sub of step.substeps) {
          const subRow = document.createElement("div");
          subRow.className = "wf-substep";
          subRow.innerHTML = `
            <div class="wf-substep-name" style="--sub-color: ${sub.color}">
              <span style="background: ${sub.color}; width: 5px; height: 5px; border-radius: 50%; display: inline-block;"></span>
              ${escapeHtml(sub.name)}
            </div>
            <div class="wf-substep-hint">${sub.type || ""}</div>
          `;
          subRow.addEventListener("click", (e) => {
            e.stopPropagation();
            selectStep(step.id);
          });
          subs.appendChild(subRow);
        }

        group.appendChild(subs);
      }
    }

    scroll.appendChild(group);
  }

  // Agentic overlay section
  if (showAgentic && State.pipeline.agenticOverlay) {
    const agGroup = document.createElement("div");
    agGroup.className = "wf-phase-group";

    const agLabel = document.createElement("div");
    agLabel.className = "wf-phase-label";
    agLabel.dataset.phase = "agentic";
    agLabel.style.setProperty("--phase-color", "var(--c-agentic)");
    agLabel.innerHTML =
      '<span style="background: var(--c-agentic); width: 10px; height: 2px; border-radius: 1px; display: inline-block;"></span> AGENTIC OVERLAY — Multi-session reasoning (' +
      (State.qualityMode === "deepThink" ? "4-8 sessions" : "8-50 sessions") +
      ")";
    agGroup.appendChild(agLabel);

    for (const step of State.pipeline.agenticOverlay.steps) {
      const row = document.createElement("div");
      row.className = "wf-step";
      row.innerHTML = `
        <div class="wf-step-number" style="color: var(--c-agentic);">◈</div>
        <div class="wf-step-info">
          <div class="wf-step-name">${step.name}</div>
          <div class="wf-step-desc">${escapeHtml(step.description).substring(0, 80)}${step.description.length > 80 ? "…" : ""}</div>
        </div>
        <div class="wf-step-bar-container">
          <div class="wf-step-bar">
            <div class="wf-step-bar-fill" style="width: 60%; background: var(--c-agentic);"></div>
          </div>
          <div class="wf-step-duration">varies</div>
        </div>
      `;
      agGroup.appendChild(row);
    }

    scroll.appendChild(agGroup);
  }

  updateStats();
}

function estimateBarWidth(step) {
  // Parse typical duration to get a relative bar width (0-100)
  const d = step.typicalDuration || "";
  if (d.includes("30s") || d.includes("2min")) return 95;
  if (d.includes("10s") || d.includes("12s")) return 75;
  if (d.includes("2-10s") || d.includes("2-5")) return 60;
  if (d.includes("500ms")) return 40;
  if (d.includes("200ms")) return 30;
  if (d.includes("100ms")) return 25;
  if (d.includes("50ms")) return 18;
  if (d.includes("10ms")) return 12;
  if (d.includes("5ms")) return 8;
  if (d.includes("< 1s")) return 15;
  if (d.includes("< 0.5s")) return 10;
  if (d.includes("< 2s")) return 20;
  return 15;
}

function updateStats() {
  document.getElementById("stat-steps").textContent = State.allSteps.length;

  if (State.replayData && State.replayData.metadata) {
    const meta = State.replayData.metadata;
    document.getElementById("stat-duration").textContent =
      meta.totalGenTime || "—";
    document.getElementById("stat-tokens").textContent =
      meta.tokensGenerated || "—";
  } else {
    document.getElementById("stat-duration").textContent = "—";
    document.getElementById("stat-tokens").textContent = "—";
  }
}

// ─── STEP SELECTION ───

function selectStep(stepId) {
  State.activeStepId = stepId;

  // Update ribbon
  document.querySelectorAll(".ribbon-step").forEach((el) => {
    el.classList.toggle("active", el.dataset.stepId === stepId);
  });

  // Update waterfall
  document.querySelectorAll(".wf-step").forEach((el) => {
    el.classList.toggle("active", el.dataset.stepId === stepId);
  });

  // Show detail
  showStepDetail(stepId);
}

// ─── DETAIL RAIL ───

function renderDetailOverview() {
  document.getElementById("detail-overview").classList.remove("hidden");
  document.getElementById("detail-step").classList.add("hidden");
  document.getElementById("detail-title").textContent = "Pipeline Overview";

  renderLimitGrid();
  renderModeCards();
  renderGateList();
}

function renderLimitGrid() {
  const grid = document.getElementById("limit-grid");
  if (!State.pipeline) return;

  const limits = State.pipeline.hardLimits;
  const items = [
    { key: "llmContext", label: "LLM Context" },
    { key: "contextChars", label: "Context Chars" },
    { key: "embeddingTokens", label: "Embed Tokens" },
    { key: "embeddingDim", label: "Embed Dims" },
    { key: "chunkSize", label: "Chunk Size" },
    { key: "chunkLimit", label: "Max Chunks" },
    { key: "ocrDpi", label: "OCR DPI" },
    { key: "compressionCap", label: "Compress Cap" },
  ];

  grid.innerHTML = items
    .map((item) => {
      const lim = limits[item.key];
      return `<div class="limit-item">
      <div class="limit-value">${formatNumber(lim.value)}</div>
      <div class="limit-label">${item.label} (${lim.unit})</div>
    </div>`;
    })
    .join("");
}

function renderModeCards() {
  const container = document.getElementById("mode-cards");
  if (!State.pipeline) return;

  const modes = State.pipeline.modes;
  container.innerHTML = Object.entries(modes)
    .map(
      ([key, mode]) => `
    <div class="mode-card ${key === State.qualityMode ? "selected" : ""}" data-mode-key="${key}">
      <div class="mode-card-sessions">${mode.sessions}</div>
      <div class="mode-card-info">
        <div class="mode-card-name">${mode.label}</div>
        <div class="mode-card-desc">${mode.description}</div>
      </div>
      <div class="mode-card-speed">${mode.speed}</div>
    </div>
  `,
    )
    .join("");

  container.querySelectorAll(".mode-card").forEach((card) => {
    card.addEventListener("click", () => {
      State.qualityMode = card.dataset.modeKey;
      document.getElementById("quality-mode").value = card.dataset.modeKey;
      renderWaterfall();
      renderModeCards();
    });
  });
}

function renderGateList() {
  const list = document.getElementById("gate-list");
  if (!State.pipeline) return;

  const gates = State.pipeline.gates;
  list.innerHTML = Object.entries(gates)
    .map(
      ([letter, gate]) => `
    <div class="gate-item">
      <div class="gate-letter ${gate.type}">${letter}</div>
      <div class="gate-name">${gate.name}</div>
      <div class="gate-type ${gate.type}">${gate.type}</div>
    </div>
  `,
    )
    .join("");
}

function showStepDetail(stepId) {
  const step = State.allSteps.find((s) => s.id === stepId);
  if (!step) return;

  document.getElementById("detail-overview").classList.add("hidden");
  document.getElementById("detail-step").classList.remove("hidden");
  document.getElementById("detail-title").textContent = step.name;

  const body = document.getElementById("step-detail-body");
  let html = `
    <div class="step-detail-header">
      <div class="step-number-large">Step ${step.stepNumber} · ${step.phaseLabel}</div>
      <h3 style="color: ${step.color}">${step.name}</h3>
      <div class="step-detail-desc">${escapeHtml(step.description)}</div>
    </div>

    <div class="step-detail-meta">
      <div class="meta-item">
        <div class="meta-item-label">Typical Duration</div>
        <div class="meta-item-value">${step.typicalDuration || "Not measured"}</div>
      </div>
      <div class="meta-item">
        <div class="meta-item-label">Phase</div>
        <div class="meta-item-value" style="color: ${step.phaseColor}">${step.phaseLabel}</div>
      </div>
    </div>
  `;

  // Substeps
  if (step.substeps && step.substeps.length > 0) {
    html += `<div class="step-substeps-detail"><h4>Substeps (${step.substeps.length})</h4>`;
    for (const sub of step.substeps) {
      html += `
        <div class="substep-detail-item" style="border-left-color: ${sub.color}">
          <div class="substep-detail-item-name">${escapeHtml(sub.name)}</div>
          <div class="substep-detail-item-desc">${escapeHtml(sub.description)}</div>
        </div>
      `;
    }
    html += "</div>";
  }

  // Public trace event categories
  if (
    step.thinkingKinds &&
    step.thinkingKinds.length > 0 &&
    State.pipeline.thinkingKindMap
  ) {
    html += `<div class="step-thinking-kinds"><h4>Trace Event Categories</h4><div class="kind-tags">`;
    for (const kind of step.thinkingKinds) {
      const info = State.pipeline.thinkingKindMap[kind];
      if (info) {
        html += `<span class="kind-tag" style="background: ${info.color}">${info.displayName}</span>`;
      }
    }
    html += "</div></div>";
  }

  // Conditional note
  if (step.conditional) {
    html += `<div style="margin-top: 12px; padding: 8px 10px; background: rgba(251, 191, 36, 0.08); border: 1px solid rgba(251, 191, 36, 0.2); border-radius: 8px; font-size: 11px; color: var(--text-secondary);">
      <strong>Conditional:</strong> ${escapeHtml(step.conditional)}
    </div>`;
  }

  body.innerHTML = html;
}

function showOverview() {
  State.activeStepId = null;
  document
    .querySelectorAll(".ribbon-step")
    .forEach((el) => el.classList.remove("active"));
  document
    .querySelectorAll(".wf-step")
    .forEach((el) => el.classList.remove("active"));
  renderDetailOverview();
}

// ═══════════════════════════════════════════════════════════════
// TRACE PARSERS
// ═══════════════════════════════════════════════════════════════

function handleFileLoad(file) {
  const reader = new FileReader();
  reader.onload = (e) => {
    const text = e.target.result;
    document.getElementById("drop-zone").classList.add("hidden");

    if (State.mode === "replay") {
      State.replayData = parseExportTrace(text);
      renderReplay();
    } else if (State.mode === "debug") {
      State.replayData = parseDebugLog(text);
      renderDebugLog();
    }

    updateBadgeAfterLoad();
  };
  reader.readAsText(file);
}

/**
 * Parse PipelineTraceExporter output.
 * Format: sections marked by ▶ HEADER, fields with labels,
 * thinking events as timestamped lines.
 */
function parseExportTrace(text) {
  const result = {
    source: "export",
    query: "",
    response: "",
    metadata: {},
    events: [],
    pipelineLog: [],
    reasoningTrace: [],
    chunks: [],
  };

  const sections = text.split(/^▶\s+/m);

  for (const section of sections) {
    const lines = section.split("\n");
    const header = lines[0].trim();

    if (header.startsWith("QUERY")) {
      result.query = lines.slice(2).join("\n").trim();
    } else if (header.startsWith("RESPONSE")) {
      result.response = lines.slice(2).join("\n").trim();
    } else if (header.startsWith("METADATA")) {
      for (const line of lines.slice(2)) {
        const match = line.match(/^\s+(\w[\w\s/]*?):\s+(.+)/);
        if (match) {
          const key = match[1].trim().replace(/\s+/g, "");
          result.metadata[key] = match[2].trim();
        }
      }
    } else if (header.startsWith("THINKING EVENTS")) {
      for (const line of lines.slice(2)) {
        const match = line.match(
          /^\s+\+(\d+)ms\s+\[(.+?)\]\s+(.+?)(?:\s+│\s+(.+))?$/,
        );
        if (match) {
          result.events.push({
            timeMs: parseInt(match[1]),
            kind: match[2].trim(),
            title: match[3].trim(),
            detail: match[4] ? match[4].trim() : null,
          });
        }
      }
    } else if (header.startsWith("PIPELINE LOG")) {
      for (const line of lines.slice(2)) {
        const trimmed = line.trim();
        if (trimmed) result.pipelineLog.push(trimmed);
      }
    } else if (header.startsWith("REASONING TRACE")) {
      for (const line of lines.slice(2)) {
        const match = line.match(/^\s+Session\s+(\d+):\s+(.+)/);
        if (match) {
          result.reasoningTrace.push({
            session: parseInt(match[1]),
            content: match[2].trim(),
          });
        }
      }
    } else if (header.startsWith("RETRIEVED CHUNKS")) {
      let currentChunk = null;
      for (const line of lines.slice(2)) {
        if (line.includes("── Chunk")) {
          if (currentChunk) result.chunks.push(currentChunk);
          currentChunk = {};
        } else if (currentChunk) {
          const m = line.match(/^\s+(\w+):\s+(.+)/);
          if (m) currentChunk[m[1].trim()] = m[2].trim();
        }
      }
      if (currentChunk) result.chunks.push(currentChunk);
    }
  }

  return result;
}

/**
 * Parse pipeline_trace.log (rolling debug log from device).
 * Format: [HH:mm:ss.SSS] [CATEGORY] message
 * Queries delimited by traceQueryStart / traceQueryEnd markers.
 */
function parseDebugLog(text) {
  const result = {
    source: "debug",
    queries: [],
    allLines: [],
  };

  const lines = text.split("\n");
  let currentQuery = null;

  for (const line of lines) {
    const match = line.match(
      /^\[(\d{2}:\d{2}:\d{2}\.\d{3})\]\s+\[(\w+)\]\s+(.+)/,
    );
    if (!match) continue;

    const entry = {
      time: match[1],
      category: match[2],
      message: match[3].trim(),
    };

    result.allLines.push(entry);

    if (
      entry.message.includes("traceQueryStart") ||
      entry.message.includes("═══ QUERY START")
    ) {
      currentQuery = { startTime: entry.time, entries: [], endTime: null };
      result.queries.push(currentQuery);
    }

    if (currentQuery) {
      currentQuery.entries.push(entry);
    }

    if (
      entry.message.includes("traceQueryEnd") ||
      entry.message.includes("═══ QUERY END")
    ) {
      if (currentQuery) {
        currentQuery.endTime = entry.time;
        currentQuery = null;
      }
    }
  }

  return result;
}

// ═══════════════════════════════════════════════════════════════
// REPLAY RENDERING
// ═══════════════════════════════════════════════════════════════

function renderReplay() {
  if (!State.replayData || State.replayData.source !== "export") return;

  const data = State.replayData;

  // Update badge
  updateBadgeAfterLoad();

  // Render waterfall with canonical steps + overlay replay events
  renderCanonical(); // base structure

  // Update stats with real data
  if (data.metadata) {
    document.getElementById("stat-duration").textContent =
      data.metadata.TotalGenTime || data.metadata.RetrievalTime || "—";
    document.getElementById("stat-tokens").textContent =
      data.metadata.TokensGenerated || "—";
  }

  // Show replay detail in right rail
  const detailContent = document.getElementById("detail-content");
  const overview = document.getElementById("detail-overview");
  overview.classList.remove("hidden");

  // Build replay metadata section
  let replayHtml = `
    <div class="overview-card">
      <h3>Replay: Trace Data</h3>
      <div class="replay-metadata">
  `;

  if (data.query) {
    replayHtml += `<div class="replay-meta-item" style="grid-column: 1/-1;">
      <div class="replay-meta-label">Query</div>
      <div class="replay-meta-value" style="font-size: 12px; font-weight: 400;">${escapeHtml(data.query.substring(0, 200))}${data.query.length > 200 ? "…" : ""}</div>
    </div>`;
  }

  const metaKeys = [
    "Model",
    "QualityMode",
    "Agentic",
    "RetrievalTime",
    "TotalGenTime",
    "TTFT",
    "TokensGenerated",
    "Tokens/sec",
    "Gating",
  ];
  for (const key of metaKeys) {
    const val = data.metadata[key];
    if (val) {
      replayHtml += `<div class="replay-meta-item">
        <div class="replay-meta-label">${key}</div>
        <div class="replay-meta-value">${escapeHtml(val)}</div>
      </div>`;
    }
  }

  replayHtml += `</div></div>`;

  // Thinking events log
  if (data.events.length > 0) {
    replayHtml += `<div class="overview-card"><h3>Thinking Events (${data.events.length})</h3><div class="thinking-log">`;
    for (const evt of data.events) {
      const kindInfo = findKindInfo(evt.kind);
      replayHtml += `<div class="thinking-event">
        <div class="thinking-event-time">+${evt.timeMs.toLocaleString()}ms</div>
        <div class="thinking-event-kind" style="background: ${kindInfo.color}; color: #fff;">${escapeHtml(evt.kind)}</div>
        <div class="thinking-event-title">${escapeHtml(evt.title)}</div>
      </div>`;
    }
    replayHtml += `</div></div>`;
  }

  // Retrieved chunks
  if (data.chunks.length > 0) {
    replayHtml += `<div class="overview-card"><h3>Retrieved Chunks (${data.chunks.length})</h3>`;
    for (const chunk of data.chunks) {
      replayHtml += `<div style="padding: 8px; background: var(--bg-root); border-radius: 8px; margin-bottom: 6px; font-size: 11px;">
        <div style="color: var(--text-secondary); font-weight: 600;">${escapeHtml(chunk.Source || "Unknown")}</div>
        <div style="color: var(--text-muted); margin-top: 2px;">Rank ${chunk.Rank || "?"} · Similarity ${chunk.Similarity || "?"}${chunk.Page ? " · Page " + chunk.Page : ""}</div>
        ${chunk.Content ? `<div style="color: var(--text-muted); margin-top: 4px; white-space: pre-wrap;">${escapeHtml(chunk.Content.substring(0, 150))}…</div>` : ""}
      </div>`;
    }
    replayHtml += `</div>`;
  }

  // Reasoning trace
  if (data.reasoningTrace.length > 0) {
    replayHtml += `<div class="overview-card"><h3>Reasoning Trace (${data.reasoningTrace.length} sessions)</h3>`;
    for (const session of data.reasoningTrace) {
      replayHtml += `<div style="padding: 6px 8px; background: var(--bg-root); border-radius: 6px; margin-bottom: 4px; font-size: 11px;">
        <span style="color: var(--c-agentic); font-weight: 600;">Session ${session.session}:</span>
        <span style="color: var(--text-secondary);">${escapeHtml(session.content.substring(0, 200))}</span>
      </div>`;
    }
    replayHtml += `</div>`;
  }

  overview.innerHTML = replayHtml;
}

function renderDebugLog() {
  if (!State.replayData || State.replayData.source !== "debug") return;

  const data = State.replayData;
  updateBadgeAfterLoad();
  renderCanonical();

  const overview = document.getElementById("detail-overview");
  overview.classList.remove("hidden");
  document.getElementById("detail-step").classList.add("hidden");

  let html = `<div class="overview-card"><h3>Debug Log: ${data.queries.length} Queries, ${data.allLines.length} Lines</h3>`;

  if (data.queries.length === 0) {
    html += `<div style="padding: 12px; font-size: 12px; color: var(--text-muted);">No query boundaries found. Showing raw log entries.</div>`;
  }

  for (const [i, query] of data.queries.entries()) {
    html += `<div style="margin-bottom: 12px; padding: 10px; background: var(--bg-root); border-radius: 8px;">
      <div style="font-weight: 600; font-size: 12px; color: var(--text-primary); margin-bottom: 6px;">Query ${i + 1} <span style="color: var(--text-muted); font-weight: 400;">${query.startTime} → ${query.endTime || "(running)"}</span></div>
      <div class="thinking-log">`;

    for (const entry of query.entries.slice(0, 50)) {
      const catColor = getCategoryColor(entry.category);
      html += `<div class="thinking-event">
        <div class="thinking-event-time">${entry.time}</div>
        <div class="thinking-event-kind" style="background: ${catColor}; color: #fff;">${entry.category}</div>
        <div class="thinking-event-title">${escapeHtml(entry.message.substring(0, 120))}</div>
      </div>`;
    }

    if (query.entries.length > 50) {
      html += `<div style="padding: 4px 8px; font-size: 10px; color: var(--text-muted);">… ${query.entries.length - 50} more entries</div>`;
    }

    html += `</div></div>`;
  }

  html += `</div>`;
  overview.innerHTML = html;
}

function updateBadgeAfterLoad() {
  const badge = document.getElementById("source-badge");
  const label = badge.querySelector(".badge-label");
  const detail = badge.querySelector(".badge-detail");

  if (State.mode === "replay" && State.replayData) {
    label.textContent = "From PipelineTraceExporter";
    detail.textContent = `${State.replayData.events.length} events · ${State.replayData.chunks.length} chunks`;
  } else if (State.mode === "debug" && State.replayData) {
    label.textContent = "From pipeline_trace.log";
    detail.textContent = `${State.replayData.queries.length} queries · ${State.replayData.allLines.length} lines`;
  }
}

// ═══════════════════════════════════════════════════════════════
// FILM MODE
// ═══════════════════════════════════════════════════════════════

function enterFilmMode() {
  State.filmMode = true;
  State.filmIndex = 0;
  document.getElementById("film-overlay").classList.remove("hidden");
  filmRenderStep();
}

function exitFilmMode() {
  State.filmMode = false;
  filmPause();
  document.getElementById("film-overlay").classList.add("hidden");
}

function filmPlay() {
  if (State.filmPlaying) return;
  State.filmPlaying = true;
  filmTick();
}

function filmPause() {
  State.filmPlaying = false;
  if (State.filmTimer) {
    clearTimeout(State.filmTimer);
    State.filmTimer = null;
  }
}

function filmReset() {
  filmPause();
  State.filmIndex = 0;
  filmRenderStep();
}

function filmTick() {
  if (!State.filmPlaying) return;
  if (State.filmIndex >= State.allSteps.length) {
    State.filmPlaying = false;
    return;
  }

  filmRenderStep();
  State.filmIndex++;

  // Calculate delay based on step importance and speed
  const step =
    State.allSteps[Math.min(State.filmIndex, State.allSteps.length - 1)];
  let baseDelay = 2000; // 2s per step

  // Emphasize bottleneck steps
  if (
    step &&
    (step.id.includes("step3") ||
      step.id.includes("step6") ||
      step.id.includes("step7-5") ||
      step.id.includes("step4-7"))
  ) {
    baseDelay = 3500;
  }

  const delay = baseDelay / State.filmSpeed;
  State.filmTimer = setTimeout(filmTick, delay);
}

function filmPlayPreset(durationSec) {
  filmReset();
  if (durationSec === 0) {
    State.filmSpeed = 1;
  } else {
    // Calculate speed to fit all steps in the given duration
    const stepsCount = State.allSteps.length;
    const avgDelay = (durationSec * 1000) / stepsCount;
    State.filmSpeed = 2000 / avgDelay; // base delay is 2000ms
  }
  document.getElementById("film-speed-select").value =
    State.filmSpeed <= 0.5
      ? "0.5"
      : State.filmSpeed <= 1.5
        ? "1"
        : State.filmSpeed <= 3
          ? "2"
          : "4";
  filmPlay();
}

function filmRenderStep() {
  const display = document.getElementById("film-step-display");
  const progressBar = document.getElementById("film-progress-bar");

  if (State.filmIndex >= State.allSteps.length) {
    display.innerHTML = `<div class="film-current-step">
      <div class="film-phase-label">COMPLETE</div>
      <div class="film-step-number" style="font-size: 36px;">✓</div>
      <div class="film-step-name">Pipeline Finished</div>
      <div class="film-step-desc">${State.allSteps.length} steps processed</div>
    </div>`;
    progressBar.style.width = "100%";
    return;
  }

  const step = State.allSteps[State.filmIndex];
  const progress = ((State.filmIndex + 1) / State.allSteps.length) * 100;
  progressBar.style.width = `${progress}%`;

  let html = `<div class="film-current-step">
    <div class="film-phase-label">${step.phaseLabel}</div>
    <div class="film-step-number">Step ${step.stepNumber}</div>
    <div class="film-step-name" style="color: ${step.color}">${step.name}</div>
    <div class="film-step-desc">${escapeHtml(step.description)}</div>
  `;

  // Substeps as pills
  if (step.substeps && step.substeps.length > 0) {
    html += '<div class="film-substeps-list">';
    step.substeps.forEach((sub, i) => {
      html += `<span class="film-substep-pill" style="background: ${sub.color}; animation-delay: ${i * 150}ms">${escapeHtml(sub.name)}</span>`;
    });
    html += "</div>";
  }

  // Special: gates visualization
  if (step.id === "query-step7-5" && State.pipeline.gates) {
    html += '<div class="film-gates-row">';
    Object.entries(State.pipeline.gates).forEach(([letter, gate], i) => {
      const bg =
        gate.type === "critical"
          ? "var(--c-gate-critical)"
          : "var(--c-gate-advisory)";
      html += `<div class="film-gate" style="background: ${bg}; animation-delay: ${i * 100}ms">${letter}</div>`;
    });
    html += "</div>";
  }

  html += "</div>";
  display.innerHTML = html;

  // Also highlight in ribbon if visible
  selectStep(step.id);
}

// ═══════════════════════════════════════════════════════════════
// DEMO TRACE LOADING
// ═══════════════════════════════════════════════════════════════

function loadDemoTrace(traceName) {
  if (typeof DEMO_TRACES === "undefined" || !DEMO_TRACES[traceName]) {
    showToast("Demo trace not available");
    return;
  }

  const text = DEMO_TRACES[traceName];
  State.replayData = parseExportTrace(text);
  switchMode("replay");
  renderReplay();

  const label =
    traceName === "standard"
      ? "Standard (Engine Oil)"
      : "Deep Think (Brake Comparison)";
  showToast("Loaded demo: " + label);
}

// ═══════════════════════════════════════════════════════════════
// WELCOME GUIDE
// ═══════════════════════════════════════════════════════════════

function initWelcomeGuide() {
  const dismissed = localStorage.getItem("xray-welcome-dismissed");
  if (dismissed) {
    document.getElementById("welcome-guide").classList.add("hidden");
  }
}

function dismissWelcome() {
  document.getElementById("welcome-guide").classList.add("hidden");
  localStorage.setItem("xray-welcome-dismissed", "1");
}

// ═══════════════════════════════════════════════════════════════
// UTILITIES
// ═══════════════════════════════════════════════════════════════

function escapeHtml(str) {
  if (!str) return "";
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

function formatNumber(n) {
  if (n >= 10000) return (n / 1000).toFixed(0) + "K";
  return n.toLocaleString();
}

function findKindInfo(kindName) {
  if (!State.pipeline || !State.pipeline.thinkingKindMap) {
    return { color: "#68687a", displayName: kindName };
  }

  // Try direct match by display name or key
  for (const [key, info] of Object.entries(State.pipeline.thinkingKindMap)) {
    if (
      info.displayName === kindName ||
      key === kindName.toLowerCase().replace(/\s+/g, "")
    ) {
      return info;
    }
  }

  // Fuzzy match
  const lower = kindName.toLowerCase();
  for (const [key, info] of Object.entries(State.pipeline.thinkingKindMap)) {
    if (lower.includes(key) || key.includes(lower)) return info;
  }

  return { color: "#68687a", displayName: kindName };
}

function getCategoryColor(category) {
  const colors = {
    pipeline: "#a78bfa",
    retrieval: "#34d399",
    llm: "#fbbf24",
    embedding: "#60a5fa",
    ingestion: "#34d399",
    pipelineTrace: "#818cf8",
    system: "#68687a",
    error: "#ef4444",
  };
  return colors[category] || "#68687a";
}

function showToast(message) {
  const toast = document.getElementById("toast");
  toast.textContent = message;
  toast.classList.remove("hidden");
  setTimeout(() => toast.classList.add("hidden"), 3000);
}
