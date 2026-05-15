# NPS Landing Page — Nginx Rewrite Setup

The public NPS landing page lives at `/survey/index.html` (top-level, NOT under `/admin/` to avoid the admin auth gate). It reads the token from the URL path. Nginx must rewrite `/survey/grupo/{token}` and `/survey/aluno/{token}` to that file (without redirecting — the browser must see the original URL so JS can parse it).

## SSH to VPS

```bash
ssh -i ~/.ssh/contabo root@194.163.179.68
```

## Edit Nginx config

```bash
sudo nano /etc/nginx/sites-available/painel-lesson-pages
```

Inside the `server { ... }` block for `painel.igorrover.com.br`, **before** any existing `location /` block, add:

```nginx
# NPS public landing — rewrite token paths to static index.html
location ~ ^/survey/(grupo|aluno)/[A-Za-z0-9_\-+/=]+$ {
    try_files /survey/index.html =404;
    add_header Cache-Control "no-cache" always;
}

# NPS static assets — pass through to the app container normally
location ^~ /survey/ {
    proxy_pass http://localhost:3080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Test config

```bash
sudo nginx -t
```

Expected: `nginx: configuration file /etc/nginx/nginx.conf test is successful`

## Reload

```bash
sudo systemctl reload nginx
```

## Verify

```bash
# Token URL serves the form (HTTP 200, HTML body)
curl -sI 'https://painel.igorrover.com.br/survey/grupo/test_token_xyz' | head -1
# Expected: HTTP/2 200

curl -s 'https://painel.igorrover.com.br/survey/grupo/test_token_xyz' | grep -o '<title>.*</title>'
# Expected: <title>Avaliar aula — Academia Lendária</title>

# Static asset (CSS) loads
curl -sI 'https://painel.igorrover.com.br/survey/styles.css' | head -1
# Expected: HTTP/2 200
```

## Rollback

If the rewrite breaks something:

```bash
sudo cp /etc/nginx/sites-available/painel-lesson-pages.bak /etc/nginx/sites-available/painel-lesson-pages
sudo nginx -t && sudo systemctl reload nginx
```

(Always `cp` to `.bak` before editing.)
