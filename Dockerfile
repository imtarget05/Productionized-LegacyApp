# STAGE 1: Build & Dependencies (npm ci needs the committed package-lock.json)
FROM node:18-alpine AS builder
WORKDIR /app
COPY src/package*.json ./
RUN npm ci --omit=dev

# STAGE 2: Production Image (Tối ưu bảo mật và dung lượng)
FROM node:18-alpine
WORKDIR /app
# Chạy app dưới quyền user không phải root (Best Practice DevOps)
USER node
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node src/ ./

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Entry point: src/server.js (graceful shutdown); test/ excluded via .dockerignore.
CMD ["node", "server.js"]
