/* MZAD PHONE — حارس المنصة
   يعرض للمستخدم: وضع الصيانة / وضع الانتظار (إطار يتدلّى وينزل على خلفية بيضاء)، شاشة الحظر،
   شريط الإعلان، وشريط تقييد الحساب. يقرأ mzad_public_status كل 20 ثانية.
   الاستعمال في أي صفحة:  <script type="module" src="./js/platform-guard.js"></script>
   (داخل admin/ استعمل ../js/platform-guard.js — الحارس يتجاهل صفحات الإدارة وتسجيل دخولها تلقائياً) */
import { supabase } from "./supabase.js";

/* رقم الدعم يظهر داخل الإطار فقط إذا فعّلت خيار «إظهار رقم التواصل» من لوحة الإدارة */
const SUPPORT_PHONE = "07838003991";
const POLL_MS = 20000;

const path = location.pathname.toLowerCase();
const SKIP = document.documentElement.hasAttribute("data-no-guard") || /\/admin(\/|-)/.test(path) || /admin-login/.test(path);

const esc = v => String(v ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const t2 = n => String(n).padStart(2, "0");

/* ===== الأنماط ===== */
const CSS = `
.pg-ov{position:fixed;inset:0;z-index:2147483000;background:#fff;overflow:hidden;display:flex;justify-content:center;direction:rtl;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Tahoma,Arial,sans-serif;opacity:1;transition:opacity .55s ease .35s}
.pg-ov.pg-out{opacity:0;pointer-events:none}
.pg-ov:before{content:"";position:absolute;inset:0;background:radial-gradient(circle at 50% 0,#f5f2ff 0,#fff 55%);pointer-events:none}
.pg-drop{position:absolute;top:0;left:50%;width:min(88vw,360px);margin-left:calc(min(88vw,360px) / -2);transform:translateY(-130%);animation:pgDrop 1.1s cubic-bezier(.3,1.35,.5,1) .15s forwards}
.pg-out .pg-drop{animation:pgLeave .85s cubic-bezier(.6,-.2,.7,.2) forwards}
.pg-swing{transform-origin:50% 0;animation:pgSway 5.2s ease-in-out 1.2s infinite}
.pg-nail{position:relative;width:14px;height:14px;margin:0 auto;border-radius:50%;background:radial-gradient(circle at 35% 30%,#a99cf0,#6246d9 60%,#4a34b8);box-shadow:0 2px 5px rgba(98,70,217,.4);z-index:3;margin-top:calc(env(safe-area-inset-top,0px) + 8px)}
.pg-strings{position:relative;height:clamp(70px,16vh,130px);margin:-4px 0 -6px}
.pg-strings i{position:absolute;top:0;bottom:0;width:2px;background:linear-gradient(#c9c0f3,#8d7be6);transform-origin:50% 0}
.pg-strings i:first-child{right:50%;transform:rotate(-17deg)}
.pg-strings i:last-child{left:50%;transform:rotate(17deg)}
.pg-card{position:relative;padding:26px 22px 22px;border-radius:28px;background:#fff;border:2px solid #e4defa;text-align:center;box-shadow:0 0 0 7px #f3f0ff,0 30px 60px -22px rgba(98,70,217,.42)}
.pg-card:before,.pg-card:after{content:"";position:absolute;top:-6px;width:12px;height:12px;border-radius:50%;background:#fff;border:3px solid #8d7be6}
.pg-card:before{right:16%;transform:translateX(50%)}.pg-card:after{left:16%;transform:translateX(-50%)}
.pg-ico{width:96px;height:96px;margin:0 auto 12px;display:grid;place-items:center;border-radius:50%;background:#f3f0ff}
.pg-ico svg{width:70px;height:70px;overflow:visible}
.pg-badge{display:inline-flex;align-items:center;gap:6px;padding:5px 13px;border-radius:999px;background:#f3f0ff;color:#4a34b8;font-size:11px;font-weight:900;letter-spacing:.02em}
.pg-badge:before{content:"";width:7px;height:7px;border-radius:50%;background:#6246d9;animation:pgBlink 1.4s infinite}
.pg-card h2{margin:12px 0 8px;font-size:23px;font-weight:950;color:#17202a;letter-spacing:-.02em}
.pg-card p{margin:0;font-size:13.5px;font-weight:600;line-height:1.95;color:#555a78;white-space:pre-line}
.pg-dots{display:flex;justify-content:center;gap:7px;margin-top:14px}
.pg-dots b{width:9px;height:9px;border-radius:50%;background:#6246d9;animation:pgDot 1.2s ease-in-out infinite}
.pg-dots b:nth-child(2){animation-delay:.18s}.pg-dots b:nth-child(3){animation-delay:.36s}
.pg-eta{margin-top:16px;padding:12px;border-radius:16px;background:#f8f6ff;border:1px solid #ece8fb}
.pg-eta small{display:block;font-size:11px;font-weight:800;color:#6b7280}
.pg-eta b{display:block;margin-top:3px;font-size:26px;font-weight:950;color:#4a34b8;font-variant-numeric:tabular-nums;direction:ltr;letter-spacing:.02em}
.pg-bar{height:5px;margin-top:16px;border-radius:9px;background:#ece8fb;overflow:hidden}
.pg-bar i{display:block;height:100%;width:40%;border-radius:9px;background:linear-gradient(90deg,#6246d9,#a99cf0);animation:pgBar 1.8s ease-in-out infinite}
.pg-help{display:inline-flex;align-items:center;justify-content:center;margin-top:14px;min-height:42px;padding:0 18px;border-radius:14px;background:#6246d9;color:#fff;font-size:13px;font-weight:900;text-decoration:none;direction:ltr}
.pg-shadow{position:absolute;left:50%;bottom:7vh;width:min(60vw,240px);height:18px;margin-left:calc(min(60vw,240px) / -2);border-radius:50%;background:radial-gradient(closest-side,rgba(98,70,217,.2),transparent);animation:pgShadow 5.2s ease-in-out 1.2s infinite;opacity:0}
.pg-ov.pg-in .pg-shadow{opacity:1;transition:opacity .8s ease 1s}
.pg-gear{transform-box:fill-box;transform-origin:center;animation:pgSpin 6s linear infinite}
.pg-gear.r{animation-direction:reverse;animation-duration:4s}
.pg-glass{transform-box:fill-box;transform-origin:center;animation:pgFlip 3.2s ease-in-out infinite}
.pg-lock{transform-box:fill-box;transform-origin:50% 100%;animation:pgShake 3s ease-in-out infinite}
.pg-sand{animation:pgSand 3.2s linear infinite}
.pg-ban{position:fixed;left:0;right:0;z-index:2147482000;display:flex;align-items:center;gap:10px;padding:10px 14px;padding-top:calc(10px + env(safe-area-inset-top,0px));font:800 12.5px/1.7 -apple-system,"Segoe UI",Tahoma,Arial,sans-serif;direction:rtl;top:0;transform:translateY(-110%);animation:pgBan .5s cubic-bezier(.2,.9,.3,1) forwards}
.pg-ban.a{background:#4a34b8;color:#fff}.pg-ban.w{background:#fdf3e1;color:#8a5a0e;border-bottom:1px solid #f1d9a6}.pg-ban.i{background:#fff0f3;color:#c62f4d;border-bottom:1px solid #f3cbd4}
.pg-ban span{flex:1}.pg-ban button{flex:none;width:28px;height:28px;border-radius:9px;background:rgba(255,255,255,.18);color:inherit;border:0;font-size:16px;cursor:pointer}
.pg-ban.w button,.pg-ban.i button{background:rgba(0,0,0,.06)}
@keyframes pgDrop{0%{transform:translateY(-130%)}100%{transform:translateY(0)}}
@keyframes pgLeave{0%{transform:translateY(0)}25%{transform:translateY(7%)}100%{transform:translateY(-135%)}}
@keyframes pgSway{0%,100%{transform:rotate(0)}25%{transform:rotate(2.2deg)}75%{transform:rotate(-2.2deg)}}
@keyframes pgShadow{0%,100%{transform:scaleX(1)}25%,75%{transform:scaleX(.88)}50%{transform:scaleX(1.05)}}
@keyframes pgSpin{to{transform:rotate(360deg)}}
@keyframes pgFlip{0%,40%{transform:rotate(0)}60%,100%{transform:rotate(180deg)}}
@keyframes pgShake{0%,80%,100%{transform:rotate(0)}84%{transform:rotate(-7deg)}88%{transform:rotate(7deg)}92%{transform:rotate(-5deg)}96%{transform:rotate(3deg)}}
@keyframes pgSand{0%{transform:scaleY(1)}40%{transform:scaleY(.25)}100%{transform:scaleY(.25)}}
@keyframes pgDot{0%,80%,100%{transform:translateY(0);opacity:.35}40%{transform:translateY(-7px);opacity:1}}
@keyframes pgBlink{0%,100%{opacity:1}50%{opacity:.25}}
@keyframes pgBar{0%{margin-inline-start:-40%}100%{margin-inline-start:100%}}
@keyframes pgBan{to{transform:none}}
@media(prefers-reduced-motion:reduce){.pg-drop{animation:none;transform:none}.pg-out .pg-drop{animation:none;transform:translateY(-140%)}.pg-swing,.pg-gear,.pg-glass,.pg-lock,.pg-sand,.pg-dots b,.pg-bar i,.pg-shadow,.pg-badge:before{animation:none}.pg-ov{transition-duration:.01s}}
`;
function injectCss(){ if(document.getElementById("pg-css")) return; const s=document.createElement("style"); s.id="pg-css"; s.textContent=CSS; document.head.appendChild(s); }

/* ===== الأيقونات ===== */
const P = "#6246d9", PL = "#a99cf0";
function gear(cx, cy, R, cls){
  const teeth = [0,45,90,135].map(a => `<rect x="${-R*0.18}" y="${-R}" width="${R*0.36}" height="${R*2}" rx="${R*0.1}" transform="rotate(${a})"/>`).join("");
  return `<g class="pg-gear ${cls||""}" transform="translate(${cx} ${cy})"><g fill="${cls==="r"?PL:P}">${teeth}<circle r="${R*0.78}"/></g><circle r="${R*0.36}" fill="#f3f0ff"/></g>`;
}
const ICONS = {
  maintenance: `<svg viewBox="0 0 70 70">${gear(26,30,17)}${gear(51,48,11,"r")}</svg>`,
  waiting: `<svg viewBox="0 0 70 70"><g class="pg-glass"><path d="M20 10h30M20 60h30" stroke="${P}" stroke-width="5" stroke-linecap="round"/><path d="M24 10c0 14 11 17 11 25S24 46 24 60M46 10c0 14-11 17-11 25s11 11 11 25" fill="none" stroke="${P}" stroke-width="3.5" stroke-linecap="round"/><path class="pg-sand" d="M28 14h14c-1 7-7 10-7 14 0-4-6-7-7-14Z" fill="${PL}" style="transform-origin:35px 14px"/><path d="M30 58c2-6 3-8 5-8s3 2 5 8Z" fill="${PL}"/></g></svg>`,
  banned: `<svg viewBox="0 0 70 70"><g class="pg-lock"><rect x="17" y="30" width="36" height="28" rx="8" fill="${P}"/><path d="M24 30v-6a11 11 0 0 1 22 0v6" fill="none" stroke="${P}" stroke-width="5" stroke-linecap="round"/><circle cx="35" cy="43" r="4" fill="#fff"/><path d="M35 45v6" stroke="#fff" stroke-width="3" stroke-linecap="round"/></g></svg>`
};

/* ===== الشاشة الكاملة ===== */
let ov = null, cdTimer = null, curKey = "";
function fmtLeft(ms){ const s=Math.max(0,Math.floor(ms/1000)),h=Math.floor(s/3600),m=Math.floor(s%3600/60); return (h>0?t2(h)+":":"")+t2(m)+":"+t2(s%60); }

function buildCard(o){
  const kind = o.kind;                       /* maintenance | waiting | banned */
  const label = kind==="banned" ? "الحساب موقوف" : kind==="waiting" ? "انتظار قصير" : "صيانة مجدولة";
  const title = o.title || (kind==="banned" ? "تم إيقاف حسابك" : kind==="waiting" ? "وشغله ثانية" : "المنصة تحت الصيانة");
  const msg = o.message || (kind==="banned" ? "تواصل مع الإدارة لمعرفة التفاصيل." : kind==="waiting" ? "نجهّز لك كل شي، ارجع بعد لحظات." : "نحسّن الخدمة لك، وراجعين بأسرع وقت.");
  const eta = o.eta_at && new Date(o.eta_at) > new Date() && kind!=="banned";
  const help = o.show_phone && SUPPORT_PHONE ? `<a class="pg-help" href="tel:${esc(SUPPORT_PHONE)}">${esc(SUPPORT_PHONE)}</a>` : "";
  const reason = kind==="banned" && o.reason ? `<div class="pg-eta"><small>السبب</small><span style="font-size:13px;font-weight:800;color:#17202a">${esc(o.reason)}</span></div>` : "";
  return `<div class="pg-drop"><div class="pg-swing"><div class="pg-nail"></div><div class="pg-strings"><i></i><i></i></div>
    <div class="pg-card"><div class="pg-ico">${ICONS[kind]}</div><span class="pg-badge">${label}</span><h2>${esc(title)}</h2><p>${esc(msg)}</p>
    ${kind==="waiting" ? '<div class="pg-dots"><b></b><b></b><b></b></div>' : kind==="maintenance" && !eta ? '<div class="pg-bar"><i></i></div>' : ""}
    ${eta ? `<div class="pg-eta"><small>الرجوع المتوقع بعد</small><b id="pgEta">--:--</b></div>` : ""}${reason}${help}</div></div></div><div class="pg-shadow"></div>`;
}
function showOverlay(o){
  injectCss();
  const key = [o.kind,o.title,o.message,o.eta_at,o.reason,o.show_phone].join("|");
  if(ov && curKey===key) return;
  if(!ov){ ov = document.createElement("div"); ov.className="pg-ov"; ov.setAttribute("role","alertdialog"); ov.setAttribute("aria-live","polite"); document.body.appendChild(ov); document.documentElement.style.overflow="hidden"; requestAnimationFrame(()=>ov && ov.classList.add("pg-in")); }
  ov.classList.remove("pg-out");
  curKey = key; ov.innerHTML = buildCard(o);
  clearInterval(cdTimer);
  const el = ov.querySelector("#pgEta");
  if(el && o.eta_at){ const tick=()=>{ const ms=new Date(o.eta_at)-Date.now(); el.textContent = fmtLeft(ms); if(ms<=0){ clearInterval(cdTimer); el.textContent="قريباً جداً"; el.style.fontSize="18px"; } }; tick(); cdTimer=setInterval(tick,1000); }
}
function hideOverlay(){
  if(!ov) return; clearInterval(cdTimer);
  const el = ov; ov = null; curKey = "";
  el.classList.add("pg-out"); document.documentElement.style.overflow="";
  setTimeout(()=>el.remove(), 1400);
}

/* ===== الشرائط ===== */
const bans = {};
function banner(id, cls, text, closable){
  injectCss();
  let b = bans[id];
  if(b && b.dataset.t===text) return;
  if(b) b.remove();
  b = document.createElement("div"); b.className="pg-ban "+cls; b.dataset.t=text;
  b.innerHTML = `<span>${esc(text)}</span>${closable?'<button type="button" aria-label="إغلاق">×</button>':""}`;
  if(closable) b.querySelector("button").onclick = () => { try{ sessionStorage.setItem("pg-"+id, text); }catch{} b.remove(); delete bans[id]; relayout(); };
  document.body.appendChild(b); bans[id]=b; relayout();
}
function dropBanner(id){ if(bans[id]){ bans[id].remove(); delete bans[id]; relayout(); } }
function relayout(){ let top=0; Object.values(bans).forEach(b=>{ b.style.top=top+"px"; top+=b.offsetHeight; }); }
const dismissed = (id,t) => { try{ return sessionStorage.getItem("pg-"+id)===t; }catch{ return false; } };

/* ===== الحالة ===== */
let isAdmin = null;
async function checkAdmin(){
  if(isAdmin!==null) return isAdmin;
  try{ const s = await supabase.auth.getSession(); if(!s.data.session){ isAdmin=false; return false; } const r = await supabase.rpc("mzad_is_admin"); isAdmin = r.data===true; }catch{ isAdmin=false; }
  return isAdmin;
}
const RESTRICT_LABELS = { no_bid:"المزايدة", no_sell:"بيع الأجهزة", no_deposit:"دفع التأمين" };

export async function applyStatus(st, force){
  if(!st || typeof st!=="object") return;
  window.__mzadStatus = st; window.dispatchEvent(new CustomEvent("mzad:status",{ detail:st }));
  const m = st.maintenance || {}, me = st.me;

  if(me && me.banned){ showOverlay({ kind:"banned", reason:me.reason, title:"تم إيقاف حسابك", message:"حسابك موقوف حالياً من قبل الإدارة." + (me.until ? "\nينتهي الإيقاف: "+new Date(me.until).toLocaleString("ar-IQ",{dateStyle:"medium",timeStyle:"short"}) : ""), show_phone:true }); dropBanner("restrict"); dropBanner("maint"); return; }

  if(m.on){
    if(await checkAdmin()){ hideOverlay(); banner("maint","a","وضع الصيانة مفعّل — أنت ترى التطبيق كمشرف والمستخدمون يشاهدون شاشة الصيانة.",false); }
    else { dropBanner("maint"); showOverlay({ kind: m.style==="waiting" ? "waiting" : "maintenance", title:m.title, message:m.message, eta_at:m.eta_at, show_phone:m.show_phone }); return; }
  } else { hideOverlay(); dropBanner("maint"); }

  if(st.announcement && !dismissed("ann", st.announcement)) banner("ann","a",st.announcement,true); else dropBanner("ann");

  if(me && (me.no_bid||me.no_sell||me.no_deposit)){
    const parts = Object.keys(RESTRICT_LABELS).filter(k=>me[k]).map(k=>RESTRICT_LABELS[k]);
    const txt = "تم تقييد حسابك: "+parts.join(" و")+(me.reason?" — "+me.reason:"")+".";
    if(!dismissed("restrict", txt)) banner("restrict","w",txt,true); else dropBanner("restrict");
  } else dropBanner("restrict");
}

async function poll(){
  try{ const r = await supabase.rpc("mzad_public_status"); if(!r.error && r.data) await applyStatus(r.data); }catch{}
}

/* معاينة من لوحة الإدارة (لا تلمس الإعدادات الفعلية) */
export function previewOverlay(o, ms=6000){
  showOverlay(o);
  const el = ov; setTimeout(()=>{ if(ov===el) hideOverlay(); }, ms);
}
export function closePreview(){ hideOverlay(); }

if(!SKIP){
  const start = () => { poll(); setInterval(()=>{ if(!document.hidden) poll(); }, POLL_MS); document.addEventListener("visibilitychange", ()=>{ if(!document.hidden) poll(); }); };
  if(document.body) start(); else document.addEventListener("DOMContentLoaded", start);
}
