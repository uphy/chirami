const fs = require("fs");
const path = require("path");

const src = path.join(__dirname, "../index.html");
const destDir = path.join(__dirname, "../../Chirami/Resources/editor");
const dest = path.join(destDir, "index.html");

fs.mkdirSync(destDir, { recursive: true });
fs.copyFileSync(src, dest);
console.log(`Copied index.html -> ${dest}`);
