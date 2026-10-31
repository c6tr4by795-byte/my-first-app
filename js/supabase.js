import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

const SUPABASE_URL = "https://ldvxctpngkidvatkisae.supabase.co";

const SUPABASE_KEY =
  "sb_publishable_iKh2hmOMdDYt9MmGmCX3jA_Hs-MovbK";

export const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_KEY
);



// Unified back button for MZAD PHONE pages.
if (typeof window !== "undefined" && typeof document !== "undefined") {
  const addMzadBackButton = () => {
    const path = window.location.pathname.toLowerCase();
    const fileName = path.split("/").pop() || "";

    // Main entry pages do not need a back button.
    if (["", "home.html", "index.html", "admin-login.html"].includes(fileName)) return;
    if (document.getElementById("mzad-global-back-btn")) return;

    const style = document.createElement("style");
    style.id = "mzad-global-back-style";
    style.textContent = `
      #mzad-global-back-btn {
        position: fixed;
        top: max(14px, env(safe-area-inset-top));
        right: 14px;
        width: 42px;
        height: 42px;
        border: 0;
        border-radius: 13px;
        background: rgba(255,255,255,.96);
        color: #5b3fe0;
        font: inherit;
        font-size: 24px;
        line-height: 42px;
        text-align: center;
        cursor: pointer;
        box-shadow: 0 4px 16px rgba(0,0,0,.10);
        z-index: 9999;
        -webkit-tap-highlight-color: transparent;
      }
      #mzad-global-back-btn:active { transform: scale(.96); }
    `;
    document.head.appendChild(style);

    const button = document.createElement("button");
    button.id = "mzad-global-back-btn";
    button.type = "button";
    button.setAttribute("aria-label", "رجوع");
    button.setAttribute("title", "رجوع");
    button.innerHTML = "&#8594;";
    button.addEventListener("click", () => {
      if (window.history.length > 1) {
        window.history.back();
      } else {
        window.location.href = path.includes("/admin/") ? "../home.html" : "home.html";
      }
    });
    document.body.appendChild(button);
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", addMzadBackButton, { once: true });
  } else {
    addMzadBackButton();
  }
}

// Track presence for signed-in users. Online is based on a 45-second heartbeat;
// leaving/closing the page records an immediate best-effort offline timestamp.
if (typeof window !== "undefined") {
  let presenceTimer;
  let presenceBusy = false;

  async function updatePresence(online = !document.hidden) {
    if (presenceBusy) return;
    presenceBusy = true;
    try {
      const { data } = await supabase.auth.getSession();
      if (data?.session?.user) {
        const { error } = await supabase.rpc("mzad_presence_ping", { p_online: !!online });
        if (error) console.warn("Presence update failed:", error.message);
      }
    } finally {
      presenceBusy = false;
    }
  }

  function startPresence() {
    updatePresence(true);
    if (presenceTimer) clearInterval(presenceTimer);
    presenceTimer = setInterval(() => {
      if (!document.hidden) updatePresence(true);
    }, 45000);
  }

  function stopPresence() {
    if (presenceTimer) clearInterval(presenceTimer);
    presenceTimer = undefined;
    updatePresence(false);
  }

  supabase.auth.onAuthStateChange((event, session) => {
    if (session?.user && ["INITIAL_SESSION", "SIGNED_IN", "TOKEN_REFRESHED"].includes(event)) {
      if (!document.hidden) startPresence();
    }
    if (event === "SIGNED_OUT") stopPresence();
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopPresence();
    else startPresence();
  });
  window.addEventListener("pagehide", () => updatePresence(false));
}
