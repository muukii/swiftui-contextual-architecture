# Lifecycle verification

Verify the contracts implemented by the target app. Select relevant cases from the table according to its single- or multiple-session model, storage design, and authentication integration; do not add every case mechanically.

Use fakes that let tests control Task start and completion, a dedicated test storage root, and injectable credential stores or session factories. Do not reproduce races with fixed sleeps. Do not delete active user data or production credentials to verify cleanup.

| Scenario | Observable result |
| --- | --- |
| Create a Session for a specified environment before login | A container with a fixed environment and Session identity exists without an Account ID or credentials. Only pre-login dependencies are created |
| Authentication succeeds inside a Session | The authenticated child is published after preparation; the enclosing Session identity and environment do not change |
| Multiple scenes resolve the same Session concurrently | Exactly one Session owner and shared construction task are used; no duplicate session-scoped stores are opened |
| Dispose an unauthenticated Session | Its pre-login work and resources stop and close without requiring a logged-in child; other Sessions remain usable |
| Dispose during authentication | The old attempt completes or rolls back under the termination owner; late success cannot authenticate the replacement or recreate an ended Session |
| Logout replaces the whole Session | The old owner is retired and isolated; a fresh unauthenticated Session in the same environment has a new identity and fresh session-scoped dependencies, not reset old objects |
| Request a different environment | A different Session is created or selected; the existing Session's environment and storage destinations remain unchanged |
| Only the View or waiter is cancelled during authentication | An authentication attempt with the required lifetime continues through commit or rollback. Other waiters are unaffected, and a still-valid attempt's result is accepted according to its contract |
| The authentication attempt itself is invalidated or replaced | The old callback cannot commit to the current owner's UI, credentials, or stored data. Rollback and cleanup of the old slot can finish without mistakenly terminating current resources |
| A logs out → B logs in → A's delayed result arrives | B's UI, database, and token remain unchanged; writes by A after retirement are also rejected |
| The same account logs in again after logout replacement | Session identity differs, old-generation results are rejected, and retained account data is recovered only through the explicit policy |
| Duplicate logout / expiration notifications | Requests join the same termination operation, with consistent close and retirement outcomes |
| Switch / login / quit during termination | The defined rejection, waiting, or joining behavior applies. Completion order does not roll state back |
| Draft save fails | Explicit termination remains incomplete. Data and its owner remain recoverable |
| Explicit sign-out fails | The same owner can retry if credentials remain valid and retirement cancellation succeeds. Partial success, an unknown result, or failed rollback does not reopen admission |
| Authentication expires and a save fails | Authenticated capabilities do not return; only the necessary local recovery remains available |
| Catalog corruption / I/O failure | A recoverable error is reported instead of silently switching to another ID or overwriting data |
| Restart with a continuing unauthenticated or authenticated Session | Its environment and storage identity are restored only if supported; authenticated capabilities require credential validation, and retired Sessions are not revived |
| Interruption during retirement → restart | Invalid credentials are not restored, and pending cleanup is reapplied to the correct target |
| Old cleanup is retried after B logs in | Only A's specified storage or slot is targeted. B and shared resources are preserved |
| An operation completes despite ignoring cancellation | Stale results are rejected. The store is not considered closed before its writes finish |
| A window closes | Remaining windows and their shared owner continue according to the contract |
| Retain/select unauthenticated and authenticated Sessions, including two in the same environment | Selection does not imply login or dispose other containers; session-scoped resources remain isolated |
| Selection changes | Background work designated for retention continues, and work designated to stop, such as recording, drains |
| One Session ends | Other Sessions' stores, operations, and SDK selection are unaffected |
| App quit / update | Exit is allowed only after required saves and draining have been confirmed for every affected owner |
| UIIntent deferral / duplication / invalidation | Input is handled once in the destination Session, and an ended Session's pending input is not delivered to its replacement or another user |

Check remaining files and stored values, published state, rejected writes, and stopped observer delivery, rather than only method call counts. When order matters, record and verify “last write → close → purge.” Deinitialization is not a substitute for asynchronous completion.

Report state transitions verified with stubs separately from sign-in, refresh, expiration, and sign-out exercised with a real provider. Explicitly retain any gaps in multiwindow interaction, OS termination, actual recording, or real storage-failure verification.
