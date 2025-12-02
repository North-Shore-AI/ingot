# ADR-010: Offline & PWA Support

## Status
Proposed

## Context

Human labeling workflows typically assume continuous internet connectivity. However, several scenarios could benefit from offline support:

1. **Field Research**: Researchers collecting labels in remote locations (poor/intermittent connectivity)
2. **Mobile Labeling**: Contractors labeling on commute (subway, airplane mode)
3. **Resilience**: Continued labeling during network outages or service degradation
4. **Latency**: Instant UI responsiveness without server round-trips for every interaction

**Progressive Web App (PWA) Capabilities:**

Modern browsers support Service Workers and Cache API, enabling:
- Offline asset caching (HTML, CSS, JS, fonts)
- Background sync (queue label submissions, sync when online)
- Push notifications (new assignments available)
- Install-to-homescreen (app-like experience on mobile)

**CNS Use Case Analysis:**

For CNS dialectical labeling:
- Labelers are internal researchers working from office/home (reliable connectivity)
- Samples include large artifacts (narratives 10KB+, potential images/charts)
- Real-time collaboration is valuable (seeing other labelers' progress)
- Offline mode adds complexity without clear value proposition

**Other Potential Use Cases:**

- **Medical Imaging**: Radiologists labeling scans on tablet (hospital WiFi unreliable)
  - Samples: Large DICOM images (10-100MB) → challenging to cache
  - Labels: Complex annotations (polygons, measurements) → conflict resolution needed

- **Audio Transcription**: Field linguists labeling recordings in remote areas
  - Samples: Audio files (5-50MB) → feasible to cache small batches
  - Labels: Text transcriptions → relatively conflict-free

- **Code Review**: Engineers labeling code quality during commute
  - Samples: Small text files (<1MB) → easy to cache
  - Labels: Binary (bug/no bug) or categorical → minimal conflict risk

**Technical Challenges:**

1. **Sample Caching**: Forge samples may include large artifacts (images, audio). Caching 100+ samples locally consumes storage.
2. **Conflict Resolution**: If labeler completes assignment offline, another labeler may label same sample online. Which label wins?
3. **Schema Versioning**: Offline labeler has schema v1, queue updated to schema v2 while offline. Submission fails on sync.
4. **Data Freshness**: Queue stats (assignments remaining) become stale offline. Labeler may work on assignment another labeler already completed.
5. **Security**: Cached samples contain sensitive research data. Local storage must be encrypted.

**Design Options:**

1. **Full Offline Mode**: Cache samples, queue locally. Sync when online (complex, high conflict risk).
2. **Optimistic UI Only**: UI updates instantly (no server wait), but requires online connection for data fetch (simpler, no sync).
3. **Download-for-Offline**: Labeler explicitly downloads batch of assignments for offline work (controlled, batch sync).
4. **Online-Only**: No offline support (simplest, matches current LiveView architecture).

## Decision

**For CNS and initial Ingot deployments, implement ONLINE-ONLY mode with optimistic UI updates. Do NOT implement full offline PWA support. Rationale: CNS labelers have reliable connectivity, complexity of conflict resolution outweighs benefits. Reserve offline support for future use cases (field research, mobile) where offline necessity is clear.**

**However, prepare for future PWA by:**
1. Designing API for batch assignment downloads (future "offline mode" can use this)
2. Implementing optimistic UI updates in LiveView (instant feedback without server wait)
3. Documenting offline architecture for future implementation (when use case demands it)

### Optimistic UI (Online-Only)

**Current Flow (Pessimistic):**

```
Labeler clicks Submit
  → POST to Anvil (500ms)
  → Anvil validates, writes DB (200ms)
  → Response to Ingot (100ms)
  → Fetch next assignment (300ms)
  → Render new sample (200ms)
Total: 1300ms perceived latency
```

**Optimistic Flow:**

```
Labeler clicks Submit
  → UI immediately shows "Submitting..." (0ms)
  → UI loads next assignment from cache/pre-fetch (50ms)
  → Background: POST to Anvil (async)
  → If success: mark complete
  → If error: show error, revert to previous assignment
Total: 50ms perceived latency (26x faster)
```

**Implementation:**

```elixir
defmodule IngotWeb.LabelingLive do
  use IngotWeb, :live_view

  def handle_event("submit_label", params, socket) do
    %{assignment: assignment, label_data: label_data, next_assignment_cache: next_cache} = socket.assigns

    # Optimistic update: show next assignment immediately
    socket =
      if next_cache do
        socket
        |> assign(assignment: next_cache, sample: next_cache.sample, label_data: %{})
        |> push_event("label_submitted", %{assignment_id: assignment.id})
      else
        assign(socket, submitting: true)
      end

    # Async submission
    Task.start(fn ->
      case AnvilClient.submit_label(assignment.id, label_data) do
        :ok ->
          # Pre-fetch next assignment for next submit
          prefetch_next_assignment(socket.assigns.queue_id, socket.assigns.user_id)

        {:error, reason} ->
          send(self(), {:submit_error, assignment.id, reason})
      end
    end)

    {:noreply, socket}
  end

  # Handle submission error
  def handle_info({:submit_error, assignment_id, reason}, socket) do
    # Revert optimistic update, show error
    socket =
      socket
      |> put_flash(:error, "Submission failed: #{inspect(reason)}")
      |> assign(assignment: fetch_assignment(assignment_id))

    {:noreply, socket}
  end

  # Pre-fetch next assignment in background
  defp prefetch_next_assignment(queue_id, user_id) do
    case AnvilClient.get_next_assignment(queue_id, user_id) do
      {:ok, assignment} ->
        {:ok, sample} = ForgeClient.get_sample(assignment.sample_id)
        send(self(), {:next_assignment_ready, %{assignment | sample: sample}})

      {:error, _} ->
        :ok
    end
  end

  def handle_info({:next_assignment_ready, assignment}, socket) do
    {:noreply, assign(socket, next_assignment_cache: assignment)}
  end
end
```

### Future Offline Architecture (Design Only)

**For future implementation when offline use case is validated:**

#### Service Worker (PWA)

```javascript
// assets/js/service-worker.js
const CACHE_NAME = 'ingot-v1';
const OFFLINE_URLS = [
  '/',
  '/assets/app.css',
  '/assets/app.js',
  '/offline.html'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(OFFLINE_URLS);
    })
  );
});

self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((response) => {
      return response || fetch(event.request);
    }).catch(() => {
      // Offline: return cached offline page
      return caches.match('/offline.html');
    })
  );
});

// Background sync for label submissions
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-labels') {
    event.waitUntil(syncQueuedLabels());
  }
});

async function syncQueuedLabels() {
  const db = await openIndexedDB();
  const queuedLabels = await db.getAll('pending_labels');

  for (const label of queuedLabels) {
    try {
      await fetch('/api/labels', {
        method: 'POST',
        body: JSON.stringify(label),
        headers: {'Content-Type': 'application/json'}
      });
      await db.delete('pending_labels', label.id);
    } catch (error) {
      console.error('Sync failed for label', label.id, error);
    }
  }
}
```

#### Batch Download API

```elixir
defmodule IngotWeb.OfflineController do
  use IngotWeb, :controller

  @doc """
  Download batch of assignments for offline labeling.
  Returns ZIP file with:
  - assignments.json (assignment metadata + samples)
  - artifacts/* (images, audio files)
  - schema.json (label schema for validation)
  """
  def download_batch(conn, %{"queue_id" => queue_id, "count" => count}) do
    user_id = get_session(conn, :user_id)

    # Reserve N assignments for this labeler
    {:ok, assignments} = AnvilClient.reserve_batch(queue_id, user_id, String.to_integer(count))

    # Fetch samples and artifacts
    batch_data = Enum.map(assignments, fn assignment ->
      {:ok, sample} = ForgeClient.get_sample(assignment.sample_id)

      %{
        assignment_id: assignment.id,
        sample: sample,
        schema: assignment.schema
      }
    end)

    # Create ZIP file
    {:ok, zip_path} = create_offline_zip(batch_data)

    conn
    |> put_resp_header("content-disposition", "attachment; filename=\"offline_batch_#{queue_id}.zip\"")
    |> send_file(200, zip_path)
  end

  defp create_offline_zip(batch_data) do
    # Implementation: create ZIP with assignments.json + artifact files
    # Return path to temporary ZIP file
  end
end
```

#### Conflict Resolution Strategy

```elixir
defmodule Anvil.OfflineSync do
  @moduledoc """
  Handles syncing labels submitted offline.
  Conflict resolution: last-write-wins with duplicate detection.
  """

  def sync_offline_labels(user_id, labels) do
    Enum.reduce(labels, {:ok, []}, fn label, {:ok, acc} ->
      case submit_with_conflict_detection(label) do
        {:ok, result} ->
          {:ok, [result | acc]}

        {:error, :already_labeled} ->
          # Another labeler completed this assignment while offline
          # Skip this label, don't fail entire sync
          Logger.warning("Duplicate label detected", assignment_id: label.assignment_id, user_id: user_id)
          {:ok, acc}

        {:error, :schema_mismatch} ->
          # Schema changed while offline, label invalid
          {:error, :schema_version_conflict}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  defp submit_with_conflict_detection(label) do
    # Check if assignment already has label from another labeler
    case Anvil.Assignments.get(label.assignment_id) do
      {:ok, assignment} when assignment.status == :completed ->
        {:error, :already_labeled}

      {:ok, assignment} ->
        # Validate label against current schema version
        if assignment.schema_version == label.schema_version do
          Anvil.Labels.create(label)
        else
          {:error, :schema_mismatch}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

#### Local Storage Encryption

```javascript
// Encrypt cached samples with Web Crypto API
async function cacheSampleSecurely(sample) {
  const key = await getEncryptionKey();
  const encrypted = await crypto.subtle.encrypt(
    {name: 'AES-GCM', iv: new Uint8Array(12)},
    key,
    new TextEncoder().encode(JSON.stringify(sample))
  );

  await localforage.setItem(`sample_${sample.id}`, encrypted);
}

async function getEncryptionKey() {
  // Derive key from user password or session token
  const password = sessionStorage.getItem('encryption_password');
  const enc = new TextEncoder();

  return crypto.subtle.importKey(
    'raw',
    enc.encode(password),
    {name: 'PBKDF2'},
    false,
    ['deriveKey']
  ).then(baseKey =>
    crypto.subtle.deriveKey(
      {name: 'PBKDF2', salt: enc.encode('ingot'), iterations: 100000, hash: 'SHA-256'},
      baseKey,
      {name: 'AES-GCM', length: 256},
      true,
      ['encrypt', 'decrypt']
    )
  );
}
```

## Consequences

### Positive (Online-Only Decision)

- **Simplicity**: Leverages existing LiveView architecture. No PWA complexity (Service Workers, IndexedDB, sync logic).

- **Data Freshness**: Labels always submitted to authoritative Anvil. No stale data or conflict resolution bugs.

- **Security**: Samples never cached locally. No risk of sensitive research data leaking from lost devices.

- **Real-Time Collaboration**: LiveView PubSub updates work. Admins see labeler progress live, labelers see queue stats update.

- **Faster Time-to-Market**: No offline development needed for CNS launch. Can revisit if future use case demands it.

### Negative (Online-Only Decision)

- **Network Dependency**: Labelers cannot work without internet. Even brief disconnections pause labeling.
  - *Mitigation*: Optimistic UI reduces perceived latency. Labelers get instant feedback, server call happens in background.

- **Mobile Experience**: On slow 3G/4G, fetching next assignment after submit may feel laggy.
  - *Mitigation*: Pre-fetch next assignment while labeler reviews current sample. Cache 1 assignment ahead.

- **Field Research Blocked**: Cannot support offline field research scenarios (yet).
  - *Acceptance*: Current CNS use case doesn't require this. Future medical/audio use cases can trigger offline implementation.

### Positive (Optimistic UI)

- **Instant Feedback**: Submit button shows immediate response. Labeler doesn't wait for server confirmation to see next sample.

- **Perceived Performance**: 50ms perceived latency vs 1300ms pessimistic. 26x improvement in user experience.

- **Error Handling**: Background submission failures surface as toast notification. Doesn't block labeler from continuing work.

### Negative (Optimistic UI)

- **Edge Case Complexity**: If submission fails, must revert optimistic update. Labeler may have started labeling "next" sample.
  - *Mitigation*: On error, show modal: "Previous submission failed. Please retry." Prevent starting new assignment until resolved.

- **Pre-Fetch Overhead**: Fetching next assignment before current submitted wastes resources if labeler abandons session.
  - *Mitigation*: Only pre-fetch after first successful submit (indicates labeler is actively working).

### Neutral (Future Offline Design)

- **PWA Infrastructure**: Service Worker, IndexedDB, Background Sync APIs are well-supported in modern browsers (Chrome, Firefox, Safari 16+).

- **Conflict Resolution**: Last-write-wins with duplicate detection is simple but may frustrate labelers (wasted offline work).
  - Alternative: CRDTs (Conflict-Free Replicated Data Types) for automatic merge, but very complex for structured labels.

- **Storage Limits**: IndexedDB quota varies (50MB-1GB depending on browser/device). Large samples (medical imaging) may exceed quota.
  - Need quota management (evict old samples, warn labeler when quota low).

## Implementation Checklist (Online-Only with Optimistic UI)

1. ✅ Implement optimistic UI in LabelingLive (assign next assignment immediately)
2. ✅ Add background submission (Task.async for submit_label)
3. ✅ Add error handling (revert on submission failure)
4. ✅ Implement pre-fetch (get_next_assignment after successful submit)
5. ✅ Add client-side feedback (push_event for "label_submitted")
6. ⬜ Test optimistic UI edge cases (submission failure, network timeout)
7. ⬜ Document optimistic UI behavior in user guide

## Implementation Checklist (Future Offline PWA)

**Only implement if offline use case is validated:**

1. ⬜ Register Service Worker in app.js
2. ⬜ Implement cache-first strategy for static assets
3. ⬜ Add IndexedDB for offline label queue
4. ⬜ Implement `OfflineController.download_batch/2` (ZIP export)
5. ⬜ Add conflict detection in `Anvil.OfflineSync`
6. ⬜ Implement background sync (Service Worker sync event)
7. ⬜ Add local storage encryption (Web Crypto API)
8. ⬜ Build offline UI (show "Offline Mode" banner, queued labels count)
9. ⬜ Test offline scenarios (airplane mode, intermittent connectivity)
10. ⬜ Document offline workflow (download batch → label → sync)

## Decision Criteria for Future Offline Implementation

Implement full offline PWA if ANY of these criteria are met:

1. **Validated Use Case**: >10 labelers request offline mode for specific workflow (e.g., field research)
2. **Mobile-First Deployment**: >50% of labelers access Ingot from mobile devices in low-connectivity areas
3. **Compliance Requirement**: Research protocol mandates offline data collection (no internet in lab)
4. **Performance Requirement**: Network latency >500ms impacts labeler productivity (measured via telemetry)

**Decision Process:**

1. Product team validates use case (user interviews, surveys)
2. Engineering estimates implementation cost (4-6 weeks for full PWA)
3. Cost-benefit analysis (labeler productivity gain vs engineering investment)
4. If approved, implement using architecture documented above

## Related ADRs

- ADR-001: Stateless UI Architecture (optimistic UI fits stateless model)
- ADR-005: Realtime UX (LiveView provides real-time updates, incompatible with offline)
- ADR-002: Client Layer Design (offline mode would require local client implementation)
