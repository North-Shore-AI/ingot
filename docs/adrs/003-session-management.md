# ADR-003: Session Management Strategy

## Status

Accepted

## Context

Ingot needs to track user sessions for labeling workflows. We need to decide how to identify users, manage session state, and handle session lifecycle (creation, timeout, cleanup).

## Decision

Implement **lightweight session management** using Phoenix session cookies and LiveView socket state:

### Session Storage

- **Phoenix Session Cookie**: Stores user_id and session_started_at
- **LiveView Socket**: Stores current labeling state
- **No Database**: Avoid database lookups for session data

### User Identification

- Generate UUID on first visit
- Store in encrypted Phoenix session cookie
- No authentication required initially
- Optional: Add authentication layer later

### Session Lifecycle

1. **Creation**: Generate UUID on mount if not present
2. **Activity**: Track last_activity in socket assigns
3. **Timeout**: 2-hour inactivity timeout
4. **Cleanup**: Socket process terminated on disconnect

### State Structure

```elixir
socket.assigns
|> Map.put(:user_id, uuid)
|> Map.put(:session_started_at, DateTime.utc_now())
|> Map.put(:current_sample, sample)
|> Map.put(:labels_this_session, 0)
|> Map.put(:timer_started_at, DateTime.utc_now())
```

## Rationale

### Why Session Cookies?

1. **Stateless Server**: No database required for session lookup
2. **Scalability**: Easy to scale horizontally
3. **Simplicity**: Built-in Phoenix functionality
4. **Security**: Encrypted and signed by Phoenix

### Why No Authentication Initially?

1. **Lower Barrier**: Users can start labeling immediately
2. **Privacy**: No PII collection required
3. **Development Speed**: Focus on core functionality first
4. **Future-Proof**: Easy to add auth layer later

### Why LiveView Socket State?

1. **Process Isolation**: Each user has isolated state
2. **Automatic Cleanup**: State cleaned up on disconnect
3. **Real-time Updates**: Easy to broadcast changes
4. **Memory Efficient**: Only active sessions consume memory

## Consequences

### Positive

- **Fast Development**: No auth system to build initially
- **Good UX**: No login friction for users
- **Scalable**: Stateless design scales horizontally
- **Simple**: Fewer moving parts to maintain

### Negative

- **No User Accounts**: Cannot track users across devices
- **Cookie Dependency**: Clearing cookies loses session
- **Limited Analytics**: Cannot build user profiles
- **No Access Control**: Anyone can label

### Mitigation

- Document session limitations in README
- Add optional authentication as Phase 2 feature
- Store completed labels in Anvil with session_id
- Implement IP-based rate limiting if abuse occurs

## Session Timeout Strategy

### Inactivity Detection

- Track `last_activity` timestamp in socket
- Update on every user interaction
- Check timeout on handle_info(:check_timeout)

### Timeout Configuration

```elixir
# config/config.exs
config :ingot,
  session_timeout: :timer.hours(2),
  timeout_check_interval: :timer.minutes(5)
```

### Timeout Behavior

1. Show warning modal at 10 minutes remaining
2. Allow user to extend session
3. On timeout: Save partial work, redirect to home
4. Display friendly timeout message

## Session Analytics

Track per-session metrics (stored with labels in Anvil):

- `session_id`: UUID
- `labels_completed`: Count
- `session_duration`: Time from start to end
- `average_label_time`: Mean time per label
- `skips_count`: Number of skipped samples

## Future Authentication Options

When authentication is needed, support:

1. **Email/Password**: Traditional auth
2. **OAuth**: GitHub, Google, etc.
3. **Magic Links**: Passwordless email auth
4. **API Keys**: For programmatic access

Migration path:
- Add auth layer in front of existing session system
- Link existing session data to user accounts
- Maintain backward compatibility with anonymous sessions

## Alternatives Considered

### 1. Database-Backed Sessions

Store session data in PostgreSQL or Redis.

**Rejected because:**
- Adds database dependency
- Slower session lookups
- More complex deployment
- Not needed for initial version

### 2. Mandatory Authentication

Require user accounts from day one.

**Rejected because:**
- High friction for new users
- Development overhead
- Privacy concerns
- Delays core feature development

### 3. JWT Tokens

Use JWT for stateless authentication.

**Rejected because:**
- More complex than session cookies
- Token revocation challenges
- Not needed without authentication

## Implementation Details

### Session Creation

```elixir
def mount(_params, session, socket) do
  user_id = session["user_id"] || generate_user_id()

  socket =
    socket
    |> assign(:user_id, user_id)
    |> assign(:session_started_at, DateTime.utc_now())
    |> schedule_timeout_check()

  {:ok, socket, temporary_assigns: [sample: nil]}
end
```

### Timeout Check

```elixir
def handle_info(:check_timeout, socket) do
  if session_timed_out?(socket) do
    {:noreply, push_navigate(socket, to: "/timeout")}
  else
    {:noreply, schedule_timeout_check(socket)}
  end
end
```

### Session Extension

```elixir
def handle_event("extend_session", _, socket) do
  socket = assign(socket, :last_activity, DateTime.utc_now())
  {:noreply, put_flash(socket, :info, "Session extended")}
end
```

## References

- [Phoenix Session Documentation](https://hexdocs.pm/phoenix/Phoenix.Controller.html#module-sessions)
- [LiveView Lifecycle](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-life-cycle)
- [ADR-002: LiveView Labeling Interface Design](002-liveview-labeling-interface.md)
