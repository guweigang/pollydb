const fallbackData = {
  title: "PollyDB Agent History Graph",
  tagline: "AI-generated understanding stored as versioned, replayable rows.",
  generated_at: "2026-07-15T00:00:00Z",
  commits: [
    {
      cid: "derive-episode-graph",
      root_cid: "root-after-derive",
      parent_cids: ["import-session"],
      message: "save episode reasoning graph episode-demo-session-001",
      author: "agentview",
      timestamp: 0,
    },
    {
      cid: "import-session",
      root_cid: "root-after-import",
      parent_cids: [],
      message: "sync codex session rows",
      author: "agentview",
      timestamp: 0,
    },
  ],
  session: {
    id: "session-001",
    title: "Fixture thread",
    cwd: "/tmp/work",
    source: "codex",
    updated_at: "2026-04-01T10:05:00Z",
  },
  entries: [
    {
      seq: 1,
      timestamp: "2026-04-01T10:00:05Z",
      kind: "message",
      role: "user",
      text: "Review this patch",
    },
    {
      seq: 2,
      timestamp: "2026-04-01T10:00:06Z",
      kind: "message",
      role: "assistant",
      text: "I will inspect the patch.",
    },
  ],
  graph: {
    episode: {
      episode_id: "episode-demo-session-001",
      session_id: "session-001",
      start_seq: 1,
      end_seq: 4,
      title: "Fixture thread",
      intent: "Review this patch",
      outcome: "Derived a replayable episode graph from the session.",
      status: "derived",
      cwd: "/tmp/work",
      repo: "work",
      confidence: 82,
      source_refs: [
        {
          table_name: "entries",
          primary_key: "session-001:1",
          column_name: "content_text",
          start_seq: 1,
          end_seq: 1,
          text: "Review this patch",
        },
      ],
      derived_from_root_hash: "root-after-import",
    },
    report: {
      report_id: "report-episode-demo-session-001",
      episode_id: "episode-demo-session-001",
      summary_md:
        "# Fixture thread\n\n- 用户问题：Review this patch\n- 当时推进：I will inspect the patch.\n- 可复用记忆：这段会话已经被整理成带证据引用的工作复盘。\n",
    },
    nodes: [
      {
        node_id: "node-problem",
        kind: "problem",
        title: "用户当时想解决什么？",
        content: "The session starts with a user request that should become a replayable work unit.",
        start_seq: 1,
        end_seq: 1,
        confidence: 88,
        source_refs: [
          {
            table_name: "entries",
            primary_key: "session-001:1",
            column_name: "content_text",
            start_seq: 1,
            end_seq: 1,
            text: "Review this patch",
          },
        ],
      },
      {
        node_id: "node-action",
        kind: "action",
        title: "Agent 如何开始推进？",
        content: "The agent performs or proposes the next work step.",
        start_seq: 2,
        end_seq: 2,
        confidence: 78,
        source_refs: [
          {
            table_name: "entries",
            primary_key: "session-001:2",
            column_name: "content_text",
            start_seq: 2,
            end_seq: 2,
            text: "I will inspect the patch.",
          },
        ],
      },
      {
        node_id: "node-evidence",
        kind: "evidence",
        title: "每个判断都能回到原文",
        content: "每个步骤都引用原始消息，用户可以看到它来自哪一段会话。",
        start_seq: 1,
        end_seq: 4,
        confidence: 92,
      },
      {
        node_id: "node-outcome",
        kind: "outcome",
        title: "沉淀成可复用记忆",
        content: "这次会话被保存成版本化的报告、步骤和证据引用，之后可以继续更新、对比和回放。",
        start_seq: 4,
        end_seq: 4,
        confidence: 84,
      },
    ],
    links: [
      { from_node_id: "node-problem", to_node_id: "node-action", kind: "led_to" },
      { from_node_id: "node-action", to_node_id: "node-evidence", kind: "supported_by" },
      { from_node_id: "node-evidence", to_node_id: "node-outcome", kind: "resolves" },
    ],
  },
};

