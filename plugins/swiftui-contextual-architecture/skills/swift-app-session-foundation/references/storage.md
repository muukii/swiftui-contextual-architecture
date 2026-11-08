# Storage Scopes and Cleanup

## Build a data-retention table

For each actual resource, record its constructor or owner, storage key or path, startup restoration behavior, logout behavior, process-exit behavior, and retry behavior after failure. The table below offers classifications; it does not decide what should be deleted.

| Scope | Examples | Decision to make |
| --- | --- | --- |
| Process / device | Window positions, account-independent model files | Whether sharing across all users is appropriate |
| Environment | Connection settings, login catalog | How staging, production, and tenants remain isolated |
| Account | Local data shared across logins | How the account is validated and how reconnection works |
| Login lifetime | Databases, personal preferences, working directories, caches | How a continuing login is restored and retired identities are kept out of reuse |
| Credential generation | Authentication SDK state, token slots | How old logout or refresh work is prevented from deleting newer credentials |
| Operation | Temporary files, in-progress recordings | Who owns cancellation, promotion to retained storage, and recovery after a crash |

Also inventory credentials, API keys for external services such as AI providers, cookies and HTTP caches, image caches, and user identity held by analytics or crash-reporting SDKs. Include user data retained in memory caches, streams, and notification delivery. Follow the target app's secure storage policy for secrets; do not move them into ordinary preferences merely because a reference implementation does so.

## Bind storage destinations immutably

Fix the environment and login identity when constructing a container, then derive its storage destinations. One example is `Environments/<environment>/Sessions/<login-id>/...` with a dedicated preferences domain; this layout is not mandatory. Use typed identities and a collision-resistant identification method. A timestamp alone must not be the guarantee that scopes are distinct.

Do not later resolve personal stores again through `currentAccount`, `selectedEnvironment`, `UserDefaults.standard`, or similar mutable global state. A store retained by old work must point only to its original scope and reject writes once that owner is no longer valid. If an SDK exposes only global state, coordinate access and define deselect, clear, and select behavior during transitions.

Do not construct duplicate databases or services for the same identity outside the root or registry. If multiple processes or extensions access the same scope, an in-process actor alone cannot coordinate them; inspect database transactions and cross-process ownership constraints. Do not add unnecessary machinery to a single-process app.

## Distinguish release, close, retire, and purge

| Operation | Meaning |
| --- | --- |
| Release | Give up an owning reference; this does not mean data was deleted |
| Close | Stop new use, drain work, and close resources such as databases |
| Retire | Remove a login identity or credentials from the set eligible for restoration |
| Purge | Physically delete the targeted data; verify both the target and the outcome |
| Remote revocation | Invalidate credentials on the server; this has an outcome independent of local erasure or logout |

Preserve domain data that the product requires retaining. Distinguish retired storage from storage eligible for restoration, and define later deletion or explicit recovery as separate flows. Changing the storage destination alone does not establish completed deletion or secure erasure.

## Keep cleanup independent of the next login

Give each cleanup job the exact retired environment, login identity, credential slot, and store identifiers. Do not derive deletion targets from the current session when the job runs. Operate only on validated targets beneath the allowed root; do not broadly delete other users' storage or shared model files.

After excluding the old scope from restoration, finish outstanding handle use and writes, then perform required deletion. Deletion may be deferred when immediate erasure is not a requirement, but isolation and ineligibility for restoration must be established first. Cleanup at the next launch must identify protected scopes through a catalog or another explicit source of ownership; do not choose the active scope solely by modification time.

When credentials rotate between slots, old work may delete only its specified slot. Preserve current credentials if the slot no longer matches. If files, preferences, and Keychain or SDK state cannot participate in one transaction, define the possible intermediate states and persist a small journal when needed. A journal is not mandatory for every app.

Make failed cleanup retryable against the same target. An already absent resource may count as success, but record permission and I/O failures. Do not claim completion through unbounded retries or swallowed errors. Report remote revocation and the local termination policy separately when networking fails.
