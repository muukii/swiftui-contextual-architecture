# Context and Work Lifecycles

## Represent the ownership graph as state

Create a Session container with a specified environment and identity before login. Authentication is a state transition inside it, not the event that creates it. The process/app root owns a registry of these containers and their selection; it is not the per-environment Session itself.

```text
App root / registry
|-- retained Sessions
|   `-- Session (fixed environment, SessionID)
|       |-- session-scoped services and storage
|       |-- UIContext
|       `-- authentication state
|           |-- unauthenticated child / authentication attempt
|           `-- authenticated child / authenticated services
`-- selected SessionID?
```

For a single-Session app, retain one such container. For multiple Sessions, keep `retained Sessions` separate from the `selected Session`: selection is not ownership. Unauthenticated Sessions can be retained and selected too. Multiple Sessions may target the same environment without sharing session-scoped resources. When multiple windows display the same Session, share its services, UIContext where appropriate, and any in-flight resolution task through the root or registry.

Use UIContext as the source of truth for externally controlled screen state, and service contexts as the owners of operations and domain resources. Do not construct authenticated-only services before login. Work sessions, such as recordings and imports, belong under the appropriate Session-owned scope and have identities distinct from Session and authentication. When replacing a Session or authenticated child, reset SwiftUI's local state as needed, for example with `.id(...)`, so the previous user's input and navigation do not remain.

Choose isolation such as `@MainActor` for UIContext to keep UI state consistent. It does not make a transition atomic across `await`. Define whether duplicate requests join the same task and whether competing requests are rejected or queued. The owner that starts a task, stream subscription, notification observer, or timer must also own how it stops.

## Give each identifier a specific role

| Identity | Purpose |
| --- | --- |
| Service environment | Separate hosts, tenants, and development or production deployments |
| Account ID | Identify the authenticated account; it may be the same after another login |
| Session ID | Identify the environment-bound container from before login. Preserve it across authentication success; use a new one for a replacement Session. If restoration is supported, persist it to identify a continuing Session's storage scope across process restarts |
| Runtime generation / owner identity | Decide whether a result may commit to the current context |
| Credential slot / revision | Prevent old work from deleting newer credentials; introduce this distinction when needed |
| Attempt ID | Associate authentication requests with callbacks and reject canceled or superseded attempts |

Introduce only the distinctions the app needs. A Session ID is not an Account ID or a process launch ID. Because Session identity is preserved across login, use an attempt or authentication generation to reject superseded authentication work within it. Reject obsolete results after replacement even when the same account logs out and returns.

## Commit authentication inside a Session and restore its state

Construct the Session's pre-login dependencies first. The Session-owned authentication owner validates the result and binds it to that Session's fixed environment, identity, and attempt. Prepare and publish an authenticated child inside the existing Session; do not replace the outer container merely because login succeeded. Do not manufacture authenticated state from a UIIntent such as `.showHome`.

If restoration is supported, restore the continuing Session's environment and identity, then validate its authentication metadata and required credentials before publishing authenticated capabilities. An unauthenticated Session does not require credentials. Do not treat corrupt or unreadable data as absent data and silently create another identity.

Immediately before publishing a prepared authenticated child, recheck that its originating Session is still live and its attempt or generation is still valid. Intermediate persistence and credential updates need validity checks at the owner of those operations as well; a final root-level check cannot prevent earlier contamination. Cleanup of an invalid result must target only resources owned by that attempt, without accidentally ending the current context with the same identity.

Retain attempts for one-time email links and similar inputs under an appropriate owner so replacing a view cannot consume the input twice. Once a link has been consumed, retain authentication completion or rollback until consistency is restored, even if the view's work is canceled. Define whether another attempt can begin after authentication rollback fails. Distinguish these operations from a search that can simply be discarded when its UI closes.

## Dispose from any phase; replace the whole Session on logout

A Session can be explicitly ended before login, while authentication is in flight, or after login. End the owned authentication attempt as well as authenticated work when applicable. If an attempt has consumed a one-time input, retain its completion or rollback under the termination owner until consistency is restored, but never admit its result into a replacement Session. Disposal is an ordered lifecycle operation, not immediate success on dropping a reference.

Use this default logout contract:

```text
Session A (environment E, authenticated)
  -> reserve termination, save required state, retire and invalidate A
  -> stop/drain A's work and close its resources
  -> create Session B (environment E, new SessionID, unauthenticated)
```

Session B uses fresh session-scoped dependencies and storage bindings, not A's reset objects. Any explicitly retained account data must be recovered through a defined policy, not by reviving A. Physical cleanup may continue under a separate owner only after A is isolated and cannot mutate B. If a global SDK cannot isolate concurrent Sessions or cleanup, serialize its teardown and new authentication instead of assuming new Swift objects provide isolation.

Changing environments also requires a different Session, not mutating the environment of an existing container. Selecting another retained Session does not dispose the old one. An alternate logout policy must explicitly establish equivalent isolation rather than silently treating an authentication flag reset as whole-Session replacement.

