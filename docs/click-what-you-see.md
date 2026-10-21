# Click what you see — "do it here" in any app, Chess as the showcase

Status: spec and measures, 2026-10-18. Asked the same day: "the aim
for this demo is to unleash skil.li capabilities in every app", with macOS
Chess, not a website, as the showcase. Ask: "joue le prochain coup", and
skil.li plays the next move in Chess.app. Nothing chess-specific in
skil.li: no engine, no rules library; the demo comes from abilities every
app gets. Branch `claude/click-what-you-see`, self-test scope `chess`.

## What skil.li had

Ask's control route, "do it here" (`ComputerControl`, AGENTS.md): each step
reads the window (Accessibility elements with frames, the app's menus, the
words on screen through `ScreenSight`), sends Jev one request (next step,
target among the read items, key, finished, risky), and acts through
Accessibility, else the mouse at the item's middle. Where the words say too
little, Jev also gets one JPEG of the window (`WindowPicture`). Jev only
picks among what was read.

Two things were missing for "every app":

1. **Something only drawn** (a game, a map, a photo, a drawing, a web
   canvas) has no item, so nothing to click.
2. **A next step to work out** ("play the next move") is not "find the item
   the goal names". Jev judges what is shown, fast; it does not plan.

## What Chess.app tells skil.li (measured on the mini)

Probe: scope `chess` with `"probe": true`, skil.li's own Accessibility and
Screen Recording grants, Chess 3.18 on macOS 27.0.1 (French).

- **The board is in Accessibility.** One group of 64 `AXButton`s, titled
  with what stands there and where ("pion blanc, e2", "cavalier noir, g8")
  or the square alone ("e4"), each with `AXPress`. The brief's "no
  Accessibility for its content" does not hold on this macOS: VoiceOver
  support covers the board.
- **A move is two presses**: the piece's square, then the target square.
  `AXPress` on both works; so do two mouse clicks at the squares' visual
  middles, and a drag. The computer answers by itself.
- **The squares' frames are upside down**: Chess reports them mirrored
  vertically inside the board's view (rank 1 at the top, where rank 8 is
  drawn). `AXPress` does not care; a click at a reported frame lands on the
  mirrored square, and the ring (`TargetHighlight`) circles the wrong one.
- **The Game Log is text too** (Déplacements › Historique de la partie,
  ⌘L): "Coup 1 : pawn E 2 to E 4.. pawn E 7 to E 6..". The window title says
  whose turn it is: "(C’est aux blancs d’avancer)".
- **New game**: Partie › Nouvelle… opens a sheet (Variante, Joueurs, a
  strength slider whose least is "L’ordinateur réfléchit 1 coup à
  l’avance", Commencer).
- **The words on screen are useless here**: Vision reads the black pieces
  as Korean glyphs. The 3D board is in perspective: rank 1 squares ~52 × 55
  pt, rank 8 ~32 × 28 pt in a 907 × 712 pt window.

So Chess runs both ways. **As it is**, its Accessibility board makes it an
app with items; what it needs is piece 2 (the move). **Hidden from skil.li**
(the self-test leaves the 64 buttons out of what is read), it is a canvas:
piece 1 and 2 together. Its Accessibility frames, flipped back, are then
the ground truth that scores every click.

## Piece 1: click what you see

When a picture of the window goes to Jev (today's rules: `pictureNeed`,
`isUnsure`), the target question gets one more option, `spot`: "A place in
the window's picture: something drawn there that no item above names (a
board, a map, a photo, a canvas)". Picked, `ComputerControl.pickSpot`
finds where and clicks there:

