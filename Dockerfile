# Build stage
FROM hexpm/elixir:1.17.3-erlang-27.1.2-alpine-3.20.3 AS build

# Install build dependencies
RUN apk add --no-cache build-base git npm

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Copy dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy assets
COPY assets assets
COPY priv priv

# Compile assets
RUN cd assets && npm install && npm run deploy

# Copy application code
COPY lib lib
COPY config config

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage
FROM alpine:3.20.3 AS app

# Install runtime dependencies
RUN apk add --no-cache openssl ncurses-libs libstdc++

WORKDIR /app

# Create non-root user
RUN adduser -D ingot
USER ingot

# Copy release from build stage
COPY --from=build --chown=ingot:ingot /app/_build/prod/rel/ingot ./

ENV HOME=/app

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["/app/bin/ingot", "rpc", ":sys.get_state(IngotWeb.Endpoint)"]

# Start release
CMD ["/app/bin/ingot", "start"]
