/* ===== PollyDB Git-for-Data Demo ===== */

/* --- Field Definitions --- */
const FIELDS = [
  { key: "counterparty", label: "合同对方", confidence: 94 },
  { key: "effective_date", label: "生效日期", confidence: 91 },
  { key: "renewal", label: "续约条款", confidence: 68 },
  { key: "liability_cap", label: "责任上限", confidence: 74 },
];

/* --- Commit Store --- */
let commits = [];
let branches = {};
let currentBranch = "main";
let selectedCommitId = null;
let termLines = [];
let hashCounter = 0;
let lastNewId = null; // for animation

function genHash() {
  hashCounter++;
  const chars = "0123456789abcdef";
  let h = "";
  for (let i = 0; i < 6; i++) h += chars[(hashCounter * 7 + i * 13) % 16];
  return h;
}

function makeCommit(msg, author, branch, parents, snapshot) {
  const c = { id: genHash(), msg, author, branch, parents, snapshot: { ...snapshot }, time: Date.now() };
  commits.push(c);
  branches[branch] = c.id;
  return c;
}

function getCommit(id) { return commits.find(c => c.id === id); }

function emptySnapshot() {
  const s = {};
  FIELDS.forEach(f => s[f.key] = "—");
  return s;
}

/* --- Seed History --- */
function seedHistory() {
  commits = []; branches = {}; hashCounter = 0; currentBranch = "main"; termLines = []; lastNewId = null;

  const s0 = emptySnapshot();
  const c0 = makeCommit("init: import contract ACME-1042", "system", "main", [], s0);

  const s1 = { counterparty: "ACME Robotics Ltd.", effective_date: "2026-04-01", renewal: "Auto-renews annually (30 days notice)", liability_cap: "12 months fees" };
  const c1 = makeCommit("extract: AI extraction complete", "ai-engine", "main", [c0.id], s1);

  const s2 = { ...s1 };
  const c2 = makeCommit("approve: auto-approve high-confidence fields", "policy-bot", "main", [c1.id], s2);

  const s3 = { ...s2, renewal: "Auto-renews annually (60 days notice)" };
  const c3 = makeCommit("fix: renewal 30→60 days notice", "reviewer-legal", "review/legal", [c2.id], s3);

  const s4 = { ...s2, liability_cap: "12 months fees (paid or payable)" };
  const c4 = makeCommit("fix: clarify liability cap wording", "reviewer-finance", "review/finance", [c2.id], s4);

  const s5 = { ...s3 };
  const c5 = makeCommit("merge: review/legal → main", "system", "main", [c2.id, c3.id], s5);

  const s6 = { ...s5, liability_cap: s4.liability_cap };
  const c6 = makeCommit("merge: review/finance → main", "system", "main", [c5.id, c4.id], s6);

  selectedCommitId = c6.id;
  currentBranch = "main";

  termPrint("prompt", `$ pollydb log --graph --oneline`);
  termPrint("output", formatLog());
}

/* --- Terminal --- */
function termPrint(type, text) { termLines.push({ type, text }); renderTerminal(); }
function termCmd(cmd) { termPrint("prompt", `$ pollydb ${cmd}`); }
function termOutput(text) { termPrint("output", text); }
function termHighlight(text) { termPrint("highlight", text); }

function renderTerminal() {
  const body = document.getElementById("terminalBody");
  body.innerHTML = termLines.map(l => {
    if (l.type === "prompt") return `<div class="term-line"><span class="prompt">❯</span> <span class="cmd">${esc(l.text.replace("$ pollydb ", ""))}</span></div>`;
    if (l.type === "highlight") return `<div class="term-line"><span class="highlight">${esc(l.text)}</span></div>`;
    return `<div class="term-line"><span class="output">${esc(l.text)}</span></div>`;
  }).join("") + `<div class="term-line"><span class="prompt">❯</span> <span class="term-cursor"></span></div>`;
  body.scrollTop = body.scrollHeight;
}

function formatLog() {
  return commits.slice().reverse().map(c => {
    const tag = c.branch !== "main" ? ` (${c.branch})` : "";
    const merge = c.parents.length > 1 ? " ⑂" : "";
    return `  ${c.id} ${c.msg}${tag}${merge}`;
  }).join("\n");
}

/* --- DAG Layout & Render --- */
const LANE_X = { main: 55, "review/legal": 150, "review/finance": 245 };
const ROW_H = 72;
const NODE_R = 8;
const PAD_TOP = 24;

