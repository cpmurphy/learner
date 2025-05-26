This is a tool that you can use to learn from your chess games. It works as follows:

# Step One: Loading a Game
 1. get a PGN of your game (most online sites allow you to export via copy/paste)
 1. annotate this PGN with SCID
 1. save the resulting file
 1. run the learn tool, passing your annotated PGN as a parameter
 1. load the interface using your browser

# Step Two: Playing Through a Game

  * it shows the game in the display
  * you choose which side from whose mistakes you want to learn
  * you can move forwards and backwards, using the buttons
  * there is a button to go straight to the next critical moment
  * critical moments are annotated with $201 (SCID's value for critical moments)
  * you are shown the move that was a mistake and given the chance to try again
  * if you guess correctly, you can keep going; if not, you can try again or skip


# Installation

## Prerequisites

- Ruby (version 3.2.3 or higher recommended)
- Bundler gem
- Rake (the ruby build tool)
- npm (the Node package manager)
- Docker (optional, for containerized deployment)

# Implementation Notes

The UI is javascript but does not use a framework. However, the cm-chessboard package is used for the board and pieces.