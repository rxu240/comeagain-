"""A text flag trailing the cursor, client side.

Ported from tholman/cursor-effects' textFlag effect (MIT) rather than loaded
from a CDN, so the app stays self-contained and the 40% Jac rule counts it.
A canvas is drawn under the real cursor; each character chases the one ahead
of it with a spring-like lag, and the whole chain wobbles on a small ellipse
so it reads as a flag rather than a straight line of text.
"""

glob TEXT: str = " by Ryan Xu and Esther Xu";
glob COLOR: str = "#6D63E0";
glob FONT_SPEC: str = "12px monospace";
glob GAP: float = 14.0;
glob RADIUS_X: float = 2.0;
glob RADIUS_Y: float = 5.0;

glob _cfCanvas: any = None;
glob _cfCtx: any = None;
glob _cfFrame: any = None;
glob _cfCursor: any = None;
glob _cfChars: list[any] = [];
glob _cfAngle: float = 0.0;


"""Track the real cursor position."""
def onCursorMove(e: any) -> None {
    _cfCursor["x"] = e.clientX;
    _cfCursor["y"] = e.clientY;
}


"""Keep the canvas covering the viewport after a resize."""
def onCursorResize(e: any) -> None {
    _cfCanvas.width = window.innerWidth;
    _cfCanvas.height = window.innerHeight;
}


"""One frame: each character eases toward the one ahead of it."""
def updateCursorFlag() -> None {
    _cfCtx.clearRect(0, 0, _cfCanvas.width, _cfCanvas.height);

    _cfAngle = _cfAngle + 0.15;
    locX = RADIUS_X * Math.cos(_cfAngle);
    locY = RADIUS_Y * Math.sin(_cfAngle);

    i = len(_cfChars) - 1;
    while i > 0 {
        _cfChars[i]["x"] = _cfChars[i - 1]["x"] + GAP;
        _cfChars[i]["y"] = _cfChars[i - 1]["y"];

        _cfCtx.fillStyle = COLOR;
        _cfCtx.font = FONT_SPEC;
        _cfCtx.fillText(_cfChars[i]["letter"], _cfChars[i]["x"], _cfChars[i]["y"]);
        i = i - 1;
    }

    x1 = _cfChars[0]["x"] + (_cfCursor["x"] - _cfChars[0]["x"]) / 5.0 + locX + 2.0;
    y1 = _cfChars[0]["y"] + (_cfCursor["y"] - _cfChars[0]["y"]) / 5.0 + locY;
    _cfChars[0]["x"] = x1;
    _cfChars[0]["y"] = y1;
}


def cursorLoop() -> None {
    updateCursorFlag();
    _cfFrame = window.requestAnimationFrame(cursorLoop);
}


"""Start the trailing flag once. Safe to call more than once; a second call
is a no-op while the first instance is still running."""
def:pub startCursorFlag() -> None {
    if _cfCanvas { return; }

    reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    if reduced.matches { return; }

    _cfCanvas = document.createElement("canvas");
    _cfCtx = _cfCanvas.getContext("2d");
    _cfCanvas.style.position = "fixed";
    _cfCanvas.style.top = "0px";
    _cfCanvas.style.left = "0px";
    _cfCanvas.style.pointerEvents = "none";
    _cfCanvas.style.zIndex = "9999999999";
    _cfCanvas.width = window.innerWidth;
    _cfCanvas.height = window.innerHeight;
    document.body.appendChild(_cfCanvas);

    startX = window.innerWidth / 2.0;
    startY = window.innerHeight / 2.0;
    _cfCursor = {"x": startX, "y": startY};

    chars: list[any] = [];
    for ch in TEXT {
        chars.push({"letter": ch, "x": startX, "y": startY});
    }
    _cfChars = chars;

    window.addEventListener("mousemove", onCursorMove);
    window.addEventListener("resize", onCursorResize);
    cursorLoop();
}
