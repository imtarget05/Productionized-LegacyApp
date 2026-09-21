# STAGE 1: Build & Dependencies (npm ci needs the committed package-lock.json)
# Phase 6B: Node 22 LTS (active LTS; 18 is EOL since 2025-04-30) on a current
# Alpine. The old node:18-alpine carried 19 HIGH + 2 CRITICAL OS CVEs
# (openssl heap overflow, busybox) with no published fix on that line.
FROM node:22-alpine AS builder
WORKDIR /app
COPY src/package*.json ./
RUN npm ci --omit=dev

# STAGE 2: Production Image (Tối ưu bảo mật và dung lượng)
FROM node:22-alpine
WORKDIR /app
# Phase 6B security gate: this is a RUNTIME image for `node server.js` — the
# package manager is a build-time tool only. Removing npm/npx deletes npm's
# bundled toolchain (tar, pacote, sigstore, brace-expansion…) which accounted
# for every remaining HIGH/CRITICAL finding in the image scan, and shrinks the
# attack surface of the shipped artefact.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
           /usr/local/bin/npm /usr/local/bin/npx \
    && node --version
# Run as non-root (Best Practice DevOps)
USER node
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node src/ ./

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# Entry point: src/server.js (graceful shutdown); test/ excluded via .dockerignore.
CMD ["node", "server.js"]
