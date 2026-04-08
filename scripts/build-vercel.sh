#!/bin/sh
set -e

mkdir -p .vercel-out/aiox-install .vercel-out/aios-install

cp -r aiox-install/. .vercel-out/aiox-install/
cp -r aios-install/. .vercel-out/aios-install/

cat > .vercel-out/index.html <<'EOF'
<!DOCTYPE html>
<html><head>
<meta http-equiv="refresh" content="0;url=/aiox-install">
<script>location.replace('/aiox-install')</script>
</head></html>
EOF
