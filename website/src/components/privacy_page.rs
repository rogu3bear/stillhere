use leptos::prelude::*;
use leptos_meta::Title;

#[component]
pub fn PrivacyPage() -> impl IntoView {
    view! {
        <Title text="Privacy — Still Here"/>
        <div class="document wrap"><p class="eyebrow">"PRIVACY"</p><h1>"Local by design."</h1>
            <section><h2>"The Mac app"</h2><p>"Still Here has no telemetry, account, or remote service. Its network requests are HTTP and HTTPS probes to 127.0.0.1 and ::1 on ports it finds listening on your Mac."</p><p>"It reads only agent markers from process environments: CLAUDECODE, CLAUDE_CODE_SESSION_ID, CLAUDE_PID, CODEX_SANDBOX, and AI_AGENT. Other environment values are skipped without decoding."</p><p>"It inspects agent and Node process arguments to identify agents and explicit reviewer roles. Arguments are never stored or reported. Command lines and process environments are excluded from JSON and MCP output."</p></section>
            <section><h2>"Files and permissions"</h2><p>"The app reads git metadata and nearby project manifests to show the branch, worktree, and a framework guess. macOS may ask for folder access when a project is in a protected location. Declining makes the framework guess less specific."</p><p>"Preferences such as the ignore list are stored locally. The app sees only processes owned by your user. Stop verifies identity before signalling one process."</p></section>
            <section><h2>"This website"</h2><p>"The site has no analytics scripts, advertising, or contact form. It uses locally served styles, fonts, and images. Cloudflare serves the site and may process ordinary request metadata in operational logs."</p><p>"The public site does not require an account or set tracking cookies."</p><a class="text-link" href="/docs">"Read the product guide →"</a></section>
        </div>
    }
}
