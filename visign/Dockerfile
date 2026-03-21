# visign/Dockerfile
# Stage 1: Install dependencies (include dev deps for build tools like next)
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --include=dev

# Stage 2: Build the application
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json package-lock.json ./
COPY . .

# Required build-time environment variables.
# Intentionally no defaults: build must fail fast if any required arg is missing.
ARG DATABASE_URL
ARG OPENAI_API_KEY
ARG NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY

RUN test -n "$DATABASE_URL" || (echo "ERROR: Missing required build arg DATABASE_URL" >&2; exit 1)
RUN test -n "$OPENAI_API_KEY" || (echo "ERROR: Missing required build arg OPENAI_API_KEY" >&2; exit 1)
RUN test -n "$NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" || (echo "ERROR: Missing required build arg NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" >&2; exit 1)

ENV DATABASE_URL=$DATABASE_URL
ENV OPENAI_API_KEY=$OPENAI_API_KEY
ENV NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=$NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# Stage 3: Production image
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV HOSTNAME=0.0.0.0

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy built assets
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/ || exit 1

CMD ["node", "server.js"]