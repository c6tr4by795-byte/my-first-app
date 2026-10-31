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
  let lastPresenceKey = null;
  let pendingPresenceState = null;

  async function updatePresence(online = !document.hidden) {
    // Keep only the latest requested state; do not lose a hide/show transition
    // merely because the previous heartbeat is still in flight.
    pendingPresenceState = !!online;
    if (presenceBusy) return;

    presenceBusy = true;
    try {
      while (pendingPresenceState !== null) {
        const nextState = pendingPresenceState;
        pendingPresenceState = null;

        const { data } = await supabase.auth.getSession();
        const userId = data?.session?.user?.id;
        if (!userId) {
          lastPresenceKey = null;
          continue;
        }

        const stateKey = userId + ":" + (nextState ? "online" : "offline");
        if (lastPresenceKey === stateKey) continue;

        const { error } = await supabase.rpc("mzad_presence_ping", {
          p_online: nextState
        });

        if (error) {
          console.warn("Presence update failed:", error.message);
        } else {
          lastPresenceKey = stateKey;
        }
      }
    } finally {
      presenceBusy = false;
      // A state can be queued just as the worker is finishing.
      if (pendingPresenceState !== null) updatePresence(pendingPresenceState);
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
      // The same page may be used by another account; presence is tracked per user.
      startPresence();
    }
    if (event === "SIGNED_OUT") {
      lastPresenceKey = null;
      stopPresence();
    }
  });

  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopPresence();
    else startPresence();
  });
  window.addEventListener("pagehide", () => updatePresence(false));
}
