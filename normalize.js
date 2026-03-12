// Helper script for path normalization in sync.sh
// Usage: node normalize.js <mode> <file> [claude_home]
// mode: "normalize" (replace abs paths with __CLAUDE_HOME__)
//       "expand"    (replace __CLAUDE_HOME__ with abs path)

const fs = require('fs');
const path = require('path');
const os = require('os');

const mode = process.argv[2];
const file = process.argv[3];
const claudeHome = process.argv[4] || path.join(os.homedir(), '.claude');

if (!mode || !file) {
    console.error('Usage: node normalize.js <normalize|expand> <file> [claude_home]');
    process.exit(1);
}

let content = fs.readFileSync(file, 'utf8');

if (mode === 'normalize') {
    // Replace any absolute path to .claude with placeholder
    // Handle Windows paths (JSON-escaped with \\)
    const winEscaped = claudeHome.replace(/\\/g, '\\\\');
    content = content.split(winEscaped).join('__CLAUDE_HOME__');
    // Handle Unix paths
    content = content.split(claudeHome).join('__CLAUDE_HOME__');
    // Normalize any remaining backslash separators after placeholder to forward slashes
    content = content.replace(/__CLAUDE_HOME__[^""]*/g, (m) => m.replace(/\\\\/g, '/'));

} else if (mode === 'expand') {
    const isWindows = os.platform() === 'win32';
    if (isWindows) {
        const winEscaped = claudeHome.replace(/\\/g, '\\\\');
        // Replace placeholder and convert forward slashes to backslashes
        content = content.replace(/__CLAUDE_HOME__([^"]*)/g, (match, rest) => {
            return winEscaped + rest.replace(/\//g, '\\\\');
        });
    } else {
        content = content.replace(/__CLAUDE_HOME__/g, claudeHome);
    }
} else {
    console.error('Unknown mode:', mode);
    process.exit(1);
}

fs.writeFileSync(file, content);
console.log(`${mode}: ${file}`);