function laneClass(branch, isMerge) {
  if (isMerge) return "merge";
  if (branch === "main") return "main";
  if (branch === "review/legal") return "branch-a";
  return "branch-b";
}

function computeLayout() {
  // Assign rows: topological order, branches share row when parallel
  const rows = [];
  const rowOf = {};
  // Simple approach: iterate commits in order, assign rows
  // Parallel branches get same row
  let row = 0;
  for (let i = 0; i < commits.length; i++) {
    const c = commits[i];
    if (i > 0) {
      const prev = commits[i - 1];
      // If same parents as prev (parallel branch), same row
      if (c.parents.length === 1 && prev.parents.length === 1 &&
          c.parents[0] === prev.parents[0] && c.branch !== prev.branch) {
        // same row
      } else {
        row++;
      }
    }
    rowOf[c.id] = row;
  }
  return rowOf;
}

function renderGraph() {
  const svg = document.getElementById("dagSvg");
  document.getElementById("commitCount").textContent = `${commits.length} commits`;
  const rowOf = computeLayout();
  const maxRow = Math.max(...Object.values(rowOf));
  const svgH = PAD_TOP * 2 + maxRow * ROW_H + 30;
  svg.setAttribute("height", svgH);
  svg.setAttribute("viewBox", `0 0 300 ${svgH}`);

  let html = "";

  // Draw edges first (behind nodes)
  commits.forEach(c => {
    const cx = LANE_X[c.branch] || 55;
    const cy = PAD_TOP + rowOf[c.id] * ROW_H;
    c.parents.forEach(pid => {
      const p = getCommit(pid);
      if (!p) return;
      const px = LANE_X[p.branch] || 55;
      const py = PAD_TOP + rowOf[p.id] * ROW_H;
      const isMerge = c.parents.length > 1;
      const cls = laneClass(c.branch, isMerge && pid !== c.parents[0]);
      // Cubic bezier
      const midY = (py + cy) / 2;
      html += `<path class="dag-edge ${cls}" d="M${px},${py} C${px},${midY} ${cx},${midY} ${cx},${cy}"/>`;
    });
  });

  // Draw nodes
  commits.forEach(c => {
    const cx = LANE_X[c.branch] || 55;
    const cy = PAD_TOP + rowOf[c.id] * ROW_H;
    const cls = laneClass(c.branch, c.parents.length > 1);
    const active = c.id === selectedCommitId ? " active" : "";
    const isNew = c.id === lastNewId ? " new-node" : "";
    const label = c.msg.length > 22 ? c.msg.slice(0, 21) + "…" : c.msg;
    // Text on right side of node
    const tx = cx + 16;
    html += `<g class="dag-node${active}${isNew}" data-id="${c.id}">
      <circle class="node-dot ${cls}" cx="${cx}" cy="${cy}" r="${NODE_R}"/>
      <text class="node-label" x="${tx}" y="${cy - 3}">${esc(label)}</text>
      <text class="node-sub" x="${tx}" y="${cy + 11}">${c.id} · ${esc(c.author)}</text>
      <text class="node-branch ${cls}" x="${tx}" y="${cy + 23}">${esc(c.branch)}</text>
    </g>`;
  });

  svg.innerHTML = html;

  // Bind clicks
  svg.querySelectorAll(".dag-node").forEach(el => {
    el.addEventListener("click", () => timeTravelTo(el.dataset.id));
  });
}

/* --- Render --- */
function render() {
  renderGraph();
  renderDataTable();
  renderDiff();
  renderYaml();
  renderBranchBadge();
  renderFieldSelect();
}

function renderBranchBadge() {
  document.getElementById("currentBranch").textContent = currentBranch;
}

function renderDataTable() {
  const commit = getCommit(selectedCommitId);
  if (!commit) return;
  document.getElementById("snapshotTitle").textContent = `@ ${commit.id}`;
  // Commit audit info bar
  document.getElementById("commitAuthor").textContent = commit.author;
  document.getElementById("commitMsg").textContent = commit.msg;
  const parent = commit.parents.length > 0 ? getCommit(commit.parents[0]) : null;
  const table = document.getElementById("dataTable");
  table.innerHTML = `
    <thead><tr>
      <th>字段</th><th>当前值</th><th>置信度</th>
    </tr></thead>
    <tbody>${FIELDS.map(f => {
      const val = commit.snapshot[f.key] || "—";
      const oldVal = parent ? (parent.snapshot[f.key] || "—") : "—";
      const changed = val !== oldVal ? " changed" : "";
      const confClass = f.confidence >= 85 ? "high" : f.confidence >= 70 ? "medium" : "low";
      return `<tr>
        <td class="col-field">${esc(f.label)}</td>
        <td class="col-value${changed}">${esc(val)}</td>
        <td class="col-conf"><span class="conf-badge ${confClass}">${f.confidence}%</span></td>
      </tr>`;
    }).join("")}</tbody>`;
}

