# ADR-005: Keyboard Shortcuts for Labeling

## Status

Accepted

## Context

Human labeling is a repetitive task. Requiring mouse clicks for every rating slows down labelers and causes fatigue. Keyboard shortcuts can dramatically improve labeling efficiency and ergonomics.

## Decision

Implement comprehensive **keyboard shortcuts** for all labeling actions:

### Shortcut Mapping

| Key | Action | Context |
|-----|--------|---------|
| `1-5` | Rate current dimension | When dimension focused |
| `Tab` | Move to next dimension | Rating form |
| `Shift+Tab` | Move to previous dimension | Rating form |
| `Enter` | Submit label and load next | Anywhere |
| `S` | Skip current sample | Anywhere |
| `Q` | Quit labeling session | Anywhere |
| `N` | Focus notes field | Anywhere |
| `Esc` | Clear current ratings | Rating form |
| `?` | Show keyboard shortcuts help | Anywhere |

### Workflow Example

Efficient labeling flow:
1. Review sample (reading)
2. Press `1-5` for Coherence rating
3. Press `Tab` to move to Grounded
4. Press `1-5` for Grounded rating
5. Press `Tab` to move to Novel
6. Press `1-5` for Novel rating
7. Press `Tab` to move to Balanced
8. Press `1-5` for Balanced rating
9. Press `Enter` to submit and load next sample

Total: **8 keypresses**, 0 mouse clicks

### Implementation Approach

Use JavaScript hook with Phoenix LiveView:

```javascript
// assets/js/labeling_hooks.js
export const LabelingShortcuts = {
  mounted() {
    this.handleKeydown = (e) => {
      // Handle keyboard shortcuts
      switch(e.key) {
        case '1':
        case '2':
        case '3':
        case '4':
        case '5':
          this.pushEvent("rate", {value: e.key});
          break;
        case 'Enter':
          this.pushEvent("submit", {});
          break;
        case 's':
        case 'S':
          this.pushEvent("skip", {});
          break;
        // ... more shortcuts
      }
    };

    window.addEventListener("keydown", this.handleKeydown);
  },

  destroyed() {
    window.removeEventListener("keydown", this.handleKeydown);
  }
};
```

## Rationale

### Why Keyboard Shortcuts?

1. **Speed**: 10x faster than mouse navigation
2. **Ergonomics**: Reduces repetitive mouse movement
3. **Focus**: Hands stay on keyboard
4. **Accessibility**: Better for users with motor limitations
5. **Professional UX**: Standard in production tools

### Why These Specific Keys?

- **1-5 Numbers**: Natural rating scale mapping
- **Tab**: Standard focus navigation
- **Enter**: Universal "submit" action
- **S/Q**: Mnemonic (Skip/Quit)
- **N**: Mnemonic (Notes)
- **Esc**: Universal "cancel" action
- **?**: Standard help shortcut

### Why JavaScript Hooks?

1. **Global Shortcuts**: Work regardless of focus
2. **Event Prevention**: Can prevent default browser behavior
3. **LiveView Integration**: Clean pushEvent API
4. **Maintainable**: Separation of concerns

## Consequences

### Positive

- **Faster Labeling**: Users can label 2-3x faster
- **Better UX**: Professional, polished interface
- **Reduced Fatigue**: Less repetitive motion
- **Accessibility**: Alternative to mouse-only interface
- **Power Users**: Experts can work very efficiently

### Negative

- **Learning Curve**: Users must learn shortcuts
- **Discoverability**: Not obvious without documentation
- **Conflicts**: May conflict with browser shortcuts
- **Testing Complexity**: Requires JavaScript testing

### Mitigation

- Show keyboard shortcuts help modal (`?` key)
- Display shortcuts as tooltips on hover
- Print reference card (PDF download)
- Make shortcuts optional (can still use mouse)
- Test on multiple browsers

## Visual Feedback

### Shortcut Hints

Display keyboard shortcuts inline:

```
Coherence:    [1] [2] [3] [4] [5]
              ↑   ↑   ↑   ↑   ↑
              Press number keys to rate
```

### Active Dimension Indicator

Highlight currently focused dimension:

```
→ Coherence:    [1] [2] [3] [4] [5]  ← Press 1-5
  Grounded:     [1] [2] [3] [4] [5]
  Novel:        [1] [2] [3] [4] [5]
  Balanced:     [1] [2] [3] [4] [5]
```

### Help Modal

Press `?` to show overlay:

