const conversations = [
  {
    title: "职业判断",
    turn: 4,
    question: "杰弗里・辛顿为什么被称为 AI 教父？",
    answer: "杰弗里・辛顿（Geoffrey Hinton）被称为“AI 教父 / 深度学习之父”的核心原因，是他在 AI 寒冬中坚持神经网络研究，推动反向传播，并通过深度学习突破促成了现代 AI 浪潮。",
    tags: ["AI 知识", "杰弗里・辛顿", "反向传播"],
    source: "真实运行中的非私人知识问答（已去标识）",
    query: "杰弗里 辛顿 反向传播"
  },
  {
    title: "本地知识库与语义搜索",
    turn: 3,
    question: "如果用户只记得大概意思，怎样在本地找到原来的那次问答？",
    answer: "可以先建立问答轮次索引，再结合关键词召回与语义重排。完整内容和检索索引都保留在本机。",
    tags: ["本地", "语义搜索", "隐私"],
    source: "合成演示内容",
    query: "本地 搜索"
  },
  {
    title: "论文创新点与研究设计",
    turn: 5,
    question: "数字化转型如何影响制造企业的供应链韧性？",
    answer: "供应链韧性可以从信息可见性、协同响应速度与风险预测能力三个机制展开。",
    tags: ["论文", "数字化转型", "供应链韧性"],
    source: "合成演示内容",
    query: "数字化转型 供应链韧性"
  }
];

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
let scope = "all";
let guideStep = 0;