## Give termination explicit stages

These stages apply in unauthenticated and authenticated phases; skip only work that does not exist in that phase. They constrain ordering, not a separate type for every stage. Accept a disposal request in any phase, but retain recoverable state and report failure if required shutdown cannot complete.

### 1. Reserve the transition and control admission

Retain the termination task in the root or a dedicated owner, independently of a view's lifetime or cancellation by one waiter. Duplicate requests join the same operation. Control admission of new edits, recordings, synchronization, authentication results, and other work in the affected scope so they cannot race with termination. Do not affect unrelated sessions.

### 2. Complete reversible preparation

Define how to save drafts, finish recording, and handle unfinished work before explicit logout or shutdown. When terminating multiple owners, complete every required save before starting irreversible retirement. If saving fails, retain the affected owner and drafts, and define which capabilities can resume or be retried. Decide whether previously admitted work should finish or be canceled according to the operation's meaning; do not hide an operation that succeeded on the server by merely reporting it as canceled.

Credential expiration has a different contract. Immediately block work using invalid credentials, and do not restore authenticated capabilities because a local save failed. When necessary, retain a state that allows recovery of unsaved local data while authentication remains ended.

### 3. Commit the termination decision

If metadata or credential changes are required to prevent restoration, persist them successfully before reporting completion. A process crash must not cause invalid credentials to be adopted again. When multiple stores cannot be updated atomically, consider recording pending retirement and completing it during startup.

Invalidate the old generation within the same isolation boundary as the termination decision. Reject subsequent UI, persistence, and token updates from ordinary work in that generation. Treat rollback, journal updates, and cleanup performed by the termination owner against its fixed old slot as a separate capability. If persisting retirement fails, retain the target identity and recovery state instead of reporting completion.

If an explicit sign-out fails without changing credentials, and the existing owner and credentials are confirmed valid, reopen admission only after successfully canceling the retirement reservation. Allow retry using the same owner. For partial success, an unknown outcome, or failed rollback, keep admission closed and retain recovery state. If SDK sign-out already succeeded, do not roll back to a state that pretends the credentials still exist.

### 4. Stop work and close resources

After stopping new work, request task cancellation, unsubscribe streams and observers, stop network operations, child processes, or recording, and await the required completion. Close admission from parent to child, drain dependent work, and then close the stores it uses. Do not delete a database or directory while a child still uses it.

Swift cancellation is cooperative: `cancel()` alone does not automatically stop arbitrary work. Separate a cancellation request from confirmation that work has ended. [Apple: Task.cancel()](https://developer.apple.com/documentation/swift/task/cancel%28%29)

If work cannot be stopped, contain it in its invalidated scope, keep its persistence capabilities disabled, and report the failure. A fixed sleep or timeout does not prove that a resource is closed. Tracking SDK callback completion does not necessarily track all activity inside the SDK. Use `deinit` for diagnostics or a final defensive action, not as the owner of asynchronous saving or shutdown.

### 5. Apply cleanup policy and update published state

Credential invalidation, store closure, Session identity retirement, and data deletion are separate operations. An unauthenticated Session still needs work shutdown and resource closure, even when it has no credentials to remove. Adapt cleanup to the SDK and product requirements, while first establishing the boundary that prevents a replacement Session from reusing old credentials. Preserve the exact target and retry state when deletion fails, and do not touch the replacement's storage.

Showing the replacement's login screen may happen before old cleanup is complete only if isolation is established. The termination owner retains the old container while cleanup is in progress and removes it from the registry after completion; it is not selectable for ordinary work after retirement. Do not ignore deletion failures and report that data was erased.

## Windows, selection, and the process

| Operation | Outcome to define |
| --- | --- |
| Window close | End that window's UI; decide whether the shared Session and unsaved edits remain |
| Deselect / show an unauthenticated Session | Do not implicitly log out or dispose the previous selection; specify which background work continues and which work, such as recording, stops |
| Select another Session | Adjust work in the previous selection, activate the new selection, and update any SDK-wide user state |
| Dispose one Session | Save as applicable, retire, and terminate only that container and its children, including pre-login attempts |
| Logout | Dispose the authenticated Session and create a fresh unauthenticated Session for the same environment by default |
| Process quit / update | Confirm all required saves, then drain work. Do not retire a continuing Session's restoration identity merely because the process is exiting. Respond asynchronously to OS termination requests when needed |

Define recovery after a crash rather than assuming orderly shutdown always runs.

## Reject late results at the commit boundary

- Capture the environment, scope, and owner generation when starting a task.
- After suspension, check that the owner is still current within its isolation boundary. Do not insert another `await` between that check and a synchronous state change.
- Check validity at the storage owner's serialization boundary as well. If the actual write is asynchronous, also guarantee its ordering relative to close and drain.
- Route cancellation-ignoring results and SDK callbacks through the same boundary.
- Associate cleanup with its own generation so an old task's `defer` cannot clear a newer task's loading state or task reference.
