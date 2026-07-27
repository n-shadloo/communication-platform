# UI specification — Page-by-Page

> **Repository scope note.** The original specification refers to web, mobile, and
> desktop layout modes. The approved build targets are Android and Web only. In this
> document, “desktop” means the wide browser layout; it does not add Windows, macOS, or
> Linux application targets.
>
> **Backend authority note.** Backend `API.md` contracts take precedence wherever this
> UI specification implies an unavailable endpoint, stronger server guarantee, or
> different limit. Client-only behavior must remain compatible with the backend's blind,
> opaque transport model.

> **Purpose.** This is a **layout and screen-flow specification** for the Flutter client
> (Android + responsive web). It describes **every screen, sub-screen, sheet, dialog, and
> menu**: what each contains, where each element sits, what every button/action does,
> where each action leads, and what states each screen can be in. It is **self-contained**
> — you do not need any other document to lay out and build these screens.
>
> **Scope boundary — read this.**
> - This document specifies **layout structure and screen content**: the arrangement of
>   top bar / body / bottom bar, what components exist, their order, and the navigation
>   between screens.
> - It does **NOT** duplicate visual styling. Colors, typography, spacing, theming,
>   component treatment, and motion are defined by
>   [`visual-design-system.md`](visual-design-system.md).
> - It does **NOT** duplicate cryptographic protocol detail (key exchange, ratchets,
>   key-backup internals). Those rules live in
>   [`cryptographic-protocol.md`](cryptographic-protocol.md) and
>   [`message-protocol.md`](message-protocol.md). Where
>   the UI must respect a privacy or honesty rule, it is stated inline and flagged
>   **[PRIVACY]** — you can build the screen correctly from that flag alone.
>
> **The product in one paragraph.** A private, self-hosted, real-time chat app for a small
> circle of friends. It has exactly **three peer features**: **DMs** (1-on-1 chat),
> **Group chats** (named, invite-only, up to ~50 people, roles), and **Voice rooms**
> (standalone audio rooms with ephemeral text). Flat model — no Discord-style
> server/channel hierarchy. Everything is end-to-end encrypted: the server is a blind
> relay that stores only unreadable ciphertext and can never read messages, names, files,
> or audio. It may run on a self-hosted server inside a country during an internet
> shutdown, so the client uses **no foreign services** — no Google/Apple push, no CDNs, no
> external fonts/JS, no third-party analytics. Telegram is an interaction reference; the
> product's visual identity is defined in [`visual-design-system.md`](visual-design-system.md).

---

## Core rules that shape the whole UI (read once, applies everywhere)

These recur across screens. They are stated here so the individual screens can stay short.

- **The server can never read content.** Messages, files, images, voice audio, and even
  group/room **names, photos, and descriptions** are encrypted on the device before they
  leave it. The UI decrypts them locally for display. Never build a screen that assumes
  the server can provide readable content, search results, or a plaintext name.
- **Presence, typing, and read/delivery receipts are private, encrypted signals.** They
  travel inside the encrypted channel. Accepted tradeoff: they may **lag slightly** vs. a
  normal chat app. Design for a small delay; don't treat them as instant.
- **Search is client-side only.** The server never indexes or helps search. Search covers
  only history stored and decrypted on **this device**.
- **Foreground delivery uses the app's own server; Android background delivery is
  best-effort polling — never Google/Apple push.** Do not offer FCM/APNs-style options.
  Uncollected envelopes expire after seven days; a detected queue gap becomes a visible
  group-rejoin state.
- **Honesty over false comfort.** Several actions are **best-effort, not guarantees**, and
  the UI must say so plainly (detailed at each spot): *Delete for everyone*, voice-room
  *ephemeral* text, and history recovery. Never word a dialog to imply a stronger promise
  than the system can keep.
- **Two separate secrets, never conflated.** A **login password** authenticates to the
  server; a **recovery secret** protects cross-signing private identity material. Neither
  recovers message history from the server because the server stores none.
- **Verification precedes messaging.** SAS/QR verifies a contact's master key out of
  band. Until verified, Message/Invite actions are blocked. Unsigned devices, master-key
  changes, and device-log forks are blocking security states.

---

## 0. Global Layout & Navigation Model

### 0.1 Adaptive shell
One adaptive shell that changes structure by viewport width.

