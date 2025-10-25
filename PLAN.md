# PGN Upload and Annotation Feature - Implementation Plan

## Goal
Automate the manual SCID annotation workflow by allowing users to upload PGN files via the web UI and run Stockfish analysis directly, saving annotated PGNs to PGN_DIR.

## Current State Analysis

**What exists:**
- `GameEditor.add_blunder_annotations(game)` - Adds $201 annotations to blunders
- PGN parsing via pgn2 gem
- Stockfish analysis via `Analyzer` class

**What's missing:**
- PGN file upload endpoint
- Adding variations (better moves) to the PGN, not just $201 markers
- PGN serialization (writing game back to PGN format)
- Frontend upload UI

---

## Implementation Plan

### **Phase 1: PGN Serialization (Backend Foundation)**
*Enable writing annotated games back to PGN format*

**Step 1.1: Create PGN Writer class** (`lib/pgn_writer.rb`)
- Write method to serialize `PGN::Game` to PGN string format
- Handle tags (Event, Site, Date, White, Black, Result, etc.)
- Handle moves with annotations ($201, comments)
- Handle variations (alternative move sequences)
- **Output:** Can convert in-memory game to PGN string

**Step 1.2: Add tests for PGN Writer**
- Test serialization of simple game
- Test serialization with annotations
- Test serialization with variations
- Test round-trip: parse → modify → serialize → parse

---

### **Phase 2: Enhanced Annotation (Core Feature)**
*Add variations showing better moves, not just $201 markers*

**Step 2.1: Enhance GameEditor to add variations**
- Modify `add_blunder_annotations` to also add variations
- When a blunder is found, add the best move as a variation
- Keep the $201 annotation for compatibility
- **Output:** Annotated games now include suggested alternatives

**Step 2.2: Add MoveTranslator reverse conversion** (if needed)
- If variations need to be in SAN format, ensure UCI → SAN conversion
- The Analyzer returns moves in UCI format (e.g., "e2e4")
- PGN variations need SAN format (e.g., "e4")
- **Note:** May be able to use chess.js or create simple converter

**Step 2.3: Add tests for enhanced annotation**
- Test that variations are added correctly
- Test that both $201 and variations exist
- Verify variation format is valid PGN

---

### **Phase 3: File Upload Backend**
*Accept PGN uploads and save annotated results*

**Step 3.1: Add file upload endpoint** (`POST /api/upload_pgn`)
- Accept multipart/form-data file upload
- Validate file is valid PGN
- Parse PGN content
- **Output:** Returns parsed game info or error

**Step 3.2: Add annotation + save endpoint** (`POST /api/annotate_and_save`)
- Accept uploaded PGN content
- Run analysis and annotation (GameEditor)
- Serialize back to PGN format (PGNWriter)
- Save to PGN_DIR with timestamp or unique name
- **Output:** Returns success + filename, or error

**Step 3.3: Add file management**
- Prevent filename collisions (use timestamps or sanitize names)
- Ensure files are saved within PGN_DIR boundary (security)
- Refresh available PGN list after upload
- **Output:** New file appears in game list

---

### **Phase 4: Frontend Upload UI**
*Allow users to upload files via web interface*

**Step 4.1: Add upload form to UI**
- Add file input and upload button to index.html
- Style to match existing UI
- Show upload progress indicator
- **Output:** User can select PGN file from disk

**Step 4.2: Implement upload JavaScript**
- Add fetch call to POST /api/upload_pgn
- Handle file reading via FormData
- Show success/error messages
- **Output:** File is uploaded to server

**Step 4.3: Add annotation trigger**
- Add "Annotate with Stockfish" button/checkbox
- Call POST /api/annotate_and_save
- Show progress during analysis (can be slow)
- Refresh PGN file list after completion
- **Output:** User sees annotated game in file list

---

### **Phase 5: Integration & Polish**
*Wire everything together and handle edge cases*

**Step 5.1: Add progress indication**
- Long-running Stockfish analysis needs feedback
- Consider WebSocket or polling for status updates
- Show "Analyzing move X of Y..."
- **Output:** User knows analysis is in progress

**Step 5.2: Error handling**
- Handle invalid PGN files gracefully
- Handle Stockfish errors/timeouts
- Handle disk write errors
- Show meaningful error messages to user
- **Output:** Robust error handling

**Step 5.3: Optional enhancements**
- Download annotated PGN directly
- Configure analysis depth/threshold
- Batch upload multiple games
- Preview annotations before saving

---

## Recommended Implementation Order

1. **Phase 1.1-1.2** (PGN Writer) - Foundational and testable in isolation
2. **Phase 2.1-2.3** (Enhanced Annotation) - Builds on PGN Writer, still backend-only
3. **Phase 3** (Backend Upload) - Can test with curl before UI exists
4. **Phase 4** (Frontend) - Wire up the UI
5. **Phase 5** (Polish) - Make it production-ready

Each phase produces a testable, working component.

---

## Technical Considerations

**PGN Variation Format:**
```pgn
1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. Bxf7+? $201 (4. c3 {Better is c3}) Kxf7
```
The variation `(4. c3 ...)` shows the better move.

**File Naming:**
- Append timestamp: `my_game_20251025_143022.pgn`
- Or add suffix: `my_game_annotated.pgn`
- Check if file exists before saving

**Security:**
- Validate uploaded files are text/PGN
- Limit file size (e.g., 10MB max)
- Sanitize filenames
- Ensure PGN_DIR path traversal protection

---

## Status

- [x] Phase 1.1: PGN Writer class
- [x] Phase 1.2: PGN Writer tests
- [x] Phase 2.1: Enhanced annotation
- [x] Phase 2.2: UCI to SAN conversion
- [x] Phase 2.3: Enhanced annotation tests
- [x] Phase 3.1: Upload endpoint
- [x] Phase 3.2: Annotate and save endpoint
- [x] Phase 3.3: File management
- [ ] Phase 4.1: Upload form UI
- [ ] Phase 4.2: Upload JavaScript
- [ ] Phase 4.3: Annotation trigger
- [ ] Phase 5.1: Progress indication
- [ ] Phase 5.2: Error handling
- [ ] Phase 5.3: Optional enhancements