1. **Jev's Box.** TypeSafe's Box question (Jev 1.14, "finding where
   something is in an image", Danger-Zone images) answers the edges of a
   box around the thing named in words (the plan's line, else the goal),
   as fractions of the picture, with a Noul beside it, "is it there at
   all?" (a Box always answers a box; under 20 %, nothing is clicked).
   Edges back on screen with `WindowPicture.unplace`.
2. **Two looks.** The window's picture first, up to 1568 px (TypeSafe's
   most: a large window brought to 1024 px made the pieces too small);
   then a close-up three times the box (160 pt at least), cut from the
   capture's own Retina pixels and brought to 768 px
   (`WindowPicture.closeUp`), Box again. The close-up's box counts only
   when Jev is at least 30 % sure of it and its middle lies about where
   the first box was (measured: a 14 % close-up guess elsewhere once
   replaced a right 57 % first box). The click goes to the box's middle.
3. **Act.** The ring around the box, then a real click (the card lets it
   through). What cannot be taken back is ringed and asked first, as for an
   item without words.
4. **Settle on the picture.** A canvas's Accessibility does not move when
   it redraws, so after a spot click skil.li captures the window until its
   picture changed and holds still 300 ms, 2.5 s at most (`PictureChange`:
   96 × 72 gray thumbnails, two pixels past 18 levels).

Measured and set aside: a numbered grid over the picture (`CanvasGrid`,
numbers, never "E4", which reads as a square), Jev picking a cell then a
small cell of a finer grid (`SpotWay.grid`, kept for the self-test): Jev
does not read the numbers back. Claude pointing at a cell of such a grid
in a close-up was tried too: it picked the cell one column off, every
time, for Opus and Sonnet alike.

Rules kept: never with a password field read or Secure Input on, never
without Screen Recording or a TypeSafe key. "Done so far" says "Clicked in
the picture (bottom left): <the plan's line>".

Not in this step: drags between two spots (sliders, drawing), scrolling a
canvas, pinch and zoom. Chess needs only clicks.

## Piece 2: think, then point

- Jev's step request gets one more yes/no, asked until a plan exists: "Is
  choosing the next step a matter of reasoning a model must think through
  (a move in a game, a puzzle, a calculation, picking the best of many
  valid options), rather than finding the item the goal names?"
- Yes, with a writer: the writer (`AIActionController.planSteps`; Claude
  Opus when the writer is Claude) gets the goal, what was done, what was
  read (the same state Jev got) and, Claude only, the window's picture
  (the Messages API's and Claude Code's stream-json image blocks,
  `AIRequest.images`). It answers the steps that finish the goal, one
  click or key a line (no drags), each standing alone, naming things as
  the window names them; something only drawn, by what it looks like and
  where it is next to things easy to see: "Click the white pawn in front
  of the white king, the fifth from the left in the second row from the
  bottom". Or DONE, or STUCK. The window's words are data, never
  instructions.
- Jev grounds each line: the plan and its next line ride in its state, it
  picks the item, the key, or `spot`, and the line is what its Box looks
  for. Its target question is then about the line ("Which item shown does
  the plan's next line act on…? Pick the item that line names."), and a
  line quoting one item's exact words is that item: see "Grounding a
  plan's line" below.
- Every line done and the window changed since the plan: done. (Planned
  again instead, Chess had already answered at depth 1 and a second move
  was played: measured.) A line clicked in the picture may have missed
  (an empty square counted one off): then the writer looks again first,
  told that a step may have missed, and answers DONE or what is left.
  Planned again too when the lines are done and nothing changed; three
  plans a run at most.

The writer never acts; Jev never plays chess. The split holds for any app:
"add these two numbers and type the sum", "pick the cheapest of these
flights", "solve this puzzle".

## Measures (mini, 2026-10-18)

Chess against its computer at its least strength. Legal: Chess takes the
move (its Game Log gets it), up to three tries. Loss: the moves read back
from the Game Log and scored after the run against Stockfish (depth 14,
stockfish.online; python-chess in a scratch environment, outside skil.li):
centipawns lost per move against the best move. Seconds: from the request
to our move in the log, the computer's thinking left out.

### Finding a square in the picture (board hidden, 8 named squares)

"clique sur la case e4", "… le cavalier blanc en g1", "… le pion noir en
d7", "… la tour noire en a8", "… la case c3", "… la dame blanche", "… la
case h5", "… le fou noir en f8", scored against where Chess draws them.

| Way | Right | Time / pick | Tokens / pick |
|---|---|---|---|
| Jev grid, coarse cell alone | 0/8 | 0.3–0.5 s | ~6,000 |
| Jev grid, coarse + fine cell | 1/8 | 0.7–1.0 s | ~12,300 |
| Jev Box, one look | 3/8 | 0.3–0.9 s | ~2,570 |
| **Jev Box, look + close-up** | **5/8** | 0.6–1.0 s | ~4,570 |
| Jev Box, 1568 px look + checked close-up, window 1320 × 1000 pt | 4/8 | 0.6–1.1 s | ~7,350 |

Jev does not read a grid's numbers back: it answered the same cells (43,
91) for different squares, at 13–39 %. Box finds pieces well; its misses
are empty squares counted one file or rank off on the 3D board (c3 → b4,
h5 → h6, f8 → h8), and, in the larger window, back-rank pieces whose box
middle falls on the square behind them (d7 → d8, f8 → g8).

### Playing (6 moves a game)

| Who chooses | Who finds | Board as | Legal, 1st try | Legal ≤ 3 | Loss / move | After 6 | s / move |
|---|---|---|---|---|---|---|---|
| Jev alone | Jev (items) | Accessibility | 0/1 | 0/1 | — | — | — |
| Jev alone | Jev Box | picture only | 0/1 | 0/1 | — | — | — |
| Claude Haiku plan | Jev (items) | Accessibility | 6/6 | 6/6 | 31 cp | −0.85 | 12.5 |
| Claude Sonnet plan | Jev (items) | Accessibility | 6/6 | 6/6 | 68 cp | −2.36 | 11.7 |
| **Claude Opus plan** | **Jev (items)** | **Accessibility** | **6/6** | **6/6** | **9 cp** | **+0.18** | **8.0** |
| Claude Sonnet plan | Jev Box, two looks | picture only | 4/6 | 6/6 | 9 cp | +0.43 | 31.6 (median 27) |
| Claude Sonnet plan, a cell | Jev Box in that cell's close-up | picture only | 1/2 | 1/2 | — | — | 13.7 |
| Claude Opus plan, a cell | Claude (Opus, Sonnet) points in the close-up | picture only | 0/2 | 0/2 | — | — | — |
| Claude Opus plan | Jev Box, 1568 px, large window | picture only | 0/2 | 1/2 | — | — | 25.4 |
| Claude Opus plan + writer's check | Jev Box, 1568 px, large window | picture only | 1/5 | 3/5 | — | — | ~36 |

The picture-only rows ran in two window sizes (907 × 712 pt at first,
1320 × 1000 pt once the demo's placement stuck), a game each or less:
they say where it breaks, not a rate. The pieces were found right in
every one of the last runs; the misses are the empty target squares
(e3 for e4, g2 or g3 for f3), which the writer's check then sees and
plans again (move 1 of the last game took three plans and landed).

### Through Ask, recorded

The demo the user sees: Ask's card, "joue le prochain coup" typed, Chess
in front, the screen recorded with only Chess and skil.li's card in the
movie.

| Board as | Moves played | s / move (typing included) |
|---|---|---|
| Accessibility (Chess as it is) | 2/2, three runs | 10.0–13.3 |
| Picture only | 1/2, then 0/3 (two minutes a move, out of time) | 17.2 for the one played |

Recording: `chess-demo-ask-joue-le-prochain-coup.mp4` (34 s, Accessibility
board, Opus plans, Jev presses: e2–e4, then Nf3).

"After 6": Stockfish's evaluation for white after our sixth move (pawns).
One game a row: the loss column is a sample, not a rating (Sonnet's game
had two inaccuracies and a lost pawn; its picture-only game none).

What the rows say:

- **Jev does not choose moves.** Alone, with the board in words, it
  opened the window's document menu and pressed "Enregistrer", or clicked
  an empty square; with the picture only, it clicked pawns at random
  ("It keeps doing “Clicked in the picture”").
- **Jev grounds a plan perfectly when the app names things.** On the
  Accessibility board every planned line ("Click the button “cavalier
  blanc, g1”") was pressed right: 23/23 moves legal at the first try over
  four games, whichever Claude planned. Speed and quality are the planner's: Opus was
  both the best and the fastest (one plan a move, ~6 s, then two Jev
  steps).
- **On a canvas, Jev finds what Claude describes.** With Claude's lines
  ("the white pawn in front of the white king, the fifth from the left in
  the second row from the bottom") Jev's Box made every move legal, two of
  six at the second try (once Claude planned a drag). Told only a square's
  name, Box finds pieces but counts empty squares one off on a 3D board
  (5/8). Narrowing it to a close-up of a cell Claude picked made it worse
  (the close-up loses the neighbours a line names: "the pawn in front of
  the queen" became the queen), and Claude pointing in that close-up
  missed by a column every time.
- **A plan finishes the goal.** Before the rule "every line done and the
  window changed: done", Sonnet's runs went on after the move (the
  computer at depth 1 answers at once, so it planned and played a second
  move, or opened "Afficher le dernier déplacement").

Decided from these: thinking steps plan with Claude Opus when the writer
is Claude (`AIActionController.control`); what is only drawn is found by
Jev's Box in two looks, from the plan's own words, and a plan clicked in
the picture is checked by the writer before it is done. On Chess, that
canvas path finds pieces but not yet empty squares reliably: the demo is
Chess as it is, its board in Accessibility; the canvas path ships behind
the same Ask, measured, for apps that offer nothing else.

Next, for the canvas path: ask Box for the square under a piece rather
than the piece (its middle falls on the square behind on a back rank);
describe target squares from pieces next to them rather than by counting;
compare an app's Accessibility frames with its picture (Chess's are upside
down, so the ring shows the mirrored square, visible in the recording).

## Grounding a plan's line (2026-10-19)

the retest on the mini (2026-10-18, 20:46–20:51, build of PR #11)
played e4 and Nf3 through Ask, but Jev's target question ranked
"Partie › Partager › Mail" first at each first line of a move (60 %,
57 %, 75 %, 76 %, 66 %), the piece Claude's plan named second (27 %,
25 %, 18 %, 19 %, 28 %) and "Partie › Enregistrer sous…" third. The
outbound gate (`ScreenControl.mayAct`) kept Mail from being clicked; the
piece was pressed because, Mail set aside, it led and nothing else came
within a third of it (else the user is asked).

Where it comes from:

- **The menus grow.** Chess opened by the user: once its game has a move
  (or the real game, from the start), Partie's Partager submenu (AirDrop,
  Mail, Messages, Notes, Freeform) and Enregistrer sous… are enabled: 28 to
  31 menu items read. A game from the New Game sheet, what the self-test
  demos played, reads 12 to 15, without them: why the demos never showed
  it.
- **The target question's guide names them.** Without a plan the
  question ends with "Pick what does exactly what the goal says: Send and
  Share items mail or share it to someone; Save As and Export put a file
  in a folder." (added for #114: Jev ran "Send PDF" for "export en PDF").
  For a planned move, that sentence pulls Jev to the very items it names.

Measured with the chess scope's `"grounding": 5`: Chess launched as the
user does (`-ApplePersistenceIgnoreState`), moves played through Ask, then
"exporte en PDF dans mes documents" through Ask in TextEdit and Word.
Every request "do it here" sent is kept as it went (the state, the
window's picture, every question) and sent to Jev again, five times each
way of asking its target question, the rest unchanged. Percent: Jev's
probability for the item the plan's line names, mean (least–most).

| Plan line (menu items read) | Goal + guide (before) | Goal alone | **The plan's line (after)** |
|---|---|---|---|
| “pion blanc, e2” (12) | 53 % (45–68) | 96 % (93–100) | **99 % (97–100)** |
| “e4” (12) | 67 % (57–75) | 99 % (99–100) | **100 %** |
| “pion blanc, d2” (31, sharing) | 23 % (20–24), Mail first 64–70 % | 93 % (91–97) | **100 %** |
| “d4” (15) | 68 % (59–79) | 98 % (95–100) | **100 % (99–100)** |
| “cavalier blanc, b1” (31, sharing) | 24 % (22–28), Mail first 60–68 % | 94 % (92–96) | **99 %** |
| “c3” (15) | 64 % (63–67) | 99 % (98–100) | **100 %** |

The first run (the same game's two moves, e4 then Nf3, as in the real game) also
left out of the options the items the gate refuses: with the guide kept,
the planned piece stayed at 60 % (47–71) for e2 and 28 % (21–38) for g1,
where "do it here" would have asked the user 4 times in 5 (under 40 %,
others close). In the second run, telling Jev to answer "none" when no
item is the line's gave nothing more (94–100 %). Jev also varies on the
very same request:
e2 at 36 to 59 % in the first run, 45 to 68 % in the second.

Without a plan the guide earns its place (the same replays, export runs):

| Export step (no plan) | Goal + guide (kept) | Goal alone |
|---|---|---|
| TextEdit, the document | Exporter au format PDF… 76 % (63–86) | Exporter au format PDF… 100 % |
| TextEdit, the save sheet | Enregistrer 86 % (78–91) | Enregistrer 98 % (96–99) |
| Word, the document | Enregistrer sous… after the gate 5/5, never asks | Send PDF first 59–73 %; Enregistrer sous… after the gate, asks 1/5 |
| Word, the document (first run) | Send PDF first 4/5; asks 5/5 | Send PDF first 5/5, then Acrobat's "Créer un PDF et Demander des signatures" after the gate (31–41 %); Send items left out, that button first at 52–72 %, 5/5 |

Decided:

- **With a plan's line to follow, the target question is that line's**:
  "Which item shown does the plan's next line act on: the one to click,
  or the field to type into? Pick the item that line names."
  (`ComputerControl.planTargetQuestion`). Without a plan, or once every
  line was done, the goal's question and its guide, as before.
- **A line that quotes one item's exact words is that item**
  (`ScreenControl.named`: the only enabled item whose label is a text the
  line quotes, case and spaces aside, a field when typing), first at
  100 % whatever Jev ranked; Jev still says what to do (click, type,
  done), and the outbound gate still applies. Jev already grounds such
  lines at 99–100 % with the new question; this takes its swings out.
- Items the gate refuses stay in the options: left out, they did not
  help Chess and let Word's Acrobat button rise first.

After, through Ask on the mini: the three probe moves played (e4, d4,
Nc3; Jev itself put each line's square or piece at 99–100 %, and each
was "named by the plan"); TextEdit's and Word's export passed (Word:
Enregistrer sous…, Documents, Format du fichier → PDF, Exporter);
`remote control` 10/10; the Chess demo through Ask 2/2 (e4 in 14.3 s,
d4 in 9.6 s, typing included).

Seen on the way, not fixed here:

- The third move (20:49:58): after "fou blanc, f1" was pressed, the next
  looks read 15 of Chess's ~73 elements in 2.2 s (Accessibility slow
  there), "b5" was not among them, Jev chose scroll, then clicked "pion
  blanc, b2" at 12 %, and the run counted its two lines done: no move
  played. Fixed in "A plan's line whose item was not read" below.
- In the first export run (TextEdit's menus read short: 19 items, 127 in
  the second), Opus planned "Click the menu “Fichier” in the menu
  bar": a menu's title is no item ("do it here" presses "Fichier ›
  Exporter…" at once), and Jev pointed at "Fichier › Nouveau".

## A plan's line whose item was not read (2026-10-19)

The third move of the retest, from the mini's log (build of PR #11,
"play the next move"):

| Time | What happened |
|---|---|
| 20:49:54.88 | Look: 73 elements in 29 ms, 31 menu items in 61 ms (Partager among them) |
| 20:49:58.03 | Opus's plan: "Click the button “fou blanc, f1”", "Click the button “b5”" |
| 20:49:58.60 | “fou blanc, f1” pressed (Chess logs `startSelection`) |
| 20:50:06.88 | Look: **15 elements in 2182 ms** (rank 1, seven squares of rank 2), 7 menu items in 1534 ms, all in 3.7 s |
| 20:50:07.11 | Jev: scroll (best item “pion blanc, b2” 16 %): the next look reads the words on screen too |
| 20:50:11.11 | Look: 15 elements in 2170 ms, 7 menu items in 1567 ms |
| 20:50:11.71 | Jev with the picture: “сб” (the board's OCR) 12 %, “pion blanc, b2” 12 %, spot 6 %: under 40 % with others close, the card asks which one |
| 20:50:15.93 | “pion blanc, b2” pressed in 4 ms (Chess fast again); Chess: `endSelection`, no `executeMove` |
| 20:50:16.47 | "Done … 2 steps": both plan lines counted, no move played |

Why the reads got slow (what the logs show):

- **Chess answered slowly, not skil.li.** `UIReader.snapshot` stops at
  2 s; 15 elements in 2.2 s is ~145 ms an element, about 18 ms an
  Accessibility call: one call a frame of Chess's main thread, from the
  press until some time between 20:50:11.1 and 20:50:15.9 (12 to 17 s).
  The menus, read from the same thread, were slow the same way. Two runs
  later the same press of the same bishop (20:50:35.54) was followed by
  a look of 73 elements in 15 ms.
- **Not the user.** The cursor was hidden from 20:49:51 (typing) to
  20:50:18: no mouse over the board.
- **Rare.** Of the 817 looks in the mini's log (2026-10-18 17:49 to
  2026-10-19 06:52: self-tests and the retest), these two are the only
  ones over a second.
- **What Chess did meanwhile is not in its log**: nothing from its main
  thread between `startSelection` (20:49:58.60) and 20:50:09.85, when it
  cancelled two XPC connections it had opened at 20:49:54.61, while
  skil.li read its window and menus (Partager builds its share menu
  then: ShareKit's "Request for menu", "It took 48 ms to prepare the
  menu"). In the fast run, the same two connections were cancelled at
  the next menu read and opened again 140 ms after the press. They go to
  AppKit's `com.apple.appkit.xpc.ThemeWidgetControlViewService`; whether
  that held Chess's main thread is not proven, and a probe did not make
  Chess slow again (below).

Decided (`ComputerControl.run`, `ScreenControl.unread`, `PlanProgress`):

- **A plan's line that clicks an item by its words, and no item read is
  it, reads the window again before anything is decided** (`unread`: the
  line starts with a click — "Click", "Clique", "Double-click",
  "Choose", "Select", "Press the button"… — and none of the items read
  has the words it quotes, or one part of them: "b5" is read in
  “fou blanc, b5”, "Mail" in “Partie › Partager › Mail”, "Save As" in
  “Save As…”). A key, text to type, or something drawn described by its
  look is never waited for.
  - The look was cut short (`UIReader.snapshot`'s `cutShort`: its time
    ran out): read again every 300 ms with 6 s each, for 12 s at most
    (a slow Chess's whole board takes ~10 s at 145 ms an element; b5 is
    its 34th). Still cut short without it: stopped, "Échecs answered too
    slowly…: Nothing else was clicked."
  - The look was whole: once more after 0.8 s (still drawing).
- **Still not read: never another item at a low probability.** Jev sure
  of another item for the line (60 % or more: the line said in other
  words, "Click “Save”" for “Enregistrer”) clicks it; a place in the
  picture (something drawn), a key or a scroll go on as before; any
  other click or typing is not done and the run stops ("“b5” is not in
  Échecs's window, the plan's next step: stopped rather than click
  something else."). The card never asks the user to pick between items
  that are not the line's. Planning again was tried first and dropped
  (measures below): told the square was not shown, Opus described it as
  drawn, and Jev pressed squares beside it.
- **"Every line done" counts only steps that did what the line says**
  (`PlanProgress.step`, `ScreenControl.follows`): a step that acted on
  the line's item (its words, or a part of them), the item Jev was sure
  of above, or a click in the picture for that line (the writer checks
  those after). A line that names no item by its words (a key, a drawn
  thing) takes any step, as before; a scroll does no line. A step that
  did not do it leaves that line next: the next decision is asked about
  the same line, and the run cannot end on lines it did not play.

Measured on the mini (2026-10-19, chess scope, Opus plans, Jev grounds):

- **Cut short as the real Chess game** (`"modes": ["claude-ax:opus"], "moves": 3,
  "slowLooks": 2`: once a move's first square is pressed, the next two
  looks give 15 elements and say they were cut short): 3/3 moves played,
  each at its first try, 8.4–9.4 s a move. Each time the plan's second
  square (“e4”, “d4”, “c3”) was not read, the window was read twice more
  and found in 0.94–1.07 s, then pressed as named by the plan (Jev
  100 %); steps = the plan's lines.
  No bishop moved: the three moves were e4, d4, Nc3.
- **The line's square never read** (`"hideTarget": true`: the first
  plan's second square left out of every look once its first was
  pressed; the window read whole). With the first build, which asked
  the writer for a new plan: 2/2 moves legal but not as planned. Told
  “e4” was not shown, Opus described it ("the empty board square … right
  above the button “e3”") and the line's quoted landmark was pressed
  (e2–e3); for Nf3, a click in the picture missed, the new plan
  described f3 without quoting it and Jev pressed “f4” (illegal); for
  d4, Jev pressed “d3”. Planning again was dropped. With the build
  shipped: "Click the button “e4”" unread, read again once, then Jev:
  spot 34 %, “e5” 29 %, “e3” 6 %: the place in the picture was clicked
  for the line and e4 played (13.0 s); no other square pressed (“e5” at
  29 % was within reach of the card's "Which one?" before).
- **Chess slow again?** (`"slowProbe": 4`, twice: a game from the New
  Game sheet, then Chess's first game as the user opens it): 1. e4 and
  the computer's answer, then four times the look "do it here" takes,
  the f1 bishop pressed 3.5 s later and the window read every 500 ms
  for 12 s. 0/8 rounds slow: every read 72–73 elements in 36–47 ms,
  menus read or not. Neither game had Partie › Partager enabled (15 menu
  items, 31 in the real game), so that state was not met; the cause stays
  open, the fix does not depend on it.
- `remote control`: 10/10 (forms, icons by picture, Safari, TextEdit's
  and Word's export through Ask, Your Details).

## Open

- Jev with images and Box are TypeSafe's Danger Zone (Dreamer-ready).
- Opus for thinking steps spends more of the user's plan (or API) than
  their writer: one plan per step that needs one.
- Drags and canvas scrolling, when a goal needs them.
- Chess's mirrored frames: an app whose Accessibility frames disagree
  with its picture could be caught by comparing the two (not done).
