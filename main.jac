"""TONECRAFT - delivery analysis for people who speak for a living.

Entry point. The server import below registers the walker endpoints; the `cl`
block mounts the React client. Everything either side of that boundary is Jac.
"""

import from api { AnalyseTake, ListTakes, LoadTake, DeleteTake }

cl {
    import ".styles.global.css";
    import from .components.AppShell { AppShell }
    import from .components.Landing { Landing }

    """Everyone lands on the waitlist page by default - the practice app
    is still being edited and isn't public yet. Only on localhost does the
    landing page get a button through to it, for local testing."""
    def:pub app() -> JsxElement {
        has view: str = "landing";

        isLocal = window.location.hostname == "localhost" or window.location.hostname == "127.0.0.1";

        if view == "app" and isLocal {
            return <AppShell/>;
        }
        return <Landing showAppLink={isLocal} onOpenApp={lambda () { view = "app"; }}/>;
    }
}
