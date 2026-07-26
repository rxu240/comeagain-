"""Shared display formatting for the client."""


"""Seconds as m:ss."""
def:pub fmtTime(t: float) -> str {
    safe = t if t > 0.0 else 0.0;
    mins = Math.floor(safe / 60.0);
    secs = Math.floor(safe % 60.0);
    return String(mins) + ":" + String(secs).padStart(2, "0");
}


"""A time range as m:ss-m:ss."""
def:pub fmtRange(a: float, b: float) -> str {
    return fmtTime(a) + "-" + fmtTime(b);
}