- **Mobile (narrow):** a **bottom tab bar** with three tabs: **Chats**, **Voice Rooms**,
  **Settings**. Each tab is a full-screen stack; tapping a list item pushes a detail
  screen; back gesture/button pops it.
- **Desktop / web (wide):** a **two-pane layout**. A **left rail** holds the same three
  destinations plus the list for the selected one; the **right pane** shows the open
  conversation/room/detail. Selecting a list item swaps the right pane in place.
- **Tablet / medium:** two panes when wide enough, otherwise mobile behavior.

The destination set is identical across form factors; only the container differs.

### 0.2 Persistent elements
- **Active voice-room banner.** Whenever the user is joined to a voice room, a thin
  persistent banner sits above the bottom tab bar (mobile) or atop the left rail
  (desktop): room name, a live mic-state icon, and a "return to room" tap target. It stays
  on every screen until the user leaves the room; tapping it opens the Live Voice Room
  (§10).
- **Connection status strip.** When the client can't reach the server, a strip appears at
  the top of the current screen: "Connecting…" / "No connection to server". It clears only
  when the connection returns, not by user dismissal.

### 0.3 Global "new" affordance
- **Mobile:** a floating compose button (FAB) on the Chats and Voice Rooms lists; its
  action depends on the active tab (§7.3 recap).
- **Desktop:** a compose "+" at the top of the left rail's list header.

---

## 1. Splash / Connection Screen

**Purpose.** First screen on launch. Decides whether the app has a stored identity, whether
it can reach the server, and where to route. Also loads the pre-installed server-trust
setup the app was provisioned with.

**Layout.**
- Centered app name/logo placeholder (you supply the mark).
- A status line reflecting boot state.
- No top bar, no bottom bar — a standalone gate.

**Boot logic & routing.**
- Stored identity + reachable server → **Chats** (§6), already signed in.
- Stored identity + expired credential → **Login** (§2), username pre-filled.
- No stored identity → **Login** (§2) with a Register path.
- Server unreachable with no usable local identity → stay here in the unreachable state.
- Server unreachable with a usable Android identity → open cached Chats in offline mode;
  queued sends wait for reconnection. The online-session-first Web client stays on the
  unreachable state until its configured server returns.

**States.**
- *Loading* — "Starting…" while local keys/trust load.
- *Reachable* — brief; auto-advances.
- *Unreachable* — "Can't reach the server" + **Retry**. **[PRIVACY]** No detail beyond
  reachable/unreachable; the app never pings any foreign service to test connectivity.
- *Not provisioned* — if the app was never set up with its server-trust config, show a
  blocking message that it must be installed from a trusted source, with no bypass.

---

## 2. Login Screen

**Purpose.** Sign an existing user in with username + password.

**Layout (top → bottom).**
1. Back/close only if reached from deeper; otherwise none.
2. App name/logo placeholder.
3. **Username** field.
4. **Password** field with show/hide toggle.
5. **Log In** primary button.
6. **Create account** link → Register (§3).
7. Footer link **"Security & how this app protects you"** → Security Notice (§5), viewable
   before login.

**Actions.**
- **Log In** → on success, if this device has no encryption identity yet, go to Encryption
  Setup (§4); otherwise go to Chats (§6).
- **Create account** → Register (§3).

**States.**
- *Idle* — Log In disabled until both fields filled.
- *Submitting* — busy button, fields locked.
- *Invalid credentials* — generic inline error ("Username or password is incorrect").
  **[PRIVACY]** No hint which field was wrong or whether the username exists.
