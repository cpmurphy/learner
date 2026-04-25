# Chess Learner Hint Feature - Implementation Plan

## Goal
If learner makes three wrong guesses in a row, show a hint button.  If the
user presses the button, show a bubble that reads "Try moving your
<piecename>".  If <piecename> is ambiguous make it not ambiguous. For
example it's a pawn and there is more than one, it should read "Try moving your
<column> pawn".  If it's not a pawn just say "Try moving your <piecename> on
<square>".  After showing the hint button, if the learner makes three more
wrong guesses, show the best move using an arrow on the board.

## Current State Analysis

### Where critical-moment guessing happens

- `public/scripts/main.js` drives all client-side gameplay. The critical-moment
  challenge is entered inside `fetchAndUpdateBoard()` when the server returns a
  `last_move` with `is_critical: true`, `turn === learningSide`, and a
  `good_move_san`. At that point the file sets:
  - `inCriticalMomentChallenge = true`
  - `fenAtCriticalPrompt = lastMoveData.fen_before_move` (position the learner
    must play from)
  - `goodMoveSanForChallenge = lastMoveData.good_move_san` (the expected reply
    in SAN)
  - and calls `board.enableMoveInput(handleCriticalMoveAttempt, learningSide)`
    (main.js:347-429).

- Every user guess flows through `handleCriticalMoveAttempt()` (main.js:49-220).
  It converts the attempted move to SAN with `MoveHelper`, derives the UCI for
  the expected good move, and POSTs both to `/game/validate_critical_move`.
  - Correct guess (`validationData.good_enough === true`): the function enters
    variation mode, saves the continuation to the PGN, and disables move input.
  - Wrong guess: the function sets
    `moveInfoDisplay.textContent = '"<san>" is not the best move. Try again!'`,
    resets the board to `fenAtCriticalPrompt`, and returns `false`. There is
    **no counter** of how many wrong guesses have happened in a row — each
    rejection is independent.

### Backend / data already available

- `/game/validate_critical_move` in `app.rb` (lines 497-529) only tells the
  client whether the move is good enough and, if so, returns a variation. It
  does not need to change for the hint feature; the client already has
  `goodMoveSanForChallenge` and `fenAtCriticalPrompt`, which together are
  enough to derive: the from-square, to-square, and piece type of the best
  move (via `new Chess(fen).move(san, { sloppy: true })` — already used at
  main.js:92-100 to compute `goodMoveUci`).
- `AppHelpers#get_last_move_info` (lib/app_helpers.rb:44-85) is what populates
  `good_move_san`, `fen_before_move`, and the critical-moment flags in the
  `last_move` payload.

### Board rendering / arrows

- The board is a `cm-chessboard` instance (main.js:376). The library ships an
  `Arrows` extension at
  `public/scripts/3rdparty/cm-chessboard/extensions/arrows/Arrows.js` that adds
  `chessboard.addArrow`, `getArrows`, and `removeArrows`. It is **not**
  currently registered — the board is constructed with only `position`,
  `assetsUrl`, `style`, and `orientation` props. To use arrows we have to pass
  an `extensions` array to the `Chessboard` constructor (see cm-chessboard
  docs) and call `chessboard.removeArrows()` when clearing.

### UI / HTML / CSS

- `public/game.html` hosts the board, the `move-info-display` paragraph, and a
  row of icon buttons inside `.controls`. There is no hint button and no
  bubble/tooltip element. The only similar existing UI pattern is
  `#copy-fen-feedback` (a green "Copied!" bubble positioned absolutely inside
  `.copy-fen-container` — style.css:149-173) which we can mirror for the
  hint-text bubble.
- `style.css` currently has no styling for hint-related elements.

### Testing

- Vitest covers JS modules (`test/js/move_helper.test.js`,
  `variation_helper.test.js`). There are no DOM-level tests for `main.js`
  today, so new hint logic should live in a small, unit-testable module (like
  `move_helper.js`) rather than being buried inline in `main.js`.
- Minitest covers Ruby. No backend changes are required, so no new Ruby tests.

### Summary of what's missing for the hint feature

1. A counter of consecutive wrong guesses for the current critical moment,
   reset when the user advances to a new critical moment, makes a correct
   move, loads a new game, changes `learningSide`, or navigates away from the
   prompt.
2. A hint button in the DOM, hidden by default.
3. A bubble element to display the hint text next to / over the board.
4. A function that turns (FEN, good-move SAN) into a human-readable hint
   phrase using the disambiguation rules in the goal.
5. Registration of the cm-chessboard `Arrows` extension and logic to draw /
   remove the best-move arrow after 6 consecutive wrong guesses.

---

## Phased Implementation Plan

### Phase 1 — Hint-text helper (pure, testable)

Create `public/scripts/hint_helper.js` exporting a single function
`bestMoveHint(fen, goodMoveSan)` that returns the sentence to show in the
bubble. Internally:

