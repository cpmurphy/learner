import { Chessboard } from "./3rdparty/cm-chessboard/Chessboard.js";
import { FEN } from "./3rdparty/cm-chessboard/model/Position.js";

document.addEventListener("DOMContentLoaded", () => {
    const boardContainer = document.getElementById("chessboard-container");
    if (!boardContainer) {
        console.error("Chessboard container not found!");
        return;
    }

    const props = {
        position: FEN.start, // Initial position
        assetsUrl: "/3rdparty-assets/cm-chessboard/" // Path to cm-chessboard assets (SVGs for pieces)
                                                    // Assumes 'public' is served as the web root.
    };
    const board = new Chessboard(boardContainer, props);

    console.log("Chessboard initialized.");

    // Placeholder event listeners for controls
    document.getElementById("prev-move")?.addEventListener("click", () => {
        console.log("Previous move clicked");
        // TODO: Implement logic
    });

    document.getElementById("next-move")?.addEventListener("click", () => {
        console.log("Next move clicked");
        // TODO: Implement logic
    });

    document.getElementById("next-critical")?.addEventListener("click", () => {
        console.log("Next critical moment clicked");
        // TODO: Implement logic
    });

    document.getElementById("learn-side")?.addEventListener("change", (event) => {
        console.log("Learn side changed to:", event.target.value);
        // TODO: Implement logic
    });
});
