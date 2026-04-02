FROM nginx:1.27-alpine

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy nginx config
COPY infra/nginx.conf /etc/nginx/conf.d/app.conf

# Copy static files
COPY . /usr/share/nginx/html

# Remove infra dir from webroot (não deve ser servido)
RUN rm -rf /usr/share/nginx/html/infra

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
