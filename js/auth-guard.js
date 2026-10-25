/* MZAD PHONE — حماية صفحات الحساب */
import { supabase } from "./supabase.js";

const html = document.documentElement;
const file = (location.pathname.split("/").pop() || "home.html").toLowerCase();
const publicPages = new Set([
  "index.html", "signup.html", "forgot.html", "reset.html",
  "admin-login.html", "home.html", "market.html", "auctions.html",
  "device.html", "direct.html", "auction-details.html"
]);

/* الصفحة العامة لا تحتاج جلسة، أما الصفحات الخاصة فتتحقق من المستخدم لدى Auth */
if (!publicPages.has(file) && !/\/admin\//i.test(location.pathname)) {
  html.classList.add("mzad-auth-pending");
  const style = document.createElement("style");
  style.id = "mzad-auth-pending-style";
  style.textContent = "html.mzad-auth-pending body{visibility:hidden!important}";
  (document.head || html).appendChild(style);

  const target = (location.pathname.split("/").pop() || file) + location.search + location.hash;

  try {
    const { data, error } = await supabase.auth.getUser();
    if (error || !data?.user) {
      const params = new URLSearchParams();
      params.set("login", "1");
      params.set("returnTo", target);
      location.replace("index.html?" + params.toString());
    } else {
      html.classList.remove("mzad-auth-pending");
      document.getElementById("mzad-auth-pending-style")?.remove();
    }
  } catch (error) {
    console.error("MZAD auth guard:", error);
    const params = new URLSearchParams({ login: "1", returnTo: target });
    location.replace("index.html?" + params.toString());
  }
}