let selectedNodeId = "";

async function loadData() {
  if (window.__POLLYDB_DEMO_DATA) return window.__POLLYDB_DEMO_DATA;
  try {
    const response = await fetch("./demo-data.json", { cache: "no-store" });
    if (!response.ok) throw new Error("missing demo-data.json");
    return await response.json();
  } catch {
    return fallbackData;
  }
}

function shortHash(value) {
  if (!value) return "none";
  return value.length > 14 ? `${value.slice(0, 7)}…${value.slice(-5)}` : value;
}

function text(value) {
  return value || "";
}

const kindLabels = {
  problem: "问题",
  action: "处理",
  evidence: "依据",
  outcome: "记忆",
};

const titleLabels = {
  problem: "用户当时想解决什么？",
  action: "Agent 做了什么？",
  evidence: "这些判断从哪里来？",
  outcome: "沉淀成什么记忆？",
};

function render(data) {
  const graph = data.graph || fallbackData.graph;
  const episode = graph.episode || {};
  const report = graph.report || {};
  const nodes = graph.nodes || [];

  document.title = "把长会话变成工作记忆";
  document.getElementById("sessionChip").textContent = `${data.session?.source || "agent"} · ${
    data.session?.title || episode.title || "session"
  }`;
  document.getElementById("episodeStatus").textContent = "真实 Codex 会话";
  document.getElementById("episodeTitle").textContent = episode.title || "一次工作会话";
  document.getElementById("episodeIntent").textContent = episode.intent || data.tagline || "";
  document.getElementById("rootHash").textContent = "";

  renderSummaryFacts(data, nodes);
  renderCommits(data.commits || []);
  renderGraph(nodes);
  selectNode(nodes[0]?.node_id || "", data);
}

function renderSummaryFacts(data, nodes) {
  const facts = document.getElementById("summaryFacts");
  const entries = data.entries || [];
  const refs = (data.graph?.episode?.source_refs || []).length;
  facts.innerHTML = `
    <div class="fact">
      <strong>${escapeHtml(String(entries.length))}</strong>
      <span>条原文 row</span>
    </div>
    <div class="fact">
      <strong>${escapeHtml(String(nodes.length))}</strong>
      <span>个记忆节点</span>
    </div>
    <div class="fact">
      <strong>${escapeHtml(String(refs))}</strong>
      <span>条证据边</span>
    </div>
  `;
}

function renderCommits(commits) {
  const items = visibleCommits(commits);
  document.getElementById("commitCount").textContent = `${items.length} 条`;
  const list = document.getElementById("commitList");
  list.innerHTML = "";
  items.forEach((commit, index) => {
    const item = document.createElement("button");
    item.type = "button";
    item.className = "commit";
    const label = commitLabel(commit, index, items.length);
    item.innerHTML = `
      <div class="commit-dot"></div>
      <div>
        <div class="commit-title">${escapeHtml(label.title)}</div>
        <div class="commit-copy">${escapeHtml(label.copy)}</div>
        <div class="commit-meta">${escapeHtml(shortHash(commit.cid))}</div>
      </div>
    `;
    item.addEventListener("click", () => showCommitDetail(commit, label));
    list.appendChild(item);
  });
}

