#!/usr/bin/env node
/**
 * Build script: minify JS files in-place using terser
 *
 * Designed for Docker image build — minifies JS in the working directory
 * before nginx serves the files. Source files in git remain unminified.
 *
 * Usage:
 *   node scripts/minify.mjs           # minify all js/ files
 *   node scripts/minify.mjs --dry-run # show what would be minified
 */

import { readdir, readFile, writeFile } from 'node:fs/promises';
import { join, extname, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { minify } from 'terser';

const DRY_RUN = process.argv.includes('--dry-run');

async function* walkJs(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      yield* walkJs(full);
    } else if (entry.isFile() && extname(entry.name) === '.js') {
      yield full;
    }
  }
}

let totalOriginal = 0;
let totalMinified = 0;
let fileCount = 0;

const jsDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'js');

for await (const filePath of walkJs(jsDir)) {
  const original = await readFile(filePath, 'utf8');
  const originalSize = Buffer.byteLength(original, 'utf8');

  try {
    const result = await minify(original, {
      compress: {
        drop_console: false, // keep console.error/warn for debugging
        passes: 2,
      },
      mangle: true,
      format: { comments: false },
    });

    const minified = result.code;
    const minifiedSize = Buffer.byteLength(minified, 'utf8');
    const savings = (((originalSize - minifiedSize) / originalSize) * 100).toFixed(1);

    const relPath = filePath.replace(jsDir + '/', 'js/');
    console.log(`  ${DRY_RUN ? '[DRY]' : 'OK  '} ${relPath}: ${originalSize} → ${minifiedSize} bytes (-${savings}%)`);

    if (!DRY_RUN) {
      await writeFile(filePath, minified, 'utf8');
    }

    totalOriginal += originalSize;
    totalMinified += minifiedSize;
    fileCount++;
  } catch (err) {
    console.error(`  FAIL ${filePath}: ${err.message}`);
    process.exit(1);
  }
}

const totalSavings = totalOriginal > 0
  ? (((totalOriginal - totalMinified) / totalOriginal) * 100).toFixed(1)
  : '0';

console.log(`\n${DRY_RUN ? '[DRY RUN]' : 'Done'}: ${fileCount} files, ${totalOriginal.toLocaleString()} → ${totalMinified.toLocaleString()} bytes (-${totalSavings}%)`);
