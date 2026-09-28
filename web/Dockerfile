# syntax=docker/dockerfile:1

# ---- build ------------------------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY . .
RUN npm run build

# ---- runtime ----------------------------------------------------------------
# Static files only. The API comes from REVOKED_SERVER (default: the hosted
# service); REVOKED_CUSTOM_SERVERS decides whether users may pick another.
FROM nginx:1.29-alpine
COPY --from=build /src/dist /usr/share/nginx/html
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY nginx/security_headers.inc.template /etc/nginx/templates/security_headers.inc.template
COPY nginx/15-revoked-config.envsh /docker-entrypoint.d/15-revoked-config.envsh
ENV REVOKED_SERVER=https://api.revoked.link \
    REVOKED_CUSTOM_SERVERS=true \
    NGINX_ENVSUBST_FILTER=^REVOKED_
EXPOSE 8080