function showCommitDetail(commit, label) {
  document.getElementById("detailTitle").textContent = label.title;
  document.getElementById("detailContent").textContent = label.copy;
  const isSummaryCommit = (commit.message || "").includes("save episode reasoning graph");
  document.getElementById("evidenceList").innerHTML = `
    <div class="evidence">
      <div class="evidence-key">提交 ${escapeHtml(shortHash(commit.cid))}</div>
      <div class="evidence-text">${escapeHtml(commit.message || "versioned update")}</div>
    </div>
    <div class="evidence">
      <div class="evidence-key">保存了什么</div>
      <div class="evidence-text">${escapeHtml(commitValue(commit))}</div>
    </div>
  `;
  document.getElementById("memoryLabel").textContent = isSummaryCommit
    ? "版本 diff"
    : "PollyDB 在这里的作用";
  const block = document.getElementById("memoryBlock");
  if (isSummaryCommit) {
    block.className = "memory-block diff-block";
    block.innerHTML = memoryDiffHtml();
  } else {
    block.className = "memory-block";
    block.innerHTML = `
      <p>PollyDB 让这张记忆卡拥有数据库语义：它有结构、有版本、有证据边，而不是散落在聊天记录里的一段文本。</p>
      <p class="takeaway">之后可以比较不同版本的记忆、回到生成它的原文证据，也可以继续让模型更新或合并这张卡。</p>
    `;
  }
}

function memoryDiffHtml() {
  return `
    <div class="diff-columns">
      <section class="diff-version">
        <div class="diff-label">上一版</div>
        <p>这段会话被整理成一段普通摘要。</p>
        <p class="muted-line">问题：读得懂，但不知道结论从哪来，也不能比较后续变化。</p>
      </section>
      <section class="diff-version current">
        <div class="diff-label">当前版</div>
        <p>记忆被拆成 typed rows：问题、处理、依据、结论、证据引用。</p>
        <p class="muted-line">每次模型更新都会产生 commit，可审计、可回放、可继续合并。</p>
      </section>
    </div>
    <div class="diff-list">
      <div class="diff-item add"><strong>新增</strong><span>把“PollyDB 的核心卖点”沉淀为 typed rows + commits + evidence refs。</span></div>
      <div class="diff-item change"><strong>修改</strong><span>从“做一个历史浏览器”转向“长会话变成可继续使用的工作记忆”。</span></div>
      <div class="diff-item keep"><strong>保留证据</strong><span>消息 1 和消息 2 仍然是这张记忆卡的来源引用。</span></div>
    </div>
  `;
}

function commitValue(commit) {
  const message = commit.message || "";
  if (message.includes("save episode reasoning graph")) {
    return "保存 episode、报告、步骤节点和证据引用。";
  }
  if (message.includes("sync")) {
    return "保存原始 Codex transcript，作为后续复盘的事实来源。";
  }
  if (message.includes("seed")) {
    return "创建可以记录后续变更的本地版本库。";
  }
  return "保存一次可追溯的数据库变更。";
}

function visibleCommits(commits) {
  const latestSummary = commits.find((commit) =>
    (commit.message || "").includes("save episode reasoning graph"),
  );
  const sync = commits.find((commit) => (commit.message || "").includes("sync"));
  const seed = commits.find((commit) => (commit.message || "").includes("seed"));
  return [latestSummary, sync, seed].filter(Boolean);
}

function commitLabel(commit, index, total) {
  const message = commit.message || "";
  if (message.includes("save episode reasoning graph")) {
    return {
      title: "生成/更新工作记忆",
      copy: "点击查看这次模型更新改变了哪些结论。",
    };
  }
  if (message.includes("sync")) {
    return {
      title: "导入 Codex 会话",
      copy: "保留原始 transcript，作为可追溯证据。",
    };
  }
  if (message.includes("seed")) {
    return {
      title: "创建本地记忆库",
      copy: "初始化 PollyDB store 和版本历史。",
    };
  }
  return {
    title: index === total - 1 ? "初始化" : "更新记忆",
    copy: message || "Saved a versioned change.",
  };
}

function renderGraph(nodes) {
  const stage = document.getElementById("graphStage");
  stage.innerHTML = "";
  nodes.forEach((node) => {
    const card = document.createElement("button");
    card.type = "button";
    card.className = "graph-node";
    card.dataset.kind = node.kind || "node";
    card.dataset.nodeId = node.node_id;
    card.innerHTML = `
      <div class="node-kind">${escapeHtml(kindLabels[node.kind] || node.kind || "step")}</div>
      <div class="node-title">${escapeHtml(titleLabels[node.kind] || node.title || node.node_id)}</div>
      <div class="node-content">${escapeHtml(node.content || "")}</div>
      <div class="node-meta"><span>来自消息 ${node.start_seq ?? 0}-${node.end_seq ?? 0}</span></div>
    `;
    card.addEventListener("click", () => selectNode(node.node_id, window.__demoData));
    stage.appendChild(card);
  });
}

