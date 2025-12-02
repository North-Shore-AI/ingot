# ADR-002: LiveView Labeling Interface Design

## Status

Accepted

## Context

Human labeling requires an interactive, responsive interface that minimizes friction and maximizes labeler productivity. We need to choose the right technology and design pattern for the labeling UI.

## Decision

Use **Phoenix LiveView** for the labeling interface with the following design:

### Interface Structure

```
┌─────────────────────────────────────────────────────────────┐
│  Ingot Labeler                              [Skip] [Quit]   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  NARRATIVE A:                                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ [Display narrative A text]                              ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  NARRATIVE B:                                               │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ [Display narrative B text]                              ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  SYNTHESIS:                                                 │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ [Display synthesis text]                                ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  YOUR RATING:                                               │
│  Coherence:    [1] [2] [3] [4] [5]                         │
│  Grounded:     [1] [2] [3] [4] [5]                         │
│  Novel:        [1] [2] [3] [4] [5]                         │
│  Balanced:     [1] [2] [3] [4] [5]                         │
│                                                             │
│  Notes: [___________________________________]               │
│                                    [Submit & Next →]        │
│  Progress: 47/500 labeled                                   │
└─────────────────────────────────────────────────────────────┘
```

### Component Architecture

- **LabelingLive**: Main LiveView process managing state
- **SampleComponent**: Displays narrative A, B, and synthesis
- **LabelFormComponent**: Handles rating inputs and notes
- **ProgressComponent**: Shows labeling progress bar

### State Management

LiveView socket state includes:
- Current sample data (narratives A/B, synthesis)
- Current ratings (coherence, grounded, novel, balanced)
- Notes text
- Session statistics (total labeled, current session count)
- Timer start time for current sample

## Rationale

### Why LiveView?

1. **Real-time Updates**: Automatic UI updates when new samples available
2. **Minimal JavaScript**: Most interactivity handled server-side
3. **Stateful Connections**: Easy session management per WebSocket
4. **Phoenix Integration**: Native integration with Phoenix ecosystem

### Why Component-Based Design?

1. **Reusability**: Components can be used in different contexts
2. **Testability**: Each component can be tested in isolation
3. **Maintainability**: Changes localized to specific components
4. **Performance**: Targeted re-rendering of changed components

## Consequences

### Positive

- **Developer Productivity**: Fast iteration with LiveView
- **User Experience**: Smooth, app-like interface
- **Real-time Capabilities**: Live progress updates, active user counts
- **Reduced Complexity**: Less JavaScript needed
- **Type Safety**: All state managed in Elixir

### Negative

- **WebSocket Dependency**: Requires persistent connection
- **Server Load**: Each user maintains LiveView process
- **Offline Limitations**: Cannot label without connection

### Mitigation

- Implement connection status indicator
- Add auto-save for partial ratings
- Show clear error messages on connection loss
- Provide reconnection logic

## Design Principles

### 1. Focus Mode

- Full-screen labeling interface
- Minimal distractions
- Clear visual hierarchy

### 2. Progressive Disclosure

- Show only essential information initially
- Notes field optional (collapsed by default)
- Advanced options hidden unless needed

### 3. Visual Clarity

- Distinct sections for each narrative
- Clear labels for rating dimensions
- Visual feedback on selection

### 4. Accessibility

- Keyboard navigation support
- ARIA labels for screen readers
- High contrast mode support
- Focus indicators

## Alternatives Considered

### 1. Traditional Form-Based UI

Server-rendered forms with full page reloads.

**Rejected because:**
- Poor user experience with page reloads
- Slower labeling workflow
- Lost state on navigation errors

### 2. React/Vue SPA

Separate frontend framework communicating via API.

**Rejected because:**
- Increased complexity (two codebases)
- More JavaScript to maintain
- Authentication/session complexity
- Slower development cycle

### 3. Mobile App

Native iOS/Android applications.

**Rejected because:**
- Much higher development cost
- Deployment friction
- Web-first approach preferred for accessibility

## Implementation Details

### Rating Input

Use radio button groups styled as clickable buttons:
- Visual feedback on hover
- Clear selected state
- Touch-friendly sizing (44px minimum)

### Sample Display

- Scrollable text areas for long narratives
- Fixed-height containers with overflow
- Monospace font for consistency
- Line height optimized for reading

### Progress Bar

- Visual indicator of completion percentage
- Text display: "X/Y labeled"
- Updates in real-time via PubSub

### Error Handling

- Inline validation messages
- Toast notifications for server errors
- Auto-retry on connection loss

## References

- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
- [ADR-004: Real-time Progress Updates](004-realtime-progress-updates.md)
- [ADR-005: Keyboard Shortcuts for Labeling](005-keyboard-shortcuts.md)
