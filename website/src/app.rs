use leptos::prelude::*;
use leptos_meta::{provide_meta_context, Meta, MetaTags, Title};
use leptos_router::{
    components::{Route, Router, Routes},
    SsrMode, StaticSegment, WildcardSegment,
};

use crate::components::app_layout::AppLayout;
use crate::components::docs_agents::AgentGuidePage;
use crate::components::docs_cli::CliGuidePage;
use crate::components::docs_help::TroubleshootingPage;
use crate::components::docs_menu::MenuBarGuidePage;
use crate::components::docs_page::DocsPage;
use crate::components::docs_release::ReleaseGuidePage;
use crate::components::docs_start::GettingStartedPage;
use crate::components::home_page::HomePage;
use crate::components::privacy_page::PrivacyPage;
use crate::components::screens_page::ScreensPage;

#[allow(dead_code)]
pub fn shell(options: LeptosOptions) -> impl IntoView {
    view! {
        <!DOCTYPE html>
        <html lang="en">
            <head>
                <meta charset="utf-8"/>
                <meta name="viewport" content="width=device-width, initial-scale=1"/>
                <link rel="icon" href="/images/app-icon.png" type="image/png"/>
                <link rel="manifest" href="/site.webmanifest"/>
                <meta name="theme-color" content="#fafafa"/>
                <meta property="og:title" content="term-web — A little clarity for localhost"/>
                <meta property="og:description" content="Every dev server, its project, branch, and the agent behind it. A native utility for your Mac."/>
                <meta property="og:type" content="website"/>
                <AutoReload options=options.clone()/>
                <HashedStylesheet options=options.clone()/>
                <EdgeHydrationScripts options=options/>
                <MetaTags/>
            </head>
            <body>
                <App/>
            </body>
        </html>
    }
}

#[component]
pub fn App() -> impl IntoView {
    provide_meta_context();

    view! {
        <Title text="term-web"/>
        <Meta
            name="description"
            content="Find every dev server on your Mac, its project, git branch, and the coding agent behind it. Menu bar app, CLI, and MCP server."
        />

        <Router>
            // AppLayout provides a persistent header + navigation across all pages.
            // Keeping it inside Router gives the shared nav links their routing context.
            <AppLayout>
                <Routes fallback=|| view! { <NotFoundPage/> }.into_view()>
                    <Route path=StaticSegment("") view=HomePage ssr=SsrMode::OutOfOrder/>
                    <Route path=StaticSegment("screens") view=ScreensPage ssr=SsrMode::OutOfOrder/>
                    <Route path=StaticSegment("docs") view=DocsPage ssr=SsrMode::OutOfOrder/>
                    <Route path=(StaticSegment("docs"), StaticSegment("getting-started")) view=GettingStartedPage ssr=SsrMode::OutOfOrder/>
                    <Route path=(StaticSegment("docs"), StaticSegment("menu-bar")) view=MenuBarGuidePage ssr=SsrMode::OutOfOrder/>
                    <Route path=(StaticSegment("docs"), StaticSegment("cli")) view=CliGuidePage ssr=SsrMode::OutOfOrder/>
                    <Route path=(StaticSegment("docs"), StaticSegment("agents")) view=AgentGuidePage ssr=SsrMode::OutOfOrder/>
                    <Route path=(StaticSegment("docs"), StaticSegment("troubleshooting")) view=TroubleshootingPage ssr=SsrMode::OutOfOrder/>
                    <Route path=(StaticSegment("docs"), StaticSegment("release")) view=ReleaseGuidePage ssr=SsrMode::OutOfOrder/>
                    <Route path=StaticSegment("privacy") view=PrivacyPage ssr=SsrMode::OutOfOrder/>

                    // Critical for Cloudflare + Leptos on the edge:
                    // This must be last. It ensures deep links and pre-hydration
                    // requests get a full SSR HTML shell (in cooperation with
                    // the generated `build/_worker.js`).
                    <Route path=WildcardSegment("any") view=NotFoundPage ssr=SsrMode::OutOfOrder/>
                </Routes>
            </AppLayout>
        </Router>
    }
}

#[component]
fn NotFoundPage() -> impl IntoView {
    // The route that actually renders recovery owns its HTTP status. Keeping
    // another path registry in the Worker would reject newly added app routes.
    #[cfg(feature = "ssr")]
    if let Some(response) = use_context::<leptos_axum::ResponseOptions>() {
        response.set_status(axum::http::StatusCode::NOT_FOUND);
    }

    view! {
        <Title text="Page not found — term-web"/>
        <div class="document wrap route-miss">
            <p class="eyebrow">"404 / PAGE NOT FOUND"</p>
            <h1>"Nothing running here."</h1>
            <p>"This address does not point to a page. Head home or open the guide."</p>
            <div class="actions"><a class="button" href="/">"Back to term-web"</a><a class="text-link" href="/docs">"Open the guide →"</a></div>
        </div>
    }
}

#[component]
fn HashedStylesheet(options: LeptosOptions) -> impl IntoView {
    let href = asset_href(&options, "css", crate::asset_hashes::CSS_HASH);

    view! {
        <link id="leptos" rel="stylesheet" href=href/>
    }
}

#[component]
fn EdgeHydrationScripts(options: LeptosOptions) -> impl IntoView {
    let js_href = asset_href(&options, "js", crate::asset_hashes::JS_HASH);
    let wasm_href = asset_href(&options, "wasm", crate::asset_hashes::WASM_HASH);
    #[cfg(feature = "ssr")]
    let nonce = leptos::nonce::use_nonce();
    #[cfg(not(feature = "ssr"))]
    let nonce = None::<String>;
    let hydration_script = format!(
        "import({js_href:?}).then(mod => {{ mod.default({{ module_or_path: {wasm_href:?} }}).then(() => {{ mod.hydrate(); }}); }});"
    );

    view! {
        <link rel="modulepreload" href=js_href.clone() crossorigin="anonymous"/>
        <link rel="preload" href=wasm_href.clone() r#as="fetch" r#type="application/wasm" crossorigin="anonymous"/>
        <script type="module" nonce=nonce>{hydration_script}</script>
    }
}

fn asset_href(options: &LeptosOptions, extension: &str, hash: &str) -> String {
    let output_name = options.output_name.as_ref();
    let output_name = if output_name.is_empty() {
        env!("CARGO_PKG_NAME")
    } else {
        output_name
    };
    let pkg_dir = options.site_pkg_dir.as_ref();

    if hash.is_empty() {
        format!("/{pkg_dir}/{output_name}.{extension}")
    } else {
        format!("/{pkg_dir}/{output_name}.{hash}.{extension}")
    }
}