- *Account inactive* — distinct message: the account exists but the owner hasn't activated
  it yet (see §3's Pending-Activation).
- *Server unreachable* — banner; Log In disabled.

**[PRIVACY]** The password only signs the user in; it never protects or recovers message
content. Nothing here should imply otherwise.

---

## 3. Register Screen (+ Pending-Activation state)

**Purpose.** Create a new account with minimal personal info — **username + password
only**.

**Layout (top → bottom).**
1. Back → Login.
2. Title "Create account".
3. **Username** field (inline format validation). Availability is checked only when the
   registration request is submitted because the backend exposes no availability probe.
4. **Password** field with show/hide + strength hint.
5. **Confirm password** field.
6. **Create account** primary button.
7. Footer link to Security Notice (§5).

**Actions.**
- **Create account** → account is created **inactive** (the owner must manually approve
  new accounts before they can be used). Route to **Pending-Activation** (below).

**Pending-Activation screen.**
- **Purpose.** Tell the user the account exists but is waiting for the owner to activate
  it.
- **Layout.** Centered text ("Your account is waiting for the owner to activate it"), a
  **Check again** button, a **Back to login** link. Check Again returns to Login with the
  username prefilled and asks for the password again; the pending screen does not retain
  the password or call a nonexistent activation-status endpoint.
- **States.** *Still pending* (unchanged on re-check) / *Now active* (route to Login §2 or
  into Encryption Setup §4).

**States (Register form).**
- *Idle / validating / submitting*.
- *Username taken* — inline error.
- *Passwords don't match* — inline error under Confirm.
- *Server unreachable* — banner; submit disabled.

---

## 4. Encryption Setup (First Run on a Device)

**Purpose.** The first installation creates account cross-signing keys plus independent
X25519 and ML-KEM-768 device material. MLS device material is created only after the
[PQ MLS production gates](mls-profile.md#production-gates) pass. A new account creates a
recovery-protected identity backup; an existing account restores that identity material.
Message history is a later transfer from an existing online device, not part of the
backup.

**Enrollment order.** Register the new device without `cross_sig`/`bundle_version`, then
use the returned device ID and full-scope tokens to finish cross-signing through the
prekey endpoint. For an existing account, retrieve and unwrap the identity backup only
after that response. While this second phase is pending, show "Finishing secure device
setup", support safe retry/resume, and withhold messaging; never offer an unsigned or
placeholder-key bypass.

### 4.1 Step — Generating identity
- **Layout.** Centered status ("Setting up encryption on this device") + progress
  indicator.
- **Behavior.** Device-private keys remain on this device. Cross-signing private keys may
  leave only inside the recovery-encrypted backup. Auto-advances when secure enrollment
  is possible; no user action.

### 4.2 Step — Recovery

**New-account branch — Your recovery secret.** Show the newly generated recovery secret
**once** and make the user save it.
- **Layout (top → bottom).**
  1. Title "Your recovery secret".
  2. Explanation: this restores the account's cross-signing identity if devices are
     lost. It does **not** restore messages; losing every device that holds history makes
     that history permanently unavailable because the server has no copy.
  3. The recovery secret in a clearly presented block.
  4. **Copy** button and, where the platform allows, **Download / Save**.
  5. **Continue** — disabled until the user copies/downloads or ticks an "I've saved it"
     checkbox.
- **[PRIVACY]** This recovery secret is **separate from the login password**, and the
  server never sees it. State that plainly on-screen.

**Existing-account branch — Restore identity.** Ask for the recovery secret, download
the opaque key backup, and decrypt cross-signing identity locally. Show wrong-secret,
restoring, and Retry states. History remains a separate online-device transfer.

### 4.3 Step — Confirm or restore
- **New-account purpose.** Stop users skipping the save.
- **Layout.** Either re-enter part of the secret, or an explicit "Yes, I've stored my
  recovery secret somewhere safe" checkbox + **Confirm**, plus a **Back** link to view it
  again during this onboarding flow only.
- **Existing-account purpose.** Show authenticated identity-restore progress and
  completion; never display or persist the entered recovery secret after the backup is
  unwrapped.

### 4.4 Step — Security notice handoff
- On completing setup, route into the **Security Notice** (§5) as a mandatory full-screen
  step before entering the app.

**States across the flow.** Standard loading/error. If uploading the user's public setup
fails (server unreachable), the flow **blocks with a retry** and never proceeds as if setup
succeeded.

---

## 5. Security Notice (Honest Safety Boundary)

**Purpose.** Tell the user plainly what the app does and does not protect. **This screen is
required and must be shown** — it is not optional marketing, and its "does NOT protect"
section must not be softened or omitted.

**When shown.**
- As a **mandatory full-screen step** at the end of first-run onboarding (§4.4), with an
  explicit acknowledge action to proceed.
- **Re-viewable anytime** from Settings (§15) and from the pre-login footer links (§2, §3).

**Layout (top → bottom).**
1. Title, e.g. "What this app protects — and what it doesn't".
2. **What it DOES protect** — the content of messages, files, and voice audio is
   unreadable to the server, to anyone watching the network, and to anyone who seizes the
   server.
3. **What it does NOT protect** — stated plainly:
   - the **fact and timing** that a device connected to the server (a network operator can
     see *that* you connected, and when, even though not *what* you said);
   - **traffic-analysis metadata** — timing, IP addresses, connection patterns;
   - the **social graph from a live hostile server operator** — the operator can observe
     which authenticated connection writes to which device queues and infer group fan-out;
   - first contact before users compare SAS/QR master-key fingerprints out of band;
   - a **compromised or seized device** — encryption can't protect messages already
     decrypted on a phone in someone else's hands.
   Wording must not imply the app makes communication "safe from the government"; it makes
   **content** unreadable — the rest is the user's informed risk.
4. In onboarding: an **"I understand"** button (required to proceed). From Settings: a
   plain **Close/Back**.

---

## 6. Chats List (Home / Chats tab)

**Purpose.** Telegram-style unified list of all DMs and group chats, plus any active voice
rooms pinned at top. The primary hub.

**Layout.**
- **Top bar:** left — title "Chats" (or an avatar/menu affordance opening Settings on
  mobile); center/right — a **search** entry point and, on desktop, the compose "+".
- **Search:** tapping the search entry opens Search (§6.5).
- **Body:** scrollable list. Order: pinned items first (including active voice rooms and
  pinned conversations), then the rest by most recent activity.
- **Bottom (mobile):** the tab bar (Chats / Voice Rooms / Settings) + FAB.
- **Active voice-room banner** (§0.2) sits above the tab bar when applicable.

**Each conversation item shows:**
- Avatar (contact photo for DMs; group photo for groups — decrypted locally).
- Title (contact/group name — decrypted locally).
- Last-message preview (decrypted locally).
- Timestamp of last activity.
- Unread count badge.
- Mute icon if muted.
- Pin marker if pinned.
- Optional delivery/read state on the last outgoing message.

**Item interactions.**
- **Tap** → DM (§8) or Group (§9) chat screen.
- **Long-press (mobile) / right-click (desktop)** → context menu: **Pin/Unpin**,
  **Mute/Unmute** (opens mute options §17), **Mark as read/unread**, **Delete chat**
  (→ confirm; for DMs this clears the conversation locally — honest wording).

**FAB / compose (§0.3)** → **Contacts / New** (§7).

**States.**
- *Loading* — skeleton list while the local store loads and the connection comes up.
- *Empty* — friendly empty state with "Start a chat" → Contacts (§7).
- *Offline* — connection strip at top; cached conversations still show and are fully
  readable (content is stored and decrypted locally). New sends queue (§8 states).

### 6.5 Search (client-side only)
**Purpose.** Search the user's own chats. **[PRIVACY] The server never indexes or assists —
search covers only history stored and decrypted on this device.**

- **Layout.** Search input at top; results grouped into **Chats** (matching titles),
  **Messages** (matching text in the local store), optionally **Contacts**.
- **Interactions.** Tapping a message result opens that chat scrolled to the message;
  tapping a chat/contact opens it.
- **States.** Empty query, no results, and a note that search covers only this device's
  stored history.

---

## 7. Contacts / New Chat

**Purpose.** Start a DM, create a group, or create a voice room. Reached via compose
(§0.3) or the empty-state CTA.

**Layout.**
- **Top bar:** back/close; title "New".
- **Action rows at top:** **New Group** → Create Group (§12.1); **New Voice Room** →
  Create Voice Room (§13.1).
- **Contacts list:** the users this client knows about. Each row shows the authenticated
  profile avatar/display name when available. Before a profile key is received, it shows
  the backend username and a locally generated placeholder avatar, plus no verified-key
  indicator. A verified indicator appears only after the safety number (§11.1) is
  verified; unverified cached profile content never replaces the fallback.

**Interactions.**
- **Tap a contact** → open/create a DM (§8).
- **Search field** filters by name.

**States.** *Loading*, *empty* (no other users known yet), *offline* (cached contacts).

### 7.3 Compose behavior recap (tab-dependent "+")
- On **Chats**, compose opens **Contacts / New** (§7) → DM, or branch into New Group /
  New Voice Room.
- On **Voice Rooms**, compose opens **Create Voice Room** (§13.1) directly.

---

## 8. DM Chat Screen

**Purpose.** 1-on-1 encrypted text conversation with the full chat experience.

**Layout (top → bottom).**
1. **Top bar:**
   - Left: back (mobile).
   - Center: contact avatar + name + a presence/last-seen line (**[PRIVACY]** encrypted,
     volatile signal; may lag).
   - Tapping name/avatar → **Contact Profile** (§11).
   - Right: overflow (**⋮**) → **Search in chat**, **Mute** (§17), **Verify safety number**
     (§11.1), **Clear history** (→ confirm, honest wording), **Block/Unblock**.
2. **Message list (body):** scrollable oldest→newest, sticky date separators.
   - **Message bubble:** text (decrypted locally), timestamp, outgoing delivery/read state,
     an **edited** marker if edited, a reply-quote block if it's a reply, reaction chips
     beneath, a star marker if starred.
   - **Pinned banner** atop the list if any message is pinned; tap to jump; expand → all
     pinned messages (§8.3).
3. **Input bar (bottom):**
   - **Attachment** button → attachment sheet (§8.2).
   - Text input (multiline, grows).
   - **Emoji** access.
   - **Send** (appears when text present).
   - When replying/editing, a **context strip** above the input shows the quoted/edited
     message with a cancel (×).

**Message interactions (long-press / right-click → context menu):**
- **Reply** — sets the reply strip.
- **React** — emoji reactor; **[PRIVACY]** reaction is encrypted, server never sees the
  emoji.
- **Edit** (own messages) — loads the message into the input with an edit strip.
- **Forward** — Forward target picker (§8.4).
- **Copy** — local clipboard.
- **Star/Unstar** — client-side flag.
- **Pin/Unpin**.
- **Delete** → **Delete dialog** with two clearly labeled options: **Delete for me** (local
  only) and **Delete for everyone** (**best-effort**). **[PRIVACY]** The dialog must state
  honestly that *Delete for everyone* cannot force other devices to forget content they've
  already received and decrypted.

**States.**
- *Loading* — history loads locally; older messages page in on scroll-up.
- *Empty* — new-conversation placeholder.
- *Sending / queued* — pending state; **offline** sends queue locally and flush on the
  next active connection or background poll; there is no foreign push.
- *Failed send* — retry affordance on the message.
- *Offline* — connection strip; existing history fully readable; composing allowed, sends
  queued.

### 8.2 Attachment sheet
- Options: **Photo/Image**, **File**, and camera on mobile. Picking shows a **preview +
  caption** step with send/cancel. **[PRIVACY]** Files/images are encrypted on the device
  before upload; the server stores only ciphertext.

### 8.3 Pinned messages screen
- All pinned messages in the conversation. Each row: preview + jump-to + **Unpin**.

### 8.4 Forward target picker
- **Purpose.** Choose where to forward a message. **[PRIVACY]** Forwarding re-encrypts the
  message for the new recipients — it is not a server-side copy.
- **Layout.** Searchable list of DMs and groups (and Saved Messages). Multi-select; a
  **Forward** confirm button.

---

## 9. Group Chat Screen

**Purpose.** Named, invite-only encrypted group chat, full chat experience. Persistent
history; up to ~50 members; roles **owner → admins → members**.

**Layout.** Same skeleton as the DM screen (§8), with group differences:
1. **Top bar:**
   - Center: group photo + name + a subtitle with member count / a few names (decrypted
     locally).
   - Tapping title/photo → **Group Info** (§12.2).
   - Overflow (**⋮**): **Search in chat**, **Mute**, **Group info**, **Leave group**
     (→ confirm), and admin/owner-only entries here or in Group Info (**Add members**,
     **Edit group**).
2. **Message list:** as §8, but incoming bubbles also show the **sender's name/avatar**.
   Inline system lines appear for membership changes ("X was added", "Y left").
3. **Input bar:** as §8. By default all members can post; if you implement any
   posting restriction, disabled states must explain why.

**Message interactions:** identical to §8 (reply, react, edit own, forward, copy, star,
pin, delete-for-me / delete-for-everyone). A pin is visible to all members via the pinned
banner.

**Role-gated actions** (owner/admins only): appear on member rows within Group Info
(§12.2), not on individual messages.

**States.** As §8, plus: *membership updating*; *removed* (read-only/exited, with no access
to future epochs); and *queue gap — rejoin required*. The queue-gap state disables the
composer until peers remove and re-add this device with a fresh Welcome.

---

## 10. Live Voice Room Screen

**Purpose.** The active audio session for a **standalone, persistent, audio-only** voice
room with an **ephemeral** alongside text chat. All members are equal peers — no admin
hierarchy.

**Layout (top → bottom).**
1. **Top bar:** room name; a **participant count**; a **Room info** affordance (§13.2); a
   **minimize** control that collapses to the persistent banner (§0.2) while keeping the
   user in the room.
2. **Participants area (main):** tiles for each participant — avatar + name + a **live
   speaking/mic indicator** (speaking, muted). **[PRIVACY]** Audio is end-to-end
   encrypted; the media server forwards it without being able to listen.
3. **Ephemeral text chat panel** (a toggle/tab on mobile, a side panel on desktop):
   messages here **disappear when the room empties** and are not stored on the server. The
   panel must plainly indicate it's ephemeral. Simplified input (text + send); no
   persistent features like pin/star here.
4. **Bottom control bar:** **Mute/Unmute** self, **Speaker/output** where applicable,
   **Invite** (§13.3), **Leave** (leaves the session; the room persists and can be rejoined
   later).

**Interactions.**
- Tapping a participant tile → a small sheet with their name and, if not yet verified, a
  link to verify their safety number (§11.1).
- **Leave** returns to the previous screen; the persistent banner disappears.

**States.**
- *Connecting* — establishing the session; connecting indicators on tiles.
- *Connected* — normal.
- *Reconnecting* — a network blip; audio drops with a reconnecting indicator; the text
  panel shows its volatile state.
- *Empty room (you're alone)* — a single-tile state inviting others.
- *Room ended / everyone left* — ephemeral text is dropped; next open shows the room empty
  and rejoinable.
- *Offline / can't reach the server* — an honest error; no foreign fallback is attempted.

---

## 11. Contact Profile (+ Safety-Number Verification)

**Purpose.** View a contact, control per-contact settings, and verify their identity key.

**Layout (top → bottom).**
1. **Top bar:** back; overflow if needed.
2. **Header:** large avatar, display name, presence/last-seen line (encrypted, volatile).
3. **Action rows:**
   - **Message** → DM (§8).
   - **Mute** → mute options (§17).
   - **Verify safety number** → Safety Number screen (§11.1).
   - **Shared media/files** → a media grid from this DM, decrypted locally (§11.2).
   - **Clear history** → confirm, honest wording.
   - **Block/Unblock** → confirm. Blocking is private client state synchronized only to
     the user's own devices. It suppresses display, receipts, presence, typing, and
     notifications from the contact, but cannot prevent the sender from submitting
     ciphertext to the backend; the client still safely drains and acknowledges it.

### 11.1 Safety Number screen
- **Purpose.** Compare a contact's key fingerprint to make sure no one — not even a
  malicious server — is impersonating them or intercepting messages.
- **Layout.** SAS emoji/number text derived from both users' exact master keys, a QR code
  containing the master-key fingerprint, a **Confirm verified** action, and instructions
  to compare in person or over another trusted channel. Confirmation cross-signs the
  peer's exact master-key bytes with the user's user-signing key.
- **States.** *Unverified — messaging withheld*, *verified*, **master key changed**,
  **unsigned/invalid device**, and **device-log fork**. The latter states block sending;
  they are not dismissible warnings or automatic TOFU resets.

### 11.2 Shared media screen
- A grid of images/files from the conversation, decrypted locally, with tap-to-open and
  jump-to-message.

---

## 12. Groups — Create & Info

### 12.1 Create Group flow
Reached from Contacts (§7). Multi-step:
1. **Pick members** — searchable contact list, multi-select, **Next**. (~50 cap guidance.)
2. **Group details** — set **name**, **photo**, optional **description**. **[PRIVACY]** All
   three are encrypted; the server stores only ciphertext.
3. **Create** — the creator becomes **owner**; opens the Group chat (§9).
- **States.** validating name, creating, error/offline.

### 12.2 Group Info screen
**Purpose.** View/manage a group. Some controls are visible only to owner/admins.

**Layout (top → bottom).**
1. **Top bar:** back; an **Edit** affordance for owner/admins → §12.3.
2. **Header:** group photo, name, description, member count.
3. **Quick actions:** **Mute**, **Search in chat**, **Shared media** (grid like §11.2).
4. **Members section:** each row — avatar, name, a **role tag** (owner/admin/member), a
   verified-key indicator if verified.
   - **Tap a member** → sheet with **Message** (DM), **Verify safety number** (§11.1), and
     **owner/admin-only**: **Remove from group** (→ confirm). **[PRIVACY]** Removing a
     member cuts off their access to future messages.
   - **Add members** (visible per the group's invite policy) → member picker (like §12.1
     step 1).
5. **Leave group** (all members) → confirm.

### 12.3 Edit Group screen (owner/admin)
**Purpose.** Edit group identity and settings. These are owner/admin powers.

**Controls.**
- **Group name** field (encrypted).
- **Group photo** picker (encrypted).
- **Description** field (encrypted).
- **Invite policy** — **the owner sets who may add new members** (present as a selectable
  policy; you'll implement the exact options the backend supports).
- **History for new members** toggle — an **owner, per-group** setting, **default = show
  past history**. Include an honest note: when on, an existing member's device **re-shares
  the backlog** to the newcomer (the server can't, since it only holds ciphertext the
  newcomer can't read), and this is an intentional, accepted tradeoff.
- **Save** / **Cancel**.
- **States.** saving, error, permission-denied (if the user's role changed underneath).

---

## 13. Voice Rooms — List, Create & Info

### 13.0 Voice Rooms list (Voice Rooms tab)
- **Layout.** A list of the user's voice rooms. Each row: room name (decrypted locally) and
  a state line (**Live now** with participant count / **Empty**). Any room the user is
  currently in also drives the persistent banner (§0.2).
- **Interactions.** Tap → Voice Room Info (§13.2) or straight into the Live Room (§10) if
  already live — your call which; be consistent. Compose (§7.3) → Create Voice Room.
- **States.** loading, empty ("No voice rooms yet"), offline (cached list).

### 13.1 Create Voice Room flow
Reached from Contacts (§7) or the Voice Rooms tab compose. Multi-step:
1. **Room details** — set **room name** (encrypted). Voice rooms are standalone, not tied
   to any DM or group.
2. **Invite members** — searchable contact multi-select (all invited are equal peers).
3. **Create** — creates the persistent room and opens it (or its info card).

### 13.2 Voice Room Info screen
**Purpose.** View/manage a room outside the live session.

**Layout (top → bottom).**
1. **Top bar:** back; **Edit** (rename / manage invites — no admin gating, all peers).
2. **Header:** room name; a state line (**Live now** + count / **Empty**).
3. **Primary action:** **Join** (→ Live Voice Room §10), or **Rejoin** if empty (the room
   is persistent and outlives everyone leaving).
4. **Members/invited list:** each row — avatar + name; an **Invite** action → picker
   (§13.3). No role tags (all peers).
5. **Leave room / remove yourself** as applicable. Confirmation explains that this
   removes local membership, keys, capability, and live access after notifying peers; it
   does not delete the persistent backend room or revoke copies of its capability held by
   others. Returning requires a fresh authenticated invite.

**[PRIVACY]** Room name is encrypted; the server stores ciphertext. The alongside text
chat exists only during a live session and is dropped when the room empties.

### 13.3 Voice Room invite picker
- Searchable contact multi-select + **Invite** confirm. Adds peers to the room.

---

## 14. Saved Messages

**Purpose.** A personal self-conversation to save/keep your own messages, encrypted to your
own device keys.

**Layout.** Same skeleton as the DM chat (§8), with the "contact" being the user
themselves. Supports the features that make sense solo: send text/files, star, pin, search,
forward (into other chats), delete-for-me. No receipts/presence (no other participant).

**Access.** From Settings (§15) and as a target in the Forward picker (§8.4). May also
appear pinned in the Chats list.

---

## 15. Settings (Settings tab / home)

**Purpose.** Account, security, devices, and app preferences hub.

**Layout (top → bottom list):**
1. **Profile header** — the user's avatar + display name; tap → **Edit profile** (§15.1).
2. **Saved Messages** → §14.
3. **Linked Devices** → §16.
4. **Security & recovery** → Security settings (§15.2).
5. **Notifications** — global notification/mute preferences (a client-side preference).
   **[PRIVACY]** Active-app delivery uses the self-hosted connection and Android
   background delivery is best-effort polling, **not** Google/Apple push. Do not offer
   push-service or always-instant options.
6. **Appearance** — client-only display preferences (the option *set* is your call; no
   styling prescribed here).
7. **Security notice** — re-open the honest boundary screen (§5).
8. **Log out** → confirm. **[PRIVACY]** The confirm clearly states whether local
   history/keys are wiped. The recovery secret can recover cross-signing identity, not
   messages; history returns only from another device that still has it.
9. **About** — app/version info (all local; no external calls).

### 15.1 Edit Profile
- Set display name and avatar. State clearly what is visible to contacts. (Keep personal
  info minimal.)

### 15.2 Security settings
- **Recovery secret** — replacement guidance; an already-saved secret is never re-shown
  because the app does not retain it. An unlocked device may generate a fresh secret,
  rewrap the same cross-signing identity material, upload a higher backup version, show
  the new secret once, and invalidate the old secret. Honest note: the server holds only
  an **unreadable identity backup** and no message history.
- **Safety numbers** — a shortcut to review verified contacts (§11.1).
- **Security notice** link (§5).

---

## 16. Linked Devices

**Purpose.** Manage the user's Android device and browser profiles. Devices are
independently keyed but cross-signed by the account identity. Add a device, authorize it,
and optionally transfer locally held history.

**Layout (top → bottom).**
1. **Top bar:** back; title "Linked Devices".
2. **This device** row — current device, marked.
3. **Other devices** list — each row: device label, last-active (as available), and
   **Remove device** (→ confirm). Removing revokes it.
4. **Add device** → Add Device flow (§16.1).

### 16.1 Add Device flow
- **Purpose.** Bring a new device online, recover/cross-sign identity, then optionally
  transfer encrypted history from an existing online device.
- **Steps.**
  1. On the **new** device, login and enter Encryption Setup (§4).
  2. After unsigned registration returns full-scope tokens, restore cross-signing
     identity using the recovery secret and finish the device cross-signature through
     the prekey endpoint.
  3. Establish fresh hybrid sessions; peers remove/re-add the device to groups for fresh
     Welcomes where required.
  4. Ask an existing online device to send its locally held history through ordinary
     encrypted envelopes. Show the source device and whether its history is partial.
- **States.** *registering device*, *awaiting secret*, *restoring identity*, *wrong
  secret*, *finishing secure setup*, *identity recovered*, *waiting for existing
  device*, *transferring history*, *no history source online*, *group re-invitation
  required*, *queue gap recovery*, and *done*. **[PRIVACY]** The server supplies no
  ciphertext history and the recovery secret cannot reconstruct it.

---

## 17. Global Dialogs, Sheets & Menus (referenced above)

The recurring modal surfaces and their contents:

- **Delete message dialog** (§8) — two labeled options, *Delete for me* / *Delete for
  everyone*, with the honest note that "for everyone" is best-effort.
- **Confirm dialogs** — Leave group, Remove member, Remove device, Clear history, Log out:
  each states the consequence plainly, including irreversibility where true.
- **Mute options sheet** — durations / until toggled.
- **Emoji reactor** — for reactions.
- **Attachment sheet** (§8.2).
- **Context menus** — message long-press menu (§8/§9) and conversation-list item menu (§6).
- **Forward target picker** (§8.4).
- **Member/participant sheets** — group member sheet (§12.2), voice participant sheet
  (§10).

Every dialog that performs an irreversible or best-effort action must carry honest wording
— no dialog may imply a stronger guarantee than the app can keep.

---

## Appendix A — Screen Inventory (flat list)

1. Splash / Connection (§1)
2. Login (§2)
3. Register (§3)
4. Pending-Activation (§3)
5. Encryption Setup — Generating (§4.1)
6. Encryption Setup — Recovery (§4.2)
7. Encryption Setup — Confirm or restore (§4.3)
8. Security Notice (§5)
9. Chats List (§6)
10. Search (§6.5)
11. Contacts / New (§7)
12. DM Chat (§8)
13. Attachment sheet (§8.2)
14. Pinned messages (§8.3)
15. Forward target picker (§8.4)
16. Group Chat (§9)
17. Live Voice Room (§10)
18. Contact Profile (§11)
19. Safety Number (§11.1)
20. Shared media (§11.2)
21. Create Group (§12.1)
22. Group Info (§12.2)
23. Edit Group (§12.3)
24. Voice Rooms list (§13.0)
25. Create Voice Room (§13.1)
26. Voice Room Info (§13.2)
27. Voice Room invite picker (§13.3)
28. Saved Messages (§14)
29. Settings home (§15)
30. Edit Profile (§15.1)
31. Security settings (§15.2)
32. Linked Devices (§16)
33. Add Device (§16.1)
34. Global dialogs/sheets/menus (§17)