function selectNode(nodeId, data) {
  if (!nodeId || !data) return;
  selectedNodeId = nodeId;
  document.querySelectorAll(".graph-node").forEach((node) => {
    node.classList.toggle("active", node.dataset.nodeId === selectedNodeId);
  });
  const graph = data.graph || {};
  const node = (graph.nodes || []).find((item) => item.node_id === nodeId) || {};
  document.getElementById("detailTitle").textContent =
    titleLabels[node.kind] || node.title || node.node_id || "Step";
  document.getElementById("detailContent").textContent = node.content || "";
  renderEvidence(node, data);
  renderNodeMemory(node, data);
}

function renderNodeMemory(node, data) {
  const label = document.getElementById("memoryLabel");
  const block = document.getElementById("memoryBlock");
  const report = data.graph?.report || {};
  if (node.kind === "outcome") {
    label.textContent = "完整记忆卡";
    block.className = "memory-block memory-card";
    block.textContent = report.summary_md || node.content || "";
    return;
  }
  label.textContent = "这一步的产物";
  block.className = "memory-block";
  block.innerHTML = stepTakeawayHtml(node, data);
}

function stepTakeawayHtml(node, data) {
  const messageCount = data.entries?.length || 0;
  const refCount = data.graph?.episode?.source_refs?.length || 0;
  if (node.kind === "problem") {
    return `
      <p>这一步只识别用户当时的问题，还没有产出最终记忆。</p>
      <p class="takeaway">继续看下一步：Agent 如何开始把问题落到当前项目上。</p>
    `;
  }
  if (node.kind === "action") {
    return `
      <p>这一步记录 Agent 的第一反应和处理方向。</p>
      <p class="takeaway">它会作为证据进入最终记忆，但本身不是完整结论。</p>
    `;
  }
  if (node.kind === "evidence") {
    return `
      <p>这一步把 ${escapeHtml(String(messageCount))} 条原始消息压缩成少量关键引用。</p>
      <p>页面只展示最关键的 ${escapeHtml(String(refCount))} 条引用；完整 transcript 仍然作为 PollyDB 版本数据保留。</p>
      <p class="takeaway">好处是：用户不用重读长会话，但每个结论都能追溯回原文和生成它的提交。</p>
    `;
  }
  return `<p>${escapeHtml(node.content || "这一步会进入最终记忆。")}</p>`;
}

function renderEvidence(node, data) {
  const refs = node.source_refs?.length
    ? node.source_refs
    : node.kind === "outcome" || node.kind === "evidence"
      ? data.graph?.episode?.source_refs || []
      : [];
  const list = document.getElementById("evidenceList");
  list.innerHTML = "";
  if (!refs.length) {
    const empty = document.createElement("div");
    empty.className = "evidence";
    empty.innerHTML = `<div class="evidence-text">这一步引用整段会话范围，而不是单条消息。</div>`;
    list.appendChild(empty);
    return;
  }
  refs.forEach((ref) => {
    const item = document.createElement("div");
    item.className = "evidence";
    item.innerHTML = `
      <div class="evidence-key">消息 ${escapeHtml(String(ref.start_seq ?? ""))}</div>
      <div class="evidence-text">${escapeHtml(ref.text || matchingEntryText(ref, data))}</div>
    `;
    list.appendChild(item);
  });
}

function matchingEntryText(ref, data) {
  const seq = Number(ref.start_seq);
  const match = (data.entries || []).find((entry) => Number(entry.seq) === seq);
  return match?.text || "";
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

loadData().then((data) => {
  window.__demoData = data;
  render(data);
});
