# Storage Scopes and Cleanup

## Build a data-retention table

For each actual resource, record its constructor or owner, storage key or path, startup restoration behavior, Session-disposal/logout behavior, process-exit behavior, and retry behavior after failure. A Session begins before login with a fixed environment and identity; storage ownership must not depend on a user already being authenticated. The table below offers classifications; it does not decide what should be deleted.

| Scope | Examples | Decision to make |
| --- | --- | --- |
| Process / device | Window positions, account-independent model files | Whether sharing across all users is appropriate |
| Environment | Connection settings, Session catalog | How staging, production, and tenants remain isolated |
| Session | Pre-login preferences, working directories, caches, and session-owned stores | How destinations are bound before login, a continuing Session is restored, and replacement Sessions avoid retired resources |
| Account | Local data explicitly retained across Sessions | How the account is validated and recovery is separated from reuse of an old Session's live stores |
| Authenticated child | Personal databases and authenticated caches | How resources are bound to the enclosing Session and verified account only after authentication |
| Credential generation | Authentication SDK state, token slots | How old logout or refresh work is prevented from deleting newer credentials |
| Operation | Temporary files, in-progress recordings | Who owns cancellation, promotion to retained storage, and recovery after a crash |

Also inventory credentials, API keys for external services such as AI providers, cookies and HTTP caches, image caches, and user identity held by analytics or crash-reporting SDKs. Include user data retained in memory caches, streams, and notification delivery. Follow the target app's secure storage policy for secrets; do not move them into ordinary preferences merely because a reference implementation does so.

## Bind storage destinations immutably

Fix the environment and Session identity when constructing the Session before login, then derive its storage destinations. One example is `Environments/<environment>/Sessions/<session-id>/...` with a dedicated preferences domain; this layout is not mandatory. Use typed identities and a collision-resistant identification method. A timestamp alone must not be the guarantee that scopes are distinct.

Authentication success preserves the enclosing Session's identity and root; construct authenticated-only stores beneath the appropriate scope after verifying the account. Do not eagerly open personal databases merely to create an unauthenticated Session. Default logout replacement uses a new Session identity and fresh session-scoped bindings even for the same environment or account. Restoring a continuing Session after process restart is distinct from reviving a disposed one; any cross-Session account data recovery must be explicit.

Do not later resolve personal stores again through `currentAccount`, `selectedEnvironment`, `UserDefaults.standard`, or similar mutable global state. A store retained by old work must point only to its original scope and reject writes once that owner is no longer valid. If an SDK exposes only global state, coordinate access and define deselect, clear, and select behavior during transitions.

Do not construct duplicate databases or services for the same identity outside the root or registry. If multiple processes or extensions access the same scope, an in-process actor alone cannot coordinate them; inspect database transactions and cross-process ownership constraints. Do not add unnecessary machinery to a single-process app.

## Distinguish release, close, retire, and purge

| Operation | Meaning |
| --- | --- |
| Release | Give up an owning reference; this does not mean data was deleted |
| Close | Stop new use, drain work, and close resources such as databases |
| Retire | Remove a Session identity or credentials from the set eligible for restoration |
| Purge | Physically delete the targeted data; verify both the target and the outcome |
| Remote revocation | Invalidate credentials on the server; this has an outcome independent of local erasure or logout |

Disposing a Session composes the required stop, close, retirement, and release operations, whether or not login occurred. It does not automatically purge persistent files or remotely revoke credentials. Preserve domain data that the product requires retaining. Distinguish retired storage from storage eligible for restoration, and define later deletion or explicit recovery as separate flows. Changing the storage destination alone does not establish completed deletion or secure erasure.

## Keep cleanup independent of the replacement Session

Give each cleanup job the exact retired environment, Session identity, credential slot if any, and store identifiers. This also applies when disposing an unauthenticated Session. Do not derive deletion targets from the currently selected Session when the job runs. Operate only on validated targets beneath the allowed root; do not broadly delete other Sessions' or users' storage or shared model files.

After excluding the old scope from restoration, finish outstanding handle use and writes, then perform required deletion. Deletion may be deferred when immediate erasure is not a requirement, but isolation and ineligibility for restoration must be established first. Cleanup at the next launch must identify protected scopes through a catalog or another explicit source of ownership; do not choose the active scope solely by modification time.

When credentials rotate between slots, old work may delete only its specified slot. Preserve current credentials if the slot no longer matches. If files, preferences, and Keychain or SDK state cannot participate in one transaction, define the possible intermediate states and persist a small journal when needed. A journal is not mandatory for every app.

Make failed cleanup retryable against the same target. An already absent resource may count as success, but record permission and I/O failures. Do not claim completion through unbounded retries or swallowed errors. Report remote revocation and the local termination policy separately when networking fails.