function renderDiff() {
  const commit = getCommit(selectedCommitId);
  if (!commit) return;
  const parent = commit.parents.length > 0 ? getCommit(commit.parents[0]) : null;
  const label = document.getElementById("diffLabel");
  const list = document.getElementById("diffList");

  if (!parent) {
    label.textContent = "initial commit";
    list.innerHTML = `<div class="diff-empty">初始提交，无父版本可比较。</div>`;
    return;
  }

  label.textContent = `${parent.id} → ${commit.id}`;
  const changes = FIELDS.filter(f => (commit.snapshot[f.key] || "—") !== (parent.snapshot[f.key] || "—"));
  if (changes.length === 0) {
    list.innerHTML = `<div class="diff-empty">此提交未修改字段值（merge / approve 操作）。</div>`;
    return;
  }
  list.innerHTML = changes.map((f, i) => `
    <div class="diff-item" style="animation-delay:${i * 60}ms">
      <span class="diff-field">${esc(f.label)}</span>
      <span class="diff-old">${esc(parent.snapshot[f.key] || "—")}</span>
      <span class="diff-new">${esc(commit.snapshot[f.key] || "—")}</span>
    </div>`).join("");
}

function renderFieldSelect() {
  const sel = document.getElementById("fieldSelect");
  sel.innerHTML = FIELDS.map(f => `<option value="${f.key}">${esc(f.label)}</option>`).join("");
}

function renderYaml() {
  const yaml = `# PollyDB Typed DDL — extracted_fields.yml
# pollydb schema register extracted_fields.yml

schema_version: 1

tables:
  - name: extracted_fields
    description: "合同 AI 抽取结果，带版本历史"
    primary_key: [doc_id, field_key]
    columns:
      - name: doc_id
        type: string
        nullable: false
      - name: field_key
        type: string
        nullable: false
      - name: field_label
        type: string
        nullable: false
      - name: ai_value
        type: string
        nullable: false
      - name: reviewed_value
        type: string
        nullable: true
      - name: confidence
        type: i64
        nullable: false
      - name: reviewer
        type: string
        nullable: true
      - name: created_at
        type: datetime
        nullable: false
        default_current_timestamp: true
      - name: updated_at
        type: datetime
        nullable: false
        default_current_timestamp: true
        auto_update_current_timestamp: true
    indexes:
      - name: fields_doc_idx
        kind: column
        column: doc_id
      - name: fields_confidence_idx
        kind: column
        column: confidence
      - name: fields_cover_idx
        kind: covering_projected
        column: doc_id
        stored_columns: [field_key, ai_value, reviewed_value, confidence]`;

  document.getElementById("yamlBlock").innerHTML = highlightYaml(yaml);
}

function highlightYaml(text) {
  return text.split("\n").map(line => {
    if (line.trim().startsWith("#")) return `<span class="y-comment">${esc(line)}</span>`;
    let result = "";
    let rest = line;
    const indentMatch = rest.match(/^(\s*(?:-\s*)?)/);
    if (indentMatch) { result += indentMatch[1]; rest = rest.slice(indentMatch[1].length); }
    const keyMatch = rest.match(/^([\w_]+)(:)/);
    if (keyMatch) {
      result += `<span class="y-key">${esc(keyMatch[1])}</span>${keyMatch[2]}`;
      rest = rest.slice(keyMatch[0].length);
      rest = highlightValue(rest);
      result += rest;
    } else {
      result += highlightValue(esc(rest));
    }
    return result;
  }).join("\n");
}

function highlightValue(s) {
  return s.replace(/("[^"]*")|\b(true|false)\b|\b(\d+)\b|\b(string|i64|datetime|bool|markdown|json)\b/g,
    (m, str, bool, num, type) => {
      if (str) return `<span class="y-str">${str}</span>`;
      if (bool) return `<span class="y-bool">${bool}</span>`;
      if (num) return `<span class="y-num">${num}</span>`;
      if (type) return `<span class="y-type">${type}</span>`;
      return m;
    });
}

/* --- Actions --- */
function timeTravelTo(id) {
  selectedCommitId = id;
  const c = getCommit(id);
  termCmd(`checkout ${id}`);
  termOutput(`HEAD is now at ${id} — ${c.msg}`);
  termHighlight(`⏱ 时间旅行：已回放到 "${c.msg}" 的状态`);
  render();
  showToast("info", "时间旅行", `已切换到 ${id}: ${c.msg}`);
}

