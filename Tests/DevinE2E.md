# Devinによる画面操作テスト

この文書は、Devinがアプリを操作して再実行するための**テスト仕様**です。過去の実行結果や動画の書き起こしではありません。コードで管理する回帰テストは別の [XCUITest](../ModelArchitectureUITests/SessionUITests.swift)、内部の所有・終了順序は [モデルテスト](ContextualArchitectureDemoTests/SessionLifecycleTests.swift)が担当します。

## 実行契約

- 対象のブランチ・commit、Xcode、Simulatorの機種・OSを記録する。コード変更後は必ずその版をビルド・インストールし直す。
- Simulatorの実画面を操作して判定する。内部の状態を書き換えたり、モデルテストの成功を画面操作の成功として代用したりしない。URLはOSの通常のURL起動経路から渡してよい。
- 各ケースは独立して実行する。特記がなければアプリのプロセスを終了して起動し直し、以下の共通前提を確認する。このデモはメモリのみのため、新しいProduction Sessionが1つ生成される。
- 共通前提を確認できなければ **blocked / untested** とし、別の開始状態で代替してpassにしない。
- UUIDは実行ごとに変わる。表示中の値を採取して前後・Session間で比較する。過去の動画のUUIDや短縮表示を固定の期待値にしない。Ownership detailsでフルUUIDを確認する。
- 固定秒数の待機ではなく、画面・状態の到達を待つ。UIが到達しない場合は状況を記録して失敗とする。モックのコールバック待ちは、指定の操作で明示的に解放する。
- テキスト入力・フォームのdraftはViewローカル。Session切り替えでのdraft保持は要求しない。同じ画面の再評価では保持される必要がある。
- 失敗時はケースID、操作、期待値、実際の値、commitを記録し、スクリーンショットを残す。修正後は影響するケースを再実行し、旧版の結果と混ぜない。

### 共通の開始状態

1. トップバーが **Production / Not signed in**、本文が **Your Session already exists**。
2. **Sessions**を開くと、Retained containersが **1**、Stored valueが **0**。
3. Ownership detailsにSession・Pre-login services・StorageのUUIDがあり、Authenticated servicesは **not created**。
4. **Callbacks**に待機中のリクエストがない。
5. 作成されたSession UUIDを `A` として記録する。Aはこの実行の記号であり、固定値ではない。

## ケース一覧と自動テストの対応

ケース定義とXCUITestは別々に保守する。対応欄は現在の重複範囲を示し、自動テストの成功だけでDevin実行をpassにしない。

| ID | Devinが確認する境界 | 対応するXCUITestメソッド |
|---|---|---|
| DEVIN-01 | ログイン前の所有・認証成功／失敗 | `testLoginPreservesOwnershipAndProfileDraft`, `testAuthenticationFailureAllowsRetryInSameSession` |
| DEVIN-02 | 複数認証済みSessionの保持・状態分離 | `testRetainedSessionsKeepIndependentAccountsAndNavigation` |
| DEVIN-03 | 終了待ち・古い結果の拒否・再生成・選択維持 | `testLogoutDrainsLateWriteWithoutStealingSelection` |
| DEVIN-04 | 認証中の破棄・遅延成功の拒否 | `testDisposalDuringAuthenticationRejectsLateSuccess` |
| DEVIN-05 | 未認証Sessionの破棄・ゼロ件からの作成 | `testUnauthenticatedDisposalLeavesNoSessions` |
| DEVIN-06 | Sessionに束縛された保留ルート | `testDeferredDeepLinkReplaysOnlyInItsSession` |
| DEVIN-07 | タブ・Route Lab・制限解除の回帰 | `testRouteLabAndRestrictionPreserveTabs` |
| DEVIN-08 | アカウント由来のdraftとViewローカル状態 | `testLoginPreservesOwnershipAndProfileDraft`（再評価の追加操作はDevin側） |

## DEVIN-01 — Sessionはログイン前から存在する

**開始状態:** 共通前提。

