"""Public landing page: waitlist signup, no app behind it.

This is what comeagain.pro shows in production, and what localhost shows by
default too - it's the thing actively being edited. The VC/Girlfriend
practice app (AppShell) still exists for local testing only: main.jac passes
showAppLink=True on localhost, which reveals the dev-only button below.
"""

glob STRIPE_PAYMENT_LINK: str = "https://buy.stripe.com/REPLACE_ME";


def isValidEmail(value: str) -> bool {
    if " " in value or value.count("@") != 1 {
        return False;
    }
    parts = value.split("@");
    local = parts[0];
    domain = parts[1];
    return len(local) > 0 and "." in domain and not domain.startswith(".") and not domain.endswith(".");
}


def:pub Landing(showAppLink: bool, onOpenApp: Callable[[], None]) -> JsxElement {
    has email: str = "",
        error: str = "",
        submitting: bool = False;

    def submit(e: any) -> None {
        e.preventDefault();
        trimmed = email.strip();
        if not isValidEmail(trimmed) {
            error = "Enter a valid email to continue.";
            return;
        }
        error = "";
        submitting = True;
        url = new(URL, STRIPE_PAYMENT_LINK);
        url.searchParams.set("prefilled_email", trimmed);
        window.location.href = url.toString();
    }

    submitLabel = "Reserve your spot ->";
    if submitting { submitLabel = "Redirecting..."; }

    return <div className="relative z-10 min-h-svh flex flex-col px-6 py-[6vh]">
        <header className="px-5 pt-2 pb-2">
            <span className="display text-[15px] tracking-tight text-ink-700">
                {"comeagain?"}
            </span>
        </header>

        <main className="flex-1 w-full max-w-[30rem] mx-auto flex flex-col items-center justify-center text-center">
            <h1 className="display text-[clamp(1.9rem,5vw,2.6rem)] leading-[1.25] text-ink-900 mb-4">
                {"Be heard."}
            </h1>

            <p className="text-[1rem] text-ink-600 mb-11">
                {"Leave your email and we'll let you in the moment beta opens."}
            </p>

            <form onSubmit={submit} className="glass w-full flex flex-col gap-3 p-6 rounded-3xl">
                <input
                    type="email"
                    value={email}
                    onChange={lambda (e: ChangeEvent) { email = e.target.value; }}
                    placeholder="you@email.com"
                    autoComplete="email"
                    required={True}
                    aria-label="Email address"
                    className="glass-quiet w-full rounded-2xl px-[1.1rem] py-[0.9rem] text-[0.95rem] text-ink-900 placeholder:text-ink-400 outline-none border-0"
                />
                {if error != "" {
                    <p className="text-[0.8rem] text-clay -mt-1 mb-0" role="alert">{error}</p>
                }}
                <button
                    type="submit"
                    disabled={submitting}
                    className="glass-btn rounded-2xl px-[1.1rem] py-[0.95rem] text-[0.95rem] font-medium cursor-pointer"
                >
                    {submitLabel}
                </button>
            </form>

            <p className="mono text-[0.7rem] tracking-[0.08em] text-ink-400 mt-[1.1rem]">
                {"Beta is releasing 8/10/26"}
            </p>

            {if showAppLink {
                <button
                    type="button"
                    onClick={onOpenApp}
                    className="glass-quiet rounded-full px-4 py-2 mono text-[11px] uppercase tracking-[0.2em] text-ink-600 cursor-pointer border-0 mt-8"
                >
                    {"Dev: open VC/GF app ->"}
                </button>
            }}
        </main>
    </div>;
}