1. Parse `goodMoveSan` with `chess.js` against `fen` to get `{ from, piece,
   color }`.
2. Map `piece` ∈ `{p,n,b,r,q,k}` to a display name
   (`pawn / knight / bishop / rook / queen / king`).
3. If the piece is a pawn:
   - Count pawns of `color` on the board (scan the FEN's piece-placement
     field).
   - If there is exactly one, return `"Try moving your pawn"`.
   - Otherwise return `"Try moving your <file> pawn"` where `<file>` is
     `from[0]` (the column, a–h).
4. Otherwise return `"Try moving your <piecename> on <from>"` (e.g.
   `"Try moving your knight on f3"`).

Add `test/js/hint_helper.test.js` covering: single pawn, multiple pawns,
knight, bishop, rook, queen, king, and both colors.

### Phase 2 — DOM additions (game.html + style.css)

1. In `game.html`, add inside `.controls` (or immediately after the board) a
   hidden hint button:
   ```html
   <button id="hint-button" class="app-button" style="display:none;">Hint</button>
   ```
   and a hidden hint-bubble container (modeled on `.copy-feedback`) positioned
   near the board:
   ```html
   <div id="hint-bubble" class="hint-bubble" style="display:none;"></div>
   ```
2. In `style.css`, add a `.hint-bubble` rule (rounded, contrasting background,
   short fade-in) and a `.app-button.hint-visible` helper if extra emphasis
   is wanted. Keep the visual language consistent with the existing
   `.copy-feedback` / `.upload-status.info` styles.

### Phase 3 — Register the Arrows extension

In `main.js` where the `Chessboard` is constructed (lines 365-376), import
`Arrows` and `ARROW_TYPE` from
`./3rdparty/cm-chessboard/extensions/arrows/Arrows.js` and pass
`extensions: [{ class: Arrows }]` in the props. Also ensure
`chessboard.removeArrows()` is called when a challenge ends (correct move,
`resumeGameButton`, `set_move_index`, side change, new game load).

### Phase 4 — Wire up wrong-guess state in main.js

1. Introduce two module-scoped counters alongside the other challenge state
   (near main.js:25-41):
   ```js
   let wrongGuessCount = 0;
   let hintShown = false;
   ```
2. Create a helper `resetHintState()` that zeroes both counters, hides the
   hint button, hides the bubble, and calls `board.removeArrows()`.
3. Call `resetHintState()` from:
   - The start of every new critical moment (the `setupChallenge` branch of
     `fetchAndUpdateBoard`).
   - The successful-guess branch of `handleCriticalMoveAttempt`.
   - `resumeGameButton` click handler.
   - `learnSideSelect` change handler.
   - `autoLoadGame` / any `/api/load_game` path.
4. In the wrong-guess branch of `handleCriticalMoveAttempt` (main.js:209-213),
   increment `wrongGuessCount`. Then:
   - If `!hintShown && wrongGuessCount >= 3`: reveal the hint button (set
     `display: inline-flex`).
   - If `hintShown && wrongGuessCount >= 6`: derive `{from, to}` of the good
     move (reuse the `goodMoveObject` computation already present at
     main.js:92-100) and call
     `board.addArrow(ARROW_TYPE.default, from, to)`. Guard so we only add the
     arrow once per challenge.

### Phase 5 — Hint button handler

Add a `document.getElementById('hint-button').addEventListener('click', …)`
handler that:

1. Calls `bestMoveHint(fenAtCriticalPrompt, goodMoveSanForChallenge)` (from
   Phase 1) to build the sentence.
2. Writes it into `#hint-bubble` and makes the bubble visible.
3. Sets `hintShown = true` and resets `wrongGuessCount = 0` so the next three
   wrong guesses trigger the arrow (matches the goal wording: "after showing
   the hint button, if the learner makes three more wrong guesses, show the
   best move").
4. Disables the hint button (we've already given it; the next escalation is
   the arrow).

### Phase 6 — Manual verification

Because `main.js` has no DOM tests, verify the full flow manually with
`PGN_DIR=./test/data bundle exec puma config.ru`:

1. Load a game with a known blunder.
2. Jump to a critical moment; make three wrong guesses of the same type
   (e.g., obviously bad moves) and confirm the hint button appears.
3. Click the hint; confirm the bubble text follows the pawn / piece-on-square
   rules for the test positions (pick one pawn blunder and one piece blunder).
4. Make three more wrong guesses; confirm an arrow is drawn from the correct
   square to the correct square.
5. Play the correct move; confirm the hint button, bubble, and arrow all
   disappear and variation mode starts normally.
6. Re-enter a different critical moment in the same game and confirm state
   is reset (no carryover counter).
7. Run `bundle exec rake test`, `npm test`, and `bundle exec rubocop` — only
   the first and second are expected to exercise new code, and rubocop must
   stay clean per CLAUDE.md.
