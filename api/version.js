const packageJson = require("firebase-admin/package.json");

module.exports = (req, res) => {
  res.status(200).json({
    firebaseAdmin: packageJson.version
  });
};
