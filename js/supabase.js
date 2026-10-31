import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

const SUPABASE_URL = "https://ldvxctpngkidvatkisae.supabase.co";

const SUPABASE_KEY =
  "sb_publishable_iKh2hmOMdDYt9MmGmCX3jA_Hs-MovbK";

export const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_KEY
);


// Track presence for signed-in users. Online is based on a 45-second heartbeat;
// leaving/closing the page records an immediate best-effort offline timestamp.
if (typeof window !== "undefined") {
  let presenceTimer;
  let presenceBusy = false;
  let lastPresenceState = null;

  async function updatePresence(online = !document.hidden) {
    const nextState = !!online;
    if (presenceBusy || lastPresenceState === nextState) return;
    presenceBusy = true;
    try {
      const { data } = await supabase.auth.getSession();
      if (data?.session?.user) {
        const { error } = await supabase.rpc("mzad_presence_ping", { p_online: nextState });
        if (error) {
          console.warn("Presence update failed:", error.message);
        } else {
          lastPresenceState = nextState;
        }
      }
    } finally {
      presenceBusy = false;
    }
  }

  function startPresence() {
    if (document.hidden || presenceTimer) return;
    updatePresence(true);
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
    if (session?.user && ["INITIAL_SESSION", "SIGNED_IN"].includes(event)) {
      startPresence();
    }
    if (event === "SIGNED_OUT") stopPresence();
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopPresence();
    else startPresence();
  });
  window.addEventListener("pagehide", () => updatePresence(false));
}
