// 修复 db.js 中被 shell 转义破坏的 books.location 迁移块
const fs = require('fs');
const p = 'E:/LeLeDaiPao/server/src/db.js';
let s = fs.readFileSync(p, 'utf8');
const bad = [
  '  const bookCols = db.prepare().all().map((c) => c.name);',
  "  if (!bookCols.includes('location')) {",
  '    db.exec();',
  "    console.log('[migrate] books 表已增加 location 列');",
  '  }',
].join('\n');
const good = [
  "  const bookCols = db.prepare(`PRAGMA table_info(books)`).all().map((c) => c.name);",
  "  if (!bookCols.includes('location')) {",
  '    db.exec(`ALTER TABLE books ADD COLUMN location TEXT`);',
  "    console.log('[migrate] books 表已增加 location 列');",
  '  }',
].join('\n');
if (!s.includes(bad)) { console.error('pattern not found'); process.exit(1); }
fs.writeFileSync(p, s.replace(bad, good));
console.log('migration fixed');