function revertToSelected() {
  const target = getCommit(selectedCommitId);
  if (!target) return;
  const head = getCommit(branches[currentBranch]);
  if (target.id === head.id) { showToast("warning", "无需回滚", "当前已在该版本"); return; }

  const c = makeCommit(`revert: rollback to ${target.id}`, "user", currentBranch, [head.id], { ...target.snapshot });
  lastNewId = c.id;
  selectedCommitId = c.id;
  termCmd(`revert --to ${target.id}`);
  termOutput(`Created commit ${c.id} on ${currentBranch}`);
  termHighlight(`⟲ 回滚成功：数据已恢复到 "${target.msg}" 的状态`);
  render();
  showToast("success", "回滚成功", `已创建 revert commit ${c.id}`);
}

function createBranch() {
  const head = getCommit(branches[currentBranch]);
  const name = `feature/edit-${hashCounter}`;
  branches[name] = head.id;
  currentBranch = name;
  termCmd(`branch ${name}`);
  termOutput(`Switched to a new branch '${name}'`);
  termHighlight(`⑂ 新分支 "${name}" 已从 ${head.id} 创建`);
  render();
  showToast("success", "分支已创建", `当前在 ${name}`);
}

function commitEdit() {
  const key = document.getElementById("fieldSelect").value;
  const val = document.getElementById("fieldInput").value.trim();
  if (!val) { showToast("warning", "请输入值", "字段值不能为空"); return; }

  const head = getCommit(branches[currentBranch]);
  const field = FIELDS.find(f => f.key === key);
  const oldVal = head.snapshot[key] || "—";
  if (oldVal === val) { showToast("info", "无变化", "新值与当前值相同"); return; }

  const snap = { ...head.snapshot, [key]: val };
  const c = makeCommit(`edit: ${field.label} = "${val}"`, "user", currentBranch, [head.id], snap);
  lastNewId = c.id;
  selectedCommitId = c.id;
  document.getElementById("fieldInput").value = "";

  termCmd(`commit -m 'edit: ${field.label}'`);
  termOutput(`[${currentBranch} ${c.id}] edit: ${field.label} = "${val}"`);
  termOutput(`  ${field.label}: "${oldVal}" → "${val}"`);
  termHighlight(`✓ 新提交 ${c.id} 已写入 ${currentBranch}`);
  render();
  showToast("success", "Commit 成功", `${field.label} 已更新`);
}

function mergeBranch() {
  if (currentBranch === "main") { showToast("warning", "已在 main", "请先切换到要合并的分支"); return; }
  const branchHead = getCommit(branches[currentBranch]);
  const mainHead = getCommit(branches["main"]);
  if (branchHead.id === mainHead.id) { showToast("info", "无变化", "分支与 main 已同步"); return; }

  const snap = { ...branchHead.snapshot };
  const c = makeCommit(`merge: ${currentBranch} → main`, "user", "main", [mainHead.id, branchHead.id], snap);
  lastNewId = c.id;
  const mergedBranch = currentBranch;
  currentBranch = "main";
  selectedCommitId = c.id;

  termCmd(`merge ${mergedBranch}`);
  termOutput(`Updating ${mainHead.id}..${c.id}`);
  termOutput(`Merge made by the 'recursive' strategy.`);
  termHighlight(`⑂ 分支 "${mergedBranch}" 已合并到 main`);
  render();
  showToast("success", "Merge 完成", `${mergedBranch} → main`);
}

function resetDemo() {
  seedHistory();
  render();
  showToast("info", "已重置", "Demo 恢复到初始状态");
}