1. Aの環境、Session / Pre-login services / StorageのフルUUIDを記録する。
2. **Increment Session Value**を1回押す。未認証のまま値が **1** になること。
3. Doneで戻りTaylorを選んでSign In。明示的に完了させるまで **Signing in** が続くこと。途中でSessionsを開いてもAと保存値は変わらないこと。
4. **Fail Sign In**を押す。エラーが表示され、同じAで再試行できること。
5. Sign In → Complete Sign In → Continue → Finish Setup → Enter App。AccountがTaylorになること。
6. Ownership detailsを比較する。3つのUUID・環境・値1は不変で、Authenticated servicesのUUIDだけが追加されること。

**判定:** ログインがSession生成ではなく、同じSessionへの子スコープ追加になっている。失敗でもSessionや既存値を失わない。

**証跡:** ログイン前後のOwnership details、エラーから再試行する操作。

## DEVIN-02 — 選択は所有・認証・破棄とは別

**開始状態:** 共通前提からAをJordanで認証し、セットアップを完了。

1. Aの値を1にする。Account → PreferencesでCompact AppearanceをONにし、Preferencesを表示したままにする。
2. SessionsのNew containerでStagingを選びCreate Session。新しいSessionを `B` として記録する。
3. Bは未認証、値0、環境Staging、3つのUUIDすべてがAと異なること。
4. BをTaylorで認証し、値を2にする。Retained containersには認証済みのAとBが同時にあること。
5. Aを選択する。Jordanの認証、値1、元のUUID、PreferencesのパスとCompact Appearance ONが戻ること。
6. Bを選択する。TaylorのAccount、値2、BのUUIDが保たれていること。

**判定:** 切り替えがlogoutや再生成を起こさず、各Sessionの環境・アカウント・保存値・UIContextが独立している。

**証跡:** 両方を保持する一覧、各SessionのAccountと保存値、復元されたPreferences。

## DEVIN-03 — 旧Sessionの終了を待って丸ごと置き換える

**開始状態:** 共通前提からAを認証し値を1にする。Stagingの未認証Bを追加してからAを選択。待機中のリクエストはない。

1. Aの3つのUUIDを記録し、Start Background Write → Log Out & Replace Session。
2. コールバックを解放せずに確認する。
   - AはClosing、Increment / Start Background Write / Disposeが無効。
   - Aの値は1のまま。AとBの2件が保持され、新しいProduction Sessionはまだ存在しない。
3. Bを選択する。Aの終了待ち中でもBを利用できること。
4. CallbacksからAの書き込みをDeliver Successする。
5. Eventsで、同じAに対する **Rejected late callback → Work drained; store closed → Session disposed** を確認する。表示は新しいイベントが上なので、時系列は下から読む。
6. Aのdisposal記録のfinal valueは1。Aは一覧から消え、Productionの新しい未認証Session `C` が追加される。選択はBのままであること。
7. Cを選択して確認する。環境はProduction、3つのUUIDはAと異なる、値0、Authenticated servicesはnot created。
8. Bの環境・UUID・値0も変化していないこと。

**判定:** キャンセル要求だけで終了扱いにせず、古い結果を拒否してdrainし、その後で再生成する。遅延結果がC/Bに書き込まれず、途中の選択も奪わない。

**証跡:** 解放前のClosingと一覧、イベント順序、Aのfinal value、CのOwnership details、選択中B。

## DEVIN-04 — 認証中でも破棄でき、遅延成功は復活させない

**開始状態:** 共通前提。

1. AにPreferencesへのURLを送り、Queued routeを確認する。
2. Sign In → **Dispose During Sign In**。Complete Sign Inは先に押さない。
3. AがClosingの間、まだ保持されていること。新規操作ができず、保留ルートが引き継がれる新Sessionもないこと。
4. **Deliver Pending Callbacks**で遅延成功を届ける。
5. EventsにAの認証結果拒否とdisposalがあること。Aは認証済みで復活せず、Retained containersは0。通常のDisposeは置き換えを作らない。
6. Production Sessionを新規作成する。Aとは異なるUUID、値0、認証済みサービスなし、Queued routeなしであること。

**判定:** 古い認証成功・保留ルートが破棄後のSessionに越境しない。

**証跡:** 認証中の破棄、拒否イベント、空の一覧、新規作成後の未認証画面。

## DEVIN-05 — 未認証Sessionも明示的に破棄する

**開始状態:** 共通前提。待機中のリクエストなし。

