#!/bin/sh
set -e

mkdir -p .vercel-out/aiox-install .vercel-out/aios-install

cp -r aiox-install/. .vercel-out/aiox-install/
cp -r aios-install/. .vercel-out/aios-install/
cp aiox-squad-index/index.html .vercel-out/index.html
