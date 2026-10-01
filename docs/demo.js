const conversations=[
  {title:"本地知识库与语义搜索",turn:3,question:"如果用户只记得大概意思，怎样在本地找到原来的那次问答？",answer:"可以先建立问答轮次索引，再结合关键词召回与语义重排。完整内容和检索索引都保留在本机。",tags:["本地","语义搜索","隐私"]},
  {title:"论文创新点与研究设计",turn:5,question:"数字化转型如何影响制造企业的供应链韧性？",answer:"供应链韧性可以从信息可见性、协同响应速度与风险预测能力三个机制展开。",tags:["论文","数字化转型","供应链韧性"]},
  {title:"个人知识管理产品设计",turn:7,question:"轻量知识管理工具最重要的产品原则是什么？",answer:"减少整理成本，让用户先找回内容，再决定是否分类；默认本地存储。",tags:["产品设计","知识管理","轻量"]}
];
const $=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
let scope="all",guideStep=0;
const esc=s=>s.replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
const words=s=>s.trim().toLowerCase().split(/[\s,，。；;]+/).filter(Boolean);
const textFor=(c,s)=>s==="question"?c.question:s==="answer"?c.answer:s==="title"?c.title:[c.title,c.question,c.answer,c.tags.join(" ")].join(" ");
function mark(text,terms){let out=esc(text);terms.forEach(t=>{if(t.length>1)out=out.replace(new RegExp(esc(t),"ig"),m=>`<mark>${m}</mark>`)});return out}
function card(c,terms){return `<article class="result-card"><div class="result-top"><h3>${esc(c.title)}</h3><span class="turn">第 ${c.turn} 轮</span></div><p><b>你问：</b>${mark(c.question,terms)}<br><b>豆包：</b>${mark(c.answer,terms)}</p><div class="result-foot"><span>${c.tags.map(x=>"#"+x).join("　")}</span><button class="locate" data-title="${esc(c.title)}">打开并定位</button></div></article>`}
function render(){
  const terms=words($("#query").value);
  const rules=$$(".rule").map(r=>({logic:r.children[0].value,scope:r.children[1].value,query:r.querySelector("input").value.trim().toLowerCase()})).filter(r=>r.query);
  if(!terms.length&&!rules.length){$("#results").innerHTML=`<div class="empty-state"><div class="quote-icon">❞</div><h2>可以开始搜索了</h2><p>已索引 44 个对话、218 条消息。</p><div><button id="exampleButton" class="mac-button">同步豆包</button><button class="mac-button">导入 JSON</button></div></div>`;return}
  const matches=conversations.filter(c=>{
    if(!terms.every(t=>textFor(c,scope).toLowerCase().includes(t)))return false;
    const positive=rules.filter(r=>r.logic==="and"),optional=rules.filter(r=>r.logic==="or"),negative=rules.filter(r=>r.logic==="not");
    const hit=r=>textFor(c,r.scope).toLowerCase().includes(r.query);
    return positive.every(hit)&&(!optional.length||optional.some(hit))&&negative.every(r=>!hit(r));
  });
  const highlights=[...terms,...rules.map(r=>r.query)];
  $("#results").innerHTML=matches.length?`<div class="result-list">${matches.map(c=>card(c,highlights)).join("")}</div>`:`<div class="empty-state"><div class="quote-icon">❞</div><h2>没有找到匹配内容</h2><p>换一种说法，或调整高级搜索条件。</p></div>`;
}
$("#query").addEventListener("input",render);
$(".segmented").onclick=e=>{const b=e.target.closest("[data-scope]");if(!b)return;$$("[data-scope]").forEach(x=>x.classList.remove("active"));b.classList.add("active");scope=b.dataset.scope;render()};
$("#syncButton").onclick=()=>toast("演示：同步完成，新增 2 个对话");
$("#fullSync").onclick=()=>toast("演示：已完成全部历史同步");
$("#advancedToggle").onclick=()=>{const p=$("#advancedPanel"),open=p.hidden;p.hidden=!open;$("#advancedToggle").textContent=open?"普通搜索":"高级搜索";if(open&&!$(".rule"))addRule()};
function addRule(){if($$(".rule").length>=6)return;const n=$("#ruleTemplate").content.cloneNode(true),r=n.querySelector(".rule");r.querySelector(".remove-rule").onclick=()=>{r.remove();render()};r.querySelectorAll("input,select").forEach(control=>control.addEventListener("input",render));$("#rules").append(n)}
$("#addRule").onclick=addRule;
document.addEventListener("click",e=>{if(e.target.id==="exampleButton"){$("#query").value="本地 搜索";render()}const b=e.target.closest(".locate");if(b)toast(`演示：已定位“${b.dataset.title}”中的命中轮次`)});
function toast(text){const n=document.createElement("div");n.className="toast";n.textContent=text;document.body.append(n);setTimeout(()=>n.remove(),2200)}
$("#guidedToggle").onclick=()=>{if(!$("#guidedView").hidden){back();return}$("#searchView").hidden=true;$("#guidedView").hidden=false;$("#guidedToggle").textContent="返回搜索";restartGuide()};
$("#backButton").onclick=back;
function back(){$("#guidedView").hidden=true;$("#searchView").hidden=false;$("#guidedToggle").textContent="✦　引导找回";guideStep=-1}
function assistant(t){$("#chat").insertAdjacentHTML("beforeend",`<div class="bubble assistant">${t}</div>`)}function user(t){$("#chat").insertAdjacentHTML("beforeend",`<div class="bubble user">${esc(t)}</div>`)}
function suggestions(items){$("#suggestions").innerHTML=items.map(x=>`<button type="button">${x}</button>`).join("")}
function restartGuide(){guideStep=0;$("#chat").innerHTML="";assistant("先告诉我你大概记得什么。主题、用途或问题语气都可以，不需要是原话。");suggestions(["好像和论文有关","是一次产品讨论","只记得答案的意思"])}
function reply(t){if(!t.trim())return;user(t);guideStep++;if(guideStep===1){assistant("你更记得它是在讨论研究方法，还是企业经营问题？如果都不是，也可以自由补充。");suggestions(["更像研究方法与论文","更像企业经营分析","都不是"])}else{assistant("结合你的补充，目前最可能是下面这轮。");$("#chat").insertAdjacentHTML("beforeend",`<div class="candidate"><b>论文创新点与研究设计 · 第 5 轮</b><span>数字化转型如何影响制造企业的供应链韧性？</span></div>`);suggestions(["就是这一条","时间好像更早","都不是，换个方向"])}}
$("#guideForm").onsubmit=e=>{e.preventDefault();const i=$("#guideInput");reply(i.value);i.value=""};$("#suggestions").onclick=e=>{if(e.target.tagName==="BUTTON")reply(e.target.textContent)};
render();
