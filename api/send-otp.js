const crypto = require("crypto");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  const serviceAccount = JSON.parse(
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON
  );

  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const db = admin.firestore();

function hashCode(salt, code) {
  return crypto
    .createHash("sha256")
    .update(`${salt}:${code}`)
    .digest("hex");
}

function emailId(email) {
  return crypto
    .createHash("sha256")
    .update(email)
    .digest("hex");
}

module.exports = async (req, res) => {
  if (req.method !== "POST") {
    return res.status(405).json({
      success: false,
      message: "Method not allowed"
    });
  }

  try {
    const { email } = req.body || {};

    const normalizedEmail = String(email || "")
      .trim()
      .toLowerCase();

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
      return res.status(400).json({
        success: false,
        message: "البريد الإلكتروني غير صحيح."
      });
    }

    const userRecord = await admin
      .auth()
      .getUserByEmail(normalizedEmail)
      .catch(() => null);

    if (!userRecord) {
      return res.status(200).json({
        success: true,
        message: "إذا كان البريد مرتبطاً بحساب، سيتم إرسال رمز التحقق."
      });
    }

    const documentId = emailId(normalizedEmail);
    const otpRef = db.collection("password_otps").doc(documentId);
    const existing = await otpRef.get();

    if (existing.exists) {
      const data = existing.data();

      if (
        data.lastSentAt &&
        Date.now() - data.lastSentAt.toMillis() < 60 * 1000
      ) {
        return res.status(429).json({
          success: false,
          message: "انتظر دقيقة قبل طلب رمز جديد."
        });
      }
    }

    const code = crypto
      .randomInt(100000, 1000000)
      .toString();

    const salt = crypto
      .randomBytes(16)
      .toString("hex");

    const codeHash = hashCode(salt, code);

    const expiresAt = new Date(
      Date.now() + 10 * 60 * 1000
    );

    await otpRef.set({
      email: normalizedEmail,
      codeHash,
      salt,
      attempts: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt)
    });

    const response = await fetch(
      "https://api.resend.com/emails",
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${process.env.RESEND_API_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          from: "العراق الأخضر <onboarding@resend.dev>",
          to: [normalizedEmail],
          subject: "رمز استعادة حسابك - العراق الأخضر",
          html: `
            <div style="font-family:Arial,sans-serif;direction:rtl;text-align:center;padding:30px">
              <h2>العراق الأخضر</h2>
              <p>رمز استعادة حسابك هو:</p>
              <div style="font-size:36px;font-weight:bold;letter-spacing:8px;margin:25px 0">
                ${code}
              </div>
              <p>الرمز صالح لمدة 10 دقائق فقط.</p>
              <p>إذا لم تطلب استعادة كلمة المرور، تجاهل هذه الرسالة.</p>
            </div>
          `
        })
      }
    );

    if (!response.ok) {
      await otpRef.delete();

      const errorText = await response.text();
      console.error("Resend error:", errorText);

      return res.status(500).json({
        success: false,
        message: "تعذر إرسال رمز التحقق."
      });
    }

    return res.status(200).json({
      success: true,
      message: "تم إرسال رمز التحقق إلى بريدك الإلكتروني."
    });

  } catch (error) {
    console.error("OTP error:", error);

    return res.status(500).json({
      success: false,
      message: "حدث خطأ في الخادم."
    });
  }
};
