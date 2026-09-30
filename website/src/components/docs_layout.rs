use leptos::prelude::*;

#[component]
pub fn DocsLayout(active: &'static str, children: Children) -> impl IntoView {
    let pages = [
        ("overview", "/docs", "Why Still Here"),
        ("start", "/docs/getting-started", "Getting started"),
        ("menu", "/docs/menu-bar", "Menu bar & Settings"),
        ("cli", "/docs/cli", "Command line"),
        ("agents", "/docs/agents", "Coding agents"),
        ("help", "/docs/troubleshooting", "Troubleshooting"),
        ("release", "/docs/release", "v0.1.0"),
    ];
    view! {
        <div class="docs-shell wrap">
            <aside class="docs-sidebar">
                <p class="eyebrow">"THE GUIDE"</p>
                <nav aria-label="Documentation">
                    {pages.into_iter().map(|(key, href, label)| view! {
                        <a href=href aria-current=if key == active { Some("page") } else { None }>{label}</a>
                    }).collect_view()}
                </nav>
                <a class="text-link" href="/screens">"See the actual app ↗"</a>
            </aside>
            <article class="docs-article">{children()}</article>
        </div>
    }
}
