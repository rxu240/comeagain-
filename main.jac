"""TONECRAFT - delivery analysis for people who speak for a living.

Entry point. The server import below registers the walker endpoints; the `cl`
block mounts the React client. Everything either side of that boundary is Jac.
"""

import from api { AnalyseTake, ListTakes, LoadTake, DeleteTake }

cl {
    import ".styles.global.css";
    import from .components.AppShell { AppShell }

    def:pub app() -> JsxElement {
        return <AppShell/>;
    }
}