const esc = value => String(value).replace(/[&<>"]/g, char => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[char]));
const words = value => value.trim().toLowerCase().split(/[\s,，。；;]+/).filter(Boolean);
const textFor = (conversation, selectedScope) => selectedScope === "question"
  ? conversation.question
  : selectedScope === "answer"
    ? conversation.answer
    : selectedScope === "title"
      ? conversation.title
      : [conversation.title, conversation.question, conversation.answer, conversation.tags.join(" ")].join(" ");

function mark(text, terms) {
  let output = esc(text);
  terms.forEach(term => {
    if (term.length > 1) output = output.replace(new RegExp(esc(term), "ig"), match => `<mark>${match}</mark>`);
  });
  return output;
}

function resultCard(conversation, terms, index) {
  return `<article class="result-card">
    <div class="result-top"><h3>${esc(conversation.title)}</h3><span class="turn">第 ${conversation.turn} 轮</span></div>
    <p><b>你问：</b>${mark(conversation.question, terms)}<br><b>豆包：</b>${mark(conversation.answer, terms)}</p>
    <div class="result-foot"><span>${conversation.tags.map(tag => `#${esc(tag)}`).join("　")}</span><button class="locate" data-index="${index}">打开并定位</button></div>
  </article>`;
}

function emptyState() {
  return `<div class="empty-state">
    <div class="quote-icon">❞</div><h2>可以开始搜索了</h2>
    <p>演示库包含 3 个对话、6 条消息。</p>
    <div><button id="historyEmpty" class="mac-button">浏览演示历史</button><button id="exampleButton" class="mac-button primary">试用示例搜索</button></div>
  </div>`;
}

function render() {
  const terms = words($("#query").value);
  const rules = $$(".rule").map(rule => ({
    logic: rule.children[0].value,
    scope: rule.children[1].value,
    query: rule.querySelector("input").value.trim().toLowerCase()
  })).filter(rule => rule.query);

  if (!terms.length && !rules.length) {
    $("#results").innerHTML = emptyState();
    return;
  }

  const matches = conversations.map((conversation, index) => ({conversation, index})).filter(({conversation}) => {
    if (!terms.every(term => textFor(conversation, scope).toLowerCase().includes(term))) return false;
    const positive = rules.filter(rule => rule.logic === "and");
    const optional = rules.filter(rule => rule.logic === "or");
    const negative = rules.filter(rule => rule.logic === "not");
    const hit = rule => textFor(conversation, rule.scope).toLowerCase().includes(rule.query);
    return positive.every(hit) && (!optional.length || optional.some(hit)) && negative.every(rule => !hit(rule));
  });
  const highlights = [...terms, ...rules.map(rule => rule.query)];
  $("#results").innerHTML = matches.length
    ? `<div class="result-list">${matches.map(({conversation, index}) => resultCard(conversation, highlights, index)).join("")}</div>`
    : `<div class="empty-state"><div class="quote-icon">❞</div><h2>没有找到匹配内容</h2><p>换一种说法，或调整高级搜索条件。</p></div>`;
}

function renderHistory() {
  $("#historyList").innerHTML = conversations.map((conversation, index) => `<article class="history-card">
    <header><h3>${esc(conversation.title)}</h3><span class="turn">第 ${conversation.turn} 轮</span></header>
    <p><b>你问：</b>${esc(conversation.question)}<br><b>豆包：</b>${esc(conversation.answer)}</p>
    <footer><span>${esc(conversation.source)}</span><button class="use-history" data-index="${index}">用这条线索搜索</button></footer>
  </article>`).join("");
}

function openSheet(id) {
  $(`#${id}`).hidden = false;
  $(`#${id} .close-sheet`).focus();
}

function closeSheet(id) {
  $(`#${id}`).hidden = true;
}

function runExample() {
  closeSheet("historyModal");
  $("#query").value = conversations[0].query;
  render();
  $("#query").focus();
  toast("已用三个模糊线索命中真实知识问答");
}

function showLocated(index) {
  const conversation = conversations[index];
  $("#locatedConversation").innerHTML = `<div class="located-meta">${esc(conversation.title)} · 第 ${conversation.turn} 轮 · 问题命中</div>
    <div class="located-question"><b>你的问题</b><p>${esc(conversation.question)}</p></div>
    <div class="located-answer"><b>豆包回答</b><p>${esc(conversation.answer)}</p></div>
    <div class="located-note">这是浏览器中的安全模拟。真实豆迹会打开豆包原对话、滚动到这一轮，并用蓝色边框高亮目标；演示不会读取访问者的豆包数据。</div>`;
  openSheet("locateModal");
}

$("#query").addEventListener("input", render);
$(".segmented").onclick = event => {
  const button = event.target.closest("[data-scope]");
  if (!button) return;
  $$('[data-scope]').forEach(item => item.classList.remove("active"));
  button.classList.add("active");
  scope = button.dataset.scope;
  render();
};
$("#syncButton").onclick = () => toast("演示模式：不会读取你的豆包；桌面应用可执行真实同步");
$("#fullSync").onclick = () => toast("演示模式：完整同步仅在桌面应用中运行");
$("#historyToggle").onclick = () => openSheet("historyModal");
$("#guidedExample").onclick = runExample;

$("#advancedToggle").onclick = () => {
  const panel = $("#advancedPanel");
  const open = panel.hidden;
  panel.hidden = !open;
  $("#advancedToggle").textContent = open ? "普通搜索" : "高级搜索";
  if (open && !$(".rule")) addRule();
};

function addRule() {
  if ($$(".rule").length >= 6) return;
  const fragment = $("#ruleTemplate").content.cloneNode(true);
  const rule = fragment.querySelector(".rule");
  rule.querySelector(".remove-rule").onclick = () => { rule.remove(); render(); };
  rule.querySelectorAll("input,select").forEach(control => control.addEventListener("input", render));
  $("#rules").append(fragment);
}
$("#addRule").onclick = addRule;

document.addEventListener("click", event => {
  if (event.target.id === "historyEmpty") openSheet("historyModal");
  if (event.target.id === "exampleButton") runExample();

  const closeButton = event.target.closest("[data-close]");
  if (closeButton) closeSheet(closeButton.dataset.close);

  const historyButton = event.target.closest(".use-history");
  if (historyButton) {
    const conversation = conversations[Number(historyButton.dataset.index)];
    closeSheet("historyModal");
    $("#query").value = conversation.query;
    render();
    $("#query").focus();
  }

  const locateButton = event.target.closest(".locate");
  if (locateButton) showLocated(Number(locateButton.dataset.index));

  if (event.target.classList.contains("sheet-backdrop")) closeSheet(event.target.id);
});

document.addEventListener("keydown", event => {
  if (event.key !== "Escape") return;
  $$(".sheet-backdrop").forEach(sheet => { sheet.hidden = true; });
});

function toast(text) {
  const node = document.createElement("div");
  node.className = "toast";
  node.textContent = text;
  document.body.append(node);
  setTimeout(() => node.remove(), 2200);
}

$("#guidedToggle").onclick = () => {
  if (!$("#guidedView").hidden) { back(); return; }
  $("#searchView").hidden = true;
  $("#guidedView").hidden = false;
  $("#guidedToggle").textContent = "返回搜索";
  restartGuide();
};
$("#backButton").onclick = back;

function back() {
  $("#guidedView").hidden = true;
  $("#searchView").hidden = false;
  $("#guidedToggle").textContent = "✦　引导找回";
  guideStep = -1;
}

function assistant(text) { $("#chat").insertAdjacentHTML("beforeend", `<div class="bubble assistant">${text}</div>`); }
function user(text) { $("#chat").insertAdjacentHTML("beforeend", `<div class="bubble user">${esc(text)}</div>`); }
function suggestions(items) { $("#suggestions").innerHTML = items.map(item => `<button type="button">${item}</button>`).join(""); }
function restartGuide() {
  guideStep = 0;
  $("#chat").innerHTML = "";
  assistant("先告诉我你大概记得什么。主题、用途或问题语气都可以，不需要是原话。");
  suggestions(["好像和 AI 人物有关", "好像和论文有关", "只记得答案的意思"]);
}
function reply(text) {
  if (!text.trim()) return;
  user(text);
  guideStep += 1;
  if (guideStep === 1) {
    assistant("你更记得它是在解释一位 AI 学者，还是讨论某项技术？如果都不是，也可以自由补充。");
    suggestions(["像是在解释一位学者", "像是在讲反向传播", "都不是"]);
  } else {
    assistant("结合你的补充，目前最可能是下面这轮。你仍可以说“都不是”来换方向。");
    $("#chat").insertAdjacentHTML("beforeend", `<div class="candidate"><b>职业判断 · 第 4 轮</b><span>杰弗里・辛顿为什么被称为 AI 教父？</span></div>`);
    suggestions(["就是这一条", "时间好像更早", "都不是，换个方向"]);
  }
}
$("#guideForm").onsubmit = event => {
  event.preventDefault();
  const input = $("#guideInput");
  reply(input.value);
  input.value = "";
};
$("#suggestions").onclick = event => { if (event.target.tagName === "BUTTON") reply(event.target.textContent); };

renderHistory();
render();