/* --- Auto Scenario (branch → parallel → merge story) --- */
async function autoScenario() {
  resetDemo();
  await sleep(800);

  // Step 1: show initial AI extraction
  const c1 = commits[1];
  timeTravelTo(c1.id);
  await sleep(1800);

  // Step 2: show approval
  const c2 = commits[2];
  timeTravelTo(c2.id);
  await sleep(1500);

  // Step 3: show branch edit (legal)
  const c3 = commits[3];
  timeTravelTo(c3.id);
  await sleep(1800);

  // Step 4: show branch edit (finance) — parallel!
  const c4 = commits[4];
  timeTravelTo(c4.id);
  await sleep(1800);

  // Step 5: show merge result
  const c6 = commits[commits.length - 1];
  timeTravelTo(c6.id);
  await sleep(1800);

  // Step 6: user creates branch and edits
  createBranch();
  await sleep(1000);
  document.getElementById("fieldSelect").value = "liability_cap";
  document.getElementById("fieldInput").value = "24 months fees (paid or payable)";
  await sleep(800);
  commitEdit();
  await sleep(1500);

  // Step 7: merge back
  mergeBranch();
  await sleep(1500);

  // Step 8: time travel back to compare
  timeTravelTo(c1.id);
  await sleep(1200);
  timeTravelTo(commits[commits.length - 1].id);
  await sleep(800);

  showToast("success", "演示完成", "分支 → 并行编辑 → 合并 → 时间旅行对比");
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

/* --- Toast --- */
function showToast(type, title, msg) {
  const container = document.getElementById("toastContainer");
  const icons = { success: "✓", warning: "!", info: "i" };
  const toast = document.createElement("div");
  toast.className = `toast ${type}`;
  toast.innerHTML = `<div class="toast-icon">${icons[type] || "i"}</div><div><div class="toast-title">${esc(title)}</div>${msg ? `<div class="toast-msg">${esc(msg)}</div>` : ""}</div>`;
  container.appendChild(toast);
  setTimeout(() => { toast.classList.add("removing"); setTimeout(() => toast.remove(), 220); }, 3000);
}

/* --- Utils --- */
function esc(v) { return String(v ?? "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;"); }

/* --- Onboarding --- */
const ONBOARD_STEPS = [
  { title: "👋 欢迎来到 PollyDB", desc: "这是一个「版本数据库」—— 数据像代码一样拥有提交历史、分支和合并能力。接下来 30 秒带你体验核心功能。" },
  { title: "📊 Commit Graph", desc: "左侧是数据的提交图谱。注意看：review/legal 和 review/finance 从 main 分叉出去，又合并回来 —— 这在 MySQL 里做不到。" },
  { title: "⏱ 时间旅行", desc: "点击任意 commit 节点，中间表格会瞬间回放到那个时间点的数据状态。修改过的字段会高亮闪烁。" },
  { title: "🚀 试一试", desc: "在右侧修改一个字段并 Commit，或者点击「自动演示」观看完整的 分支→并行编辑→合并→回滚 流程。" },
];
let onboardIdx = 0;

function showOnboard() {
  onboardIdx = 0;
  renderOnboard();
  document.getElementById("onboardOverlay").classList.remove("hidden");
}

function renderOnboard() {
  const s = ONBOARD_STEPS[onboardIdx];
  document.getElementById("onboardStep").textContent = `${onboardIdx + 1} / ${ONBOARD_STEPS.length}`;
  document.getElementById("onboardTitle").textContent = s.title;
  document.getElementById("onboardDesc").textContent = s.desc;
  document.getElementById("onboardNext").textContent = onboardIdx === ONBOARD_STEPS.length - 1 ? "开始体验 ✓" : "下一步 →";
}

function nextOnboard() {
  onboardIdx++;
  if (onboardIdx >= ONBOARD_STEPS.length) {
    document.getElementById("onboardOverlay").classList.add("hidden");
    return;
  }
  renderOnboard();
}

function skipOnboard() {
  document.getElementById("onboardOverlay").classList.add("hidden");
}

/* --- Tab Switching --- */
document.getElementById("tabData").addEventListener("click", () => switchTab("data"));
document.getElementById("tabSchema").addEventListener("click", () => switchTab("schema"));

function switchTab(tab) {
  document.getElementById("tabData").classList.toggle("active", tab === "data");
  document.getElementById("tabSchema").classList.toggle("active", tab === "schema");
  document.getElementById("panelData").classList.toggle("active", tab === "data");
  document.getElementById("panelSchema").classList.toggle("active", tab === "schema");
}

/* --- Bindings --- */
document.getElementById("revertBtn").addEventListener("click", revertToSelected);
document.getElementById("branchBtn").addEventListener("click", createBranch);
document.getElementById("editCommitBtn").addEventListener("click", commitEdit);
document.getElementById("mergeBtn").addEventListener("click", mergeBranch);
document.getElementById("resetBtn").addEventListener("click", resetDemo);
document.getElementById("scenarioBtn").addEventListener("click", autoScenario);
document.getElementById("fieldInput").addEventListener("keydown", e => { if (e.key === "Enter") commitEdit(); });
document.getElementById("onboardNext").addEventListener("click", nextOnboard);
document.getElementById("onboardSkip").addEventListener("click", skipOnboard);

/* --- Init --- */
seedHistory();
render();
showOnboard();
