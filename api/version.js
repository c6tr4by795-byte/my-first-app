const fs = require("fs");
const path = require("path");

module.exports = (req, res) => {
  try {
    const filePath = path.join(
      process.cwd(),
      "node_modules",
      "firebase-admin",
      "package.json"
    );

    const packageJson = JSON.parse(
      fs.readFileSync(filePath, "utf8")
    );

    res.status(200).json({
      firebaseAdmin: packageJson.version,
      jwksRsa: packageJson.dependencies?.["jwks-rsa"] || null
    });

  } catch (error) {
    res.status(500).json({
      error: error.message
    });
  }
};
