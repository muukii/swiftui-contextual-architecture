# Lifecycle verification

Verify the contracts implemented by the target app. Select relevant cases from the table according to its single- or multiple-session model, storage design, and authentication integration; do not add every case mechanically.

Use fakes that let tests control Task start and completion, a dedicated test storage root, and injectable credential stores or session factories. Do not reproduce races with fixed sleeps. Do not delete active user data or production credentials to verify cleanup.

| Scenario | Observable result |
| --- | --- |
| Logged-out startup | Logged-in services, recording, and personal databases are not created unnecessarily |
| Authentication succeeds / multiple scenes resolve concurrently | Exactly one owner is published after preparation |
| Only the View or waiter is cancelled during authentication | An authentication attempt with the required lifetime continues through commit or rollback. Other waiters are unaffected, and a still-valid attempt's result is accepted according to its contract |
| The authentication attempt itself is invalidated or replaced | The old callback cannot commit to the current owner's UI, credentials, or stored data. Rollback and cleanup of the old slot can finish without mistakenly terminating current resources |
| A logs out → B logs in → A's delayed result arrives | B's UI, database, and token remain unchanged; writes by A after retirement are also rejected |
| The same account logs in again | Results from the old generation are rejected even though the Account ID is unchanged |
| Duplicate logout / expiration notifications | Requests join the same termination operation, with consistent close and retirement outcomes |
| Switch / login / quit during termination | The defined rejection, waiting, or joining behavior applies. Completion order does not roll state back |
| Draft save fails | Explicit termination remains incomplete. Data and its owner remain recoverable |
| Explicit sign-out fails | The same owner can retry if credentials remain valid and retirement cancellation succeeds. Partial success, an unknown result, or failed rollback does not reopen admission |
| Authentication expires and a save fails | Authenticated capabilities do not return; only the necessary local recovery remains available |
| Catalog corruption / I/O failure | A recoverable error is reported instead of silently switching to another ID or overwriting data |
| Restart during an ongoing login | The storage scope is restored according to its contract |
| Interruption during retirement → restart | Invalid credentials are not restored, and pending cleanup is reapplied to the correct target |
| Old cleanup is retried after B logs in | Only A's specified storage or slot is targeted. B and shared resources are preserved |
| An operation completes despite ignoring cancellation | Stale results are rejected. The store is not considered closed before its writes finish |
| A window closes | Remaining windows and their shared owner continue according to the contract |
| Selection changes | Background work designated for retention continues, and work designated to stop, such as recording, drains |
| One session ends | Other sessions' stores, operations, and SDK selection are unaffected |
| App quit / update | Exit is allowed only after required saves and draining have been confirmed for every affected owner |
| UIIntent deferral / duplication / invalidation | Input is handled once in the correct session, and a request for the previous user is not delivered to the next user |

Check remaining files and stored values, published state, rejected writes, and stopped observer delivery, rather than only method call counts. When order matters, record and verify “last write → close → purge.” Deinitialization is not a substitute for asynchronous completion.

Report state transitions verified with stubs separately from sign-in, refresh, expiration, and sign-out exercised with a real provider. Explicitly retain any gaps in multiwindow interaction, OS termination, actual recording, or real storage-failure verification.
