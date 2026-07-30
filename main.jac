"""TONECRAFT - delivery analysis for people who speak for a living.

Entry point. The server import below registers the walker endpoints; the `cl`
block mounts the React client. Everything either side of that boundary is Jac.
"""

import from api { AnalyseTake, ListTakes, LoadTake, DeleteTake }

cl {
    import ".styles.global.css";
    import from .components.AppShell { AppShell }
    import from .components.Landing { Landing }

    """The practice app is still being edited - only localhost gets it.
    Everyone else (comeagain.pro, any deploy preview) sees the waitlist."""
    def:pub app() -> JsxElement {
        isLocal = window.location.hostname == "localhost" or window.location.hostname == "127.0.0.1";
        if isLocal {
            return <AppShell/>;
        }
        return <Landing/>;
    }
}
