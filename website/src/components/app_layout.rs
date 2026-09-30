use super::product::{Brand, VERSION};
use leptos::prelude::*;

#[component]
pub fn AppLayout(children: Children) -> impl IntoView {
    view! {
        <a class="skip-link" href="#content" target="_self">"Skip to content"</a>
        <header class="site-header wrap">
            <a class="brand" href="/" aria-label="Still Here home"><Brand/></a>
            <nav aria-label="Main navigation">
                <a href="/screens" target="_self">"Screens"</a><a href="/docs">"Guide"</a>
                <a class="button button-small" href="/#download" target="_self">"Get Still Here" <span aria-hidden="true">"↗"</span></a>
            </nav>
        </header>
        <main id="content" tabindex="-1">{children()}</main>
        <footer class="site-footer wrap">
            <div><a class="brand" href="/"><Brand/></a><p>"Know what’s still running."</p></div>
            <nav aria-label="Footer navigation"><a href="/docs">"Guide"</a><a href="/privacy">"Privacy"</a><a href="/docs/release">"v0.1.0"</a></nav>
            <p class="footer-note">"© 2026 MLNavigator Inc. · v" {VERSION}</p>
        </footer>
    }
}
