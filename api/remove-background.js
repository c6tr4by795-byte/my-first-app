const MAX_INPUT_BYTES = 4 * 1024 * 1024;
const MAX_OUTPUT_BYTES = 12 * 1024 * 1024;

module.exports.config = {
  api: { bodyParser: false },
  maxDuration: 60
};

function sendError(res, status, message) {
  return res.status(status).json({ success: false, message });
}

async function readRawBody(req) {
  if (Buffer.isBuffer(req.body)) return req.body;
  if (typeof req.body === "string") return Buffer.from(req.body);
  if (req.body && typeof req.body === "object") {
    throw new Error("يجب إرسال الصورة كملف وليس كبيانات نصية.");
  }

  return await new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let settled = false;

    req.on("data", chunk => {
      if (settled) return;
      size += chunk.length;
      if (size > MAX_INPUT_BYTES) {
        settled = true;
        reject(new Error("حجم الصورة بعد ضغطها أكبر من الحد المسموح."));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      if (!settled) {
        settled = true;
        resolve(Buffer.concat(chunks));
      }
    });
    req.on("error", error => {
      if (!settled) {
        settled = true;
        reject(error);
      }
    });
  });
}

module.exports = async (req, res) => {
  res.setHeader("Cache-Control", "no-store");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return sendError(res, 405, "طريقة الطلب غير مدعومة.");
  }

  const origin = req.headers.origin;
  const host = req.headers.host;
  if (origin) {
    try {
      if (new URL(origin).host !== host) {
        return sendError(res, 403, "الطلب غير مسموح.");
      }
    } catch {
      return sendError(res, 403, "مصدر الطلب غير صحيح.");
    }
  }

  const contentType = String(req.headers["content-type"] || "").split(";")[0].toLowerCase();
  if (contentType !== "image/jpeg") {
    return sendError(res, 415, "صيغة الصورة المرسلة غير مدعومة.");
  }

  let input;
  try {
    input = await readRawBody(req);
  } catch (error) {
    return sendError(res, 413, error.message || "تعذر قراءة الصورة.");
  }

  if (!input.length) {
    return sendError(res, 400, "الصورة فارغة؛ اختر صورة أخرى.");
  }
  if (input.length > MAX_INPUT_BYTES) {
    return sendError(res, 413, "حجم الصورة كبير. حاول بصورة أصغر.");
  }

  try {
    const form = new FormData();
    form.append("file", new Blob([input], { type: "image/jpeg" }), "mzad-phone.jpg");

    const upstream = await fetch("https://bgninja.com/api/remove", {
      method: "POST",
      body: form,
      signal: AbortSignal.timeout(45000)
    });

    if (!upstream.ok) {
      const upstreamMessage = await upstream.text().catch(() => "");
      console.error("Background removal provider error:", upstream.status, upstreamMessage.slice(0, 300));
      return sendError(
        res,
        upstream.status === 429 ? 429 : 502,
        upstream.status === 429
          ? "خدمة إزالة الخلفية مزدحمة مؤقتاً. انتظر قليلاً ثم حاول."
          : "خدمة قصّ الخلفية لم تستطع معالجة الصورة الآن. جرّب صورة JPG أوضح."
      );
    }

    const outputType = String(upstream.headers.get("content-type") || "").toLowerCase();
    if (!outputType.includes("image/png")) {
      const detail = await upstream.text().catch(() => "");
      console.error("Unexpected background removal response:", outputType, detail.slice(0, 300));
      return sendError(res, 502, "خدمة إزالة الخلفية لم تُرجع PNG شفافة.");
    }

    const output = Buffer.from(await upstream.arrayBuffer());
    if (!output.length || output.length > MAX_OUTPUT_BYTES) {
      return sendError(res, 502, "حجم الصورة الناتجة غير صالح. جرّب صورة أخرى.");
    }

    res.statusCode = 200;
    res.setHeader("Content-Type", "image/png");
    res.setHeader("Content-Length", String(output.length));
    res.setHeader("X-Content-Type-Options", "nosniff");
    return res.end(output);
  } catch (error) {
    console.error("Background removal request failed:", error?.message || error);
    return sendError(
      res,
      502,
      error?.name === "TimeoutError"
        ? "استغرقت إزالة الخلفية وقتاً طويلاً. حاول بصورة أصغر."
        : "تعذر الاتصال بخدمة إزالة الخلفية. تأكد من الإنترنت وحاول مجدداً."
    );
  }
};