```
┌────────────────────────────────────┐
│  Keyboard Shortcuts                │
├────────────────────────────────────┤
│  1-5      Rate current dimension   │
│  Tab      Next dimension           │
│  Enter    Submit & next sample     │
│  S        Skip sample              │
│  Q        Quit session             │
│  N        Add notes                │
│  Esc      Clear ratings            │
│  ?        Show this help           │
│                                    │
│           [Close]                  │
└────────────────────────────────────┘
```

## Accessibility Considerations

### Screen Reader Support

- Announce shortcuts in ARIA labels
- Provide text descriptions of actions
- Support keyboard-only navigation
- Don't rely solely on shortcuts

### Configurable Shortcuts

Future enhancement: Allow custom key bindings

```elixir
config :ingot, :shortcuts,
  rate: ["1", "2", "3", "4", "5"],
  submit: ["Enter"],
  skip: ["s", "S"],
  quit: ["q", "Q"]
```

### Disable Option

Some users may prefer mouse-only:

```elixir
config :ingot,
  keyboard_shortcuts_enabled: true  # Can be toggled
```

## Mobile Considerations

Keyboard shortcuts primarily benefit desktop users:

- **Mobile**: Touch-optimized button interface
- **Tablet**: Support external keyboard shortcuts
- **Detection**: Use media queries to show/hide hints

## Conflict Prevention

### Browser Shortcut Conflicts

Prevent conflicts with browser shortcuts:

```javascript
// Don't interfere with Cmd/Ctrl shortcuts
if (e.metaKey || e.ctrlKey) {
  return;  // Let browser handle it
}

// Prevent default for our shortcuts
if (['1', '2', '3', '4', '5', 's', 'q'].includes(e.key)) {
  e.preventDefault();
}
```

### Input Field Handling

Don't trigger shortcuts when typing in text fields:

```javascript
// Ignore shortcuts when focused on input/textarea
const activeElement = document.activeElement;
if (activeElement.tagName === 'INPUT' ||
    activeElement.tagName === 'TEXTAREA') {
  return;  // User is typing
}
```

## Testing Strategy

### JavaScript Testing

Use browser testing tools:

```javascript
// test/javascript/labeling_shortcuts_test.js
describe('LabelingShortcuts', () => {
  it('rates dimension when number key pressed', () => {
    const hook = new LabelingShortcuts();
    hook.pushEvent = jest.fn();

    const event = new KeyboardEvent('keydown', {key: '3'});
    hook.handleKeydown(event);

    expect(hook.pushEvent).toHaveBeenCalledWith(
      'rate',
      {value: '3'}
    );
  });
});
```

### Integration Testing

Test with LiveView:

```elixir
test "pressing number key rates current dimension", %{conn: conn} do
  {:ok, view, _html} = live(conn, "/label")

  # Simulate keypress via JavaScript hook
  assert view
         |> element("#labeling-form")
         |> render_hook("keydown", %{"key" => "4"})

  assert has_element?(view, "[data-rating='4'][data-selected='true']")
end
```

## Alternatives Considered

### 1. Mouse-Only Interface

No keyboard shortcuts.

**Rejected because:**
- Slower labeling workflow
- More fatigue for labelers
- Not competitive with modern tools
- Poor accessibility

### 2. Vim-Style Shortcuts

Use h/j/k/l navigation like Vim.

**Rejected because:**
- Less intuitive for non-Vim users
- Not mnemonic
- Steeper learning curve
- Unnecessary complexity

### 3. Custom Shortcut Library

Use library like Mousetrap.js or Hotkeys.js.

**Rejected because:**
- Additional dependency
- Simple needs don't justify library
- LiveView hooks sufficient
- Want full control

## Implementation Checklist

- [ ] Create JavaScript hook for keyboard events
- [ ] Handle all defined shortcuts
- [ ] Prevent conflicts with browser shortcuts
- [ ] Ignore shortcuts when typing in inputs
- [ ] Add visual feedback for active dimension
- [ ] Implement help modal (`?` key)
- [ ] Add shortcut hints to UI
- [ ] Test on Chrome, Firefox, Safari
- [ ] Add JavaScript tests
- [ ] Document shortcuts in README
- [ ] Create printable reference card

## References

- [MDN Keyboard Events](https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent)
- [Phoenix LiveView JS Hooks](https://hexdocs.pm/phoenix_live_view/js-interop.html#client-hooks)
- [ADR-002: LiveView Labeling Interface Design](002-liveview-labeling-interface.md)
- [Web Content Accessibility Guidelines (WCAG)](https://www.w3.org/WAI/WCAG21/quickref/)
