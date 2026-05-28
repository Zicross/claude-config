// Helper script for path normalization in sync.sh
// Usage: node normalize.js <mode> <file> [claude_home]
// mode: "normalize" (replace abs paths with __CLAUDE_HOME__ / __CLAUDE_HOME_POSIX__)
//       "expand"    (replace placeholders with abs paths)

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

// POSIX (Git-Bash on Windows) form: C:\Users\isaac\.claude -> /c/Users/isaac/.claude
function toPosixHome(nativeHome) {
    const drive = nativeHome.match(/^([A-Za-z]):/);
    if (drive) {
        return '/' + drive[1].toLowerCase() + nativeHome.slice(2).replace(/\\/g, '/');
    }
    return nativeHome;
}

const posixHome = toPosixHome(claudeHome);

let content = fs.readFileSync(file, 'utf8');

if (mode === 'normalize') {
    // Windows JSON-escaped form
    const winEscaped = claudeHome.replace(/\\/g, '\\\\');
    content = content.split(winEscaped).join('__CLAUDE_HOME__');
    // Native form
    content = content.split(claudeHome).join('__CLAUDE_HOME__');
    // POSIX form (Git-Bash on Windows, or native on Unix when distinct)
    if (posixHome !== claudeHome) {
        content = content.split(posixHome).join('__CLAUDE_HOME__');
    }
    // Convert any backslash separators after the placeholder to forward slashes
    content = content.replace(/__CLAUDE_HOME__[^"]*/g, (m) => m.replace(/\\\\/g, '/'));
    // Paths invoked through bash/sh need POSIX form on expand even on Windows
    content = content.replace(/\b(bash|sh) __CLAUDE_HOME__/g, '$1 __CLAUDE_HOME_POSIX__');

} else if (mode === 'expand') {
    // POSIX placeholder always expands to POSIX form
    content = content.replace(/__CLAUDE_HOME_POSIX__/g, posixHome);

    const isWindows = os.platform() === 'win32';
    if (isWindows) {
        const winEscaped = claudeHome.replace(/\\/g, '\\\\');
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
