import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";

const SUPABASE_URL = "https://ldvxctpngkidvatkisae.supabase.co";

const SUPABASE_KEY =
  "sb_publishable_iKh2hmOMdDYt9MmGmCX3jA_Hs-MovbK";

export const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_KEY
);
