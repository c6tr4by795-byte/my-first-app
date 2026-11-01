(function(){

  /* ===== CSS (يتحط تلقائياً) ===== */
  const css = `
#notificationBtn .notification-bell-icon{width:20px;height:20px;flex:0 0 20px;transform-origin:50% 8%}
#notificationBtn.has-unread .notification-bell-icon{animation:bellSwing 3.2s ease-in-out infinite}
@keyframes bellSwing{0%,70%,100%{transform:rotate(0)}74%{transform:rotate(14deg)}78%{transform:rotate(-12deg)}82%{transform:rotate(8deg)}86%{transform:rotate(-5deg)}90%{transform:rotate(0)}}
.gov-ov{position:fixed;inset:0;z-index:200;background:rgba(20,14,48,.55);opacity:0;pointer-events:none;transition:opacity .25s}
.gov-ov.show{opacity:1;pointer-events:auto}
.gov-sheet{position:absolute;left:0;right:0;bottom:0;width:min(100%,520px);margin:0 auto;max-height:82dvh;overflow:auto;overscroll-behavior:contain;background:#fff;border-radius:26px 26px 0 0;padding:10px 16px calc(20px + var(--safe-bottom));transform:translateY(100%);transition:transform .32s cubic-bezier(.22,.8,.3,1)}
.gov-ov.show .gov-sheet{transform:none}
.gov-handle{width:40px;height:4px;border-radius:4px;background:#ddd8f8;margin:2px auto 12px}
.gov-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:12px}
.gov-head h3{margin:0;font-size:17px;font-weight:950}
.gov-head p{margin:3px 0 0;font-size:11px;font-weight:700;color:var(--muted)}
.gov-close{width:36px;height:36px;border-radius:12px;background:var(--p-soft);color:var(--p-dark);font-size:20px;display:grid;place-items:center}
.gov-now{display:flex;align-items:center;gap:12px;width:100%;padding:14px;border-radius:18px;text-align:start;background:linear-gradient(145deg,#e8f6ef,#f4fbf7);border:1.5px solid #bfe5d2}
.gov-now .ic{width:42px;height:42px;border-radius:14px;background:var(--ok);color:#fff;display:grid;place-items:center;flex:0 0 42px}
.gov-now .ic svg{width:21px;height:21px}
.gov-now strong{display:block;font-size:15px;font-weight:950}
.gov-now span span{display:block;margin-top:2px;font-size:11px;font-weight:800;color:var(--ok)}
.gov-label{margin:16px 2px 8px;font-size:12px;font-weight:900;color:var(--muted)}
.gov-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.gov-item{display:flex;align-items:center;justify-content:space-between;gap:6px;padding:13px 12px;border-radius:14px;background:#fff;border:1.5px solid var(--edge);font-size:13px;font-weight:900;transition:transform .18s,border-color .2s,background .2s}
.gov-item:active{transform:scale(.96)}
.gov-item em{font-style:normal;font-size:9.5px;font-weight:900;padding:3px 8px;border-radius:999px;background:var(--p-soft);color:var(--p-dark)}
.gov-item.sel{border-color:var(--p);background:var(--p-soft)}
.gov-soon{display:none;margin-top:14px;padding:16px;border-radius:18px;text-align:center;background:linear-gradient(145deg,#f3f0ff,#faf9ff);border:1.5px solid var(--edge)}
.gov-soon.show{display:block;animation:govUp .3s ease}
@keyframes govUp{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
.gov-soon .rocket{font-size:26px}
.gov-soon h4{margin:6px 0 0;font-size:15px;font-weight:950}
.gov-soon p{margin:5px 0 0;font-size:11.5px;font-weight:700;line-height:1.6;color:var(--muted)}
.gov-soon .remind{margin-top:12px;padding:11px 20px;border-radius:13px;background:linear-gradient(145deg,#6246d9,#8b6cf0);color:#fff;font-size:12.5px;font-weight:900;box-shadow:0 8px 16px -8px rgba(98,70,217,.6)}
.gov-soon .remind.done{background:var(--ok)}
`;
  const st = document.createElement("style");
  st.textContent = css;
  document.head.appendChild(st);

  const OTHERS = ["بغداد","البصرة","نينوى","أربيل","السليمانية","دهوك","كركوك","الأنبار","صلاح الدين","ديالى","واسط","ميسان","ذي قار","المثنى","القادسية","بابل","كربلاء"];
  const KEY = "mzad_gov_notify";
  const read = () => { try{ return JSON.parse(localStorage.getItem(KEY) || "[]"); }catch{ return []; } };
  const write = a => { try{ localStorage.setItem(KEY, JSON.stringify(a)); }catch{} };

  const bell = document.getElementById("notificationBtn");

  /* ===== أيقونة الجرس الجديدة (الزر نفسه ما يتغير) ===== */
  const BELL = '<svg class="notification-bell-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5a1.5 1.5 0 0 1 1.5 1.5v.6c2.6.7 4.5 3 4.5 5.9v3.3c0 .8.3 1.5.9 2.1l.7.7c.6.6.2 1.7-.7 1.7H5.1c-.9 0-1.3-1.1-.7-1.7l.7-.7c.6-.6.9-1.3.9-2.1v-3.3c0-2.9 1.9-5.2 4.5-5.9V4A1.5 1.5 0 0 1 12 2.5Z" fill="currentColor"/><path d="M9.6 19.5a2.4 2.4 0 0 0 4.8 0Z" fill="currentColor" opacity=".55"/></svg>';
  const oldBell = bell && bell.querySelector(".notification-bell-icon");
  if(oldBell){
    const t = document.createElement("template");
    t.innerHTML = BELL;
    oldBell.replaceWith(t.content.firstElementChild);
  }

  function syncBell(){
    const b = bell.querySelector(".mzad-notify-badge");
    bell.classList.toggle("has-unread", !!b && !b.hidden && b.style.display !== "none");
  }
  if(bell){
    new MutationObserver(syncBell).observe(bell, {childList:true, subtree:true, attributes:true, attributeFilter:["hidden","style"]});
    syncBell();
  }

  let tt;
  function say(msg){
    const el = document.getElementById("toast");
    if(!el) return;
    el.textContent = msg;
    el.classList.add("show");
    clearTimeout(tt);
    tt = setTimeout(() => el.classList.remove("show"), 2200);
  }

  /* ===== ورقة المحافظات ===== */
  let ov = null;
  let picked = "";

  function build(){

    ov = document.createElement("div");
    ov.className = "gov-ov";

    ov.innerHTML = `
      <div class="gov-sheet" role="dialog" aria-label="اختر المحافظة">
        <div class="gov-handle"></div>
        <div class="gov-head">
          <div>
            <h3>اختر محافظتك</h3>
            <p>نشتغل حالياً بالنجف، وباقي المحافظات قريباً</p>
          </div>
          <button type="button" class="gov-close" aria-label="إغلاق">×</button>
        </div>
        <button type="button" class="gov-now" data-gov="النجف">
          <span class="ic"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.5"/></svg></span>
          <span>
            <strong>النجف</strong>
            <span>متوفر الآن ✓</span>
          </span>
        </button>
        <div class="gov-label">باقي المحافظات</div>
        <div class="gov-grid">
          ${OTHERS.map(g => `<button type="button" class="gov-item" data-gov="${g}"><span>${g}</span><em>قريباً</em></button>`).join("")}
        </div>
        <div class="gov-soon" id="govSoon">
          <div class="rocket">🚀</div>
          <h4 id="govSoonTitle"></h4>
          <p>نشتغل نوصل لكل المحافظات. اضغط الزر وراح نعلمك أول ما نفتح عندكم.</p>
          <button type="button" class="remind" id="govRemind">ذكّرني عند التوفر</button>
        </div>
      </div>
    `;

    document.body.appendChild(ov);

    const soon = ov.querySelector("#govSoon");
    const remind = ov.querySelector("#govRemind");

    ov.addEventListener("click", e => {

      if(e.target === ov || e.target.closest(".gov-close")){
        ov.classList.remove("show");
        return;
      }

      if(e.target.closest("#govRemind")){
        const list = read();
        if(!list.includes(picked)) list.push(picked);
        write(list);
        remind.textContent = "تم ✓ راح نعلمك";
        remind.classList.add("done");
        return;
      }

      const item = e.target.closest("[data-gov]");
      if(!item) return;

      const name = item.dataset.gov;

      if(name === "النجف"){
        ov.classList.remove("show");
        say("أنت بمحافظة النجف");
        return;
      }

      picked = name;

      ov.querySelectorAll(".gov-item").forEach(i => i.classList.toggle("sel", i === item));
      ov.querySelector("#govSoonTitle").textContent = `قريباً نتواجد بـ${name}`;

      const done = read().includes(name);
      remind.textContent = done ? "تم ✓ راح نعلمك" : "ذكّرني عند التوفر";
      remind.classList.toggle("done", done);

      soon.classList.add("show");
      soon.scrollIntoView({behavior:"smooth", block:"nearest"});
    });
  }

  function openGov(){
    if(!ov) build();
    ov.querySelector("#govSoon").classList.remove("show");
    ov.querySelectorAll(".gov-item").forEach(i => i.classList.remove("sel"));
    requestAnimationFrame(() => ov.classList.add("show"));
  }

  /* نلتقط الضغطة قبل الكود القديم حتى ما تطلع رسالة "المنصة تعمل حالياً داخل النجف" */
  document.addEventListener("click", e => {
    if(!e.target.closest("#locationBtn")) return;
    e.stopPropagation();
    e.preventDefault();
    openGov();
  }, true);

})();