1. Sessions → Dispose Session。
2. No active Session selected、Retained containers 0になること。ログイン操作は不要。
3. StagingでCreate Session。新しいUUID、値0、未認証の画面になること。

**判定:** ログイン状態に依存せずSessionを終了・作成できる。

## DEVIN-06 — 遅延ルートの配送先は受信時のSession

**開始状態:** 共通前提。

1. OS経由で `uicontext-demo://account/preferences` を開く。AにQueued routeが表示されること。
2. Staging Bを作り、Jordanで認証・セットアップ・Enter Appまで進む。
3. BはHomeから始まり、A宛てPreferencesに勝手に遷移しないこと。
4. Aを選び、TaylorでSign In / Complete Sign In / Continue / Finish Setupを進める。Enter App前にはまだPreferencesを表示しないこと。
5. Enter AppでAだけPreferencesに遷移し、保留が消費されること。
6. Bに切り替えると、そのタブ・パスが変わっていないこと。

**判定:** 保留されたUIIntentが後から選択されたSessionへ流れず、認証・準備のゲートを飛び越えない。

**証跡:** Aの保留表示、Bの通常画面、Aの準備完了後のPreferences。

## DEVIN-07 — ルーティングと保持タブの回帰

**開始状態:** 共通前提から認証・セットアップ・Enter Appを完了。

1. Home / Activity / Messages / Accountを順に選択し、各ルートが描画されること。
2. Route Lab → Open Mentions。ActivityのMentionsが選択されること。
3. Route Lab → Open Preferences。Compact AppearanceをONにする。
4. Route Lab → Enter Restricted Mode。Access is pausedがタブの代わりに表示されること。
5. Restore Access。元のPreferencesとONの値が復元されること。
6. OS経由で旧scheme `uimodel-demo://activity/mentions` を開く。互換ルートもMentionsに遷移すること。

**判定:** UIContextの命名やSessionの外側構造が変わっても、タブの保持とUIIntentの配送が壊れていない。

## DEVIN-08 — draftを認証アカウントから初期化し、毎回上書きしない

**開始状態:** 共通前提。

1. Jordanを選んでSign In → Complete Sign In。Create Profileの初期値がJordanであること。
2. 名前をJordan Editedに変更。Sessionsを開閉した後も編集値を保持すること。
3. 同じセットアップ画面のままRoute Lab → Show Announcementを開いて閉じる。親画面の再評価によってJordanに戻らないこと。
4. セットアップを完了する。Accountの認証アカウントはJordanであること。フォームのdraftをアカウントIDとして扱わない。
5. AccountからLog Out & Replace Session。新しいProduction SessionでTaylorを選んでログインする。
6. Create ProfileはTaylorで始まり、Jordan Editedを引き継がないこと。

**判定:** 初期値と編集状態の寿命が適切で、新Sessionへのdraft漏れもない。

**証跡:** Jordan初期値、再評価後の編集値、再生成後のTaylor初期値。

## 範囲外・追加検証の扱い

- 認証はTaylor/Jordanのモックであり、Production/Stagingは実サーバーではない。実認証、資格情報、ディスク永続化・削除、remote revocation、multiwindowはこの仕様の合否対象に含めない。
- 同じ環境での複数Session、Bookmarkの保持、終了プロセスへのcold URL起動、明示的な `?session=<UUID>` 配送は追加検証として扱う。実行しない場合は未検証と明記し、通常の画面切り替えやwarm URL起動で代用しない。
- XCUITestを実行した場合と、Devinが画面を操作した場合の結果は分けて報告する。片方をもう片方の実行済み証拠にしない。

## 実行結果テンプレート

結果はケース定義を書き換えず、実行ごとの報告・PRの検証欄に保存する。

```text
対象commit / PR:
Xcode / Simulator機種 / OS:
実行方式: Devinによる実画面操作（XCUITestの実行は別記）
開始状態の確認:

ケースID | pass / fail / blocked / untested | 期待との差分 | 証跡の位置
DEVIN-01 | ...
...
DEVIN-08 | ...

修正と再実行の範囲:
未実施・対象外:
主要録画: 1本（ケースIDと合否を注釈、スクリーンショットは補助）
```
