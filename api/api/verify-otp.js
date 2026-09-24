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
    const { email, code, newPassword } = req.body || {};

    const normalizedEmail = String(email || "")
      .trim()
      .toLowerCase();

    const normalizedCode = String(code || "").trim();

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizedEmail)) {
      return res.status(400).json({
        success: false,
        message: "البريد الإلكتروني غير صحيح."
      });
    }

    if (!/^\d{6}$/.test(normalizedCode)) {
      return res.status(400).json({
        success: false,
        message: "رمز التحقق يجب أن يتكون من 6 أرقام."
      });
    }

    if (
      typeof newPassword !== "string" ||
      newPassword.length < 6
    ) {
      return res.status(400).json({
        success: false,
        message: "كلمة المرور الجديدة يجب أن تكون 6 أحرف أو أكثر."
      });
    }

    const documentId = emailId(normalizedEmail);
    const otpRef = db
      .collection("password_otps")
      .doc(documentId);

    const otpSnapshot = await otpRef.get();

    if (!otpSnapshot.exists) {
      return res.status(400).json({
        success: false,
        message: "رمز التحقق غير موجود أو انتهت صلاحيته."
      });
    }

    const otpData = otpSnapshot.data();

    if (
      !otpData.expiresAt ||
      otpData.expiresAt.toMillis() < Date.now()
    ) {
      await otpRef.delete();

      return res.status(400).json({
        success: false,
        message: "انتهت صلاحية رمز التحقق. اطلب رمزاً جديداً."
      });
    }

    const attempts = Number(otpData.attempts || 0);

    if (attempts >= 5) {
      await otpRef.delete();

      return res.status(429).json({
        success: false,
        message: "تم تجاوز عدد المحاولات. اطلب رمزاً جديداً."
      });
    }

    const expectedHash = hashCode(
      otpData.salt,
      normalizedCode
    );

    if (expectedHash !== otpData.codeHash) {
      await otpRef.update({
        attempts: admin.firestore.FieldValue.increment(1)
      });

      return res.status(400).json({
        success: false,
        message: "رمز التحقق غير صحيح."
      });
    }

    const userRecord = await admin
      .auth()
      .getUserByEmail(normalizedEmail)
      .catch(() => null);

    if (!userRecord) {
      await otpRef.delete();

      return res.status(400).json({
        success: false,
        message: "تعذر العثور على الحساب."
      });
    }

    await admin.auth().updateUser(userRecord.uid, {
      password: newPassword
    });

    await admin.auth().revokeRefreshTokens(userRecord.uid);

    await otpRef.delete();

    return res.status(200).json({
      success: true,
      message: "تم تغيير كلمة المرور بنجاح."
    });

  } catch (error) {
    console.error("Verify OTP error:", error);

    return res.status(500).json({
      success: false,
      message: "حدث خطأ في الخادم."
    });
  }
};
