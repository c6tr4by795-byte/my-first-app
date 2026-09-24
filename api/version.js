const fs = require("fs");
const path = require("path");

function readPackage(name) {
  const filePath = path.join(
    process.cwd(),
    "node_modules",
    name,
    "package.json"
  );

  return JSON.parse(
    fs.readFileSync(filePath, "utf8")
  );
}

module.exports = (req, res) => {
  try {
    const firebaseAdmin = readPackage("firebase-admin");
    const jwksRsa = readPackage("jwks-rsa");
    const jose = readPackage("jose");

    res.status(200).json({
      firebaseAdmin: firebaseAdmin.version,
      jwksRsa: jwksRsa.version,
      jose: jose.version
    });

  } catch (error) {
    res.status(500).json({
      error: error.message
    });
  }
};
