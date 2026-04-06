# ── Stage 1: Build (minify JS) ────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /build
COPY package*.json ./
RUN npm ci --include=dev

COPY js/ ./js/
COPY scripts/ ./scripts/

RUN node scripts/minify.mjs

# ── Stage 2: Serve ────────────────────────────────────────────────────────────
FROM nginx:1.27-alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy nginx config
COPY infra/nginx.conf /etc/nginx/conf.d/app.conf

# Copy static files
COPY . /usr/share/nginx/html

# Overwrite js/ with minified versions from builder stage
COPY --from=builder /build/js/ /usr/share/nginx/html/js/

# Remove infra, scripts, node_modules from webroot (não devem ser servidos)
RUN rm -rf /usr/share/nginx/html/infra \
           /usr/share/nginx/html/scripts \
           /usr/share/nginx/html/node_modules \
           /usr/share/nginx/html/package.json \
           /usr/share/nginx/html/package-lock.json

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
