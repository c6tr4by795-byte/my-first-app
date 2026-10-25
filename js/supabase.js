import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

const SUPABASE_URL = "https://ldvxctpngkidvatkisae.supabase.co";

const SUPABASE_KEY =
  "sb_publishable_iKh2hmOMdDYt9MmGmCX3jA_Hs-MovbK";

export const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_KEY
);


// Track last-seen for signed-in users on pages importing this shared client.
if (typeof window !== "undefined") {
  let presenceTimer;

  async function updatePresence() {
    if (document.hidden) return;
    const { data } = await supabase.auth.getSession();
    if (data?.session?.user) {
      const { error } = await supabase.rpc("mzad_presence_ping", { p_online: true });
      if (error) console.warn("Presence update failed:", error.message);
    }
  }

  supabase.auth.onAuthStateChange((event, session) => {
    if (session?.user && ["INITIAL_SESSION", "SIGNED_IN", "TOKEN_REFRESHED"].includes(event)) {
      updatePresence();
      if (presenceTimer) clearInterval(presenceTimer);
      presenceTimer = setInterval(updatePresence, 45000);
    }
    if (event === "SIGNED_OUT" && presenceTimer) {
      clearInterval(presenceTimer);
      presenceTimer = undefined;
    }
  });

  document.addEventListener("visibilitychange", updatePresence);
}
