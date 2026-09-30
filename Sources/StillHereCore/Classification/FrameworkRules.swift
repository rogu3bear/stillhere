/// Data tables for framework detection. Order matters: the first match wins.
enum FrameworkRules {
    typealias ArgvRule = @Sendable (ArgvView, ManifestFacts?) -> String?

    static func rule(_ name: String, _ test: @escaping @Sendable (ArgvView) -> Bool) -> ArgvRule {
        { view, _ in test(view) ? name : nil }
    }

    static let argv: [ArgvRule] = [
        rule("Next.js") { $0.hasPrefix("next-server") || $0.has("next", followedBy: ["dev", "start"]) },
        // Meta-frameworks run their dev server through the `vite` binary; the manifest
        // tells them apart from a plain Vite app.
        { view, manifest in
            guard view.has("vite") else { return nil }
            return manifest.flatMap(viteMetaFramework) ?? "Vite"
        },
        rule("Astro") { $0.has("astro") },
        rule("Remix") { $0.has("remix") || $0.has("remix-serve") },
        rule("React Router") { $0.has("react-router") },
        rule("Nuxt") { $0.has("nuxt") || $0.has("nuxi") },
        rule("SvelteKit") { $0.has("svelte-kit") },
        rule("webpack") { $0.has("webpack-dev-server") || $0.has("webpack", followedBy: ["serve"]) },
        rule("Parcel") { $0.has("parcel") },
        rule("Storybook") { $0.has("storybook") },
        rule("Wrangler") { $0.has("wrangler") },
        rule("Angular") { $0.has("ng", followedBy: ["serve"]) },
        rule("Expo") { $0.has("expo") },
        rule("Metro") { $0.has("metro") },
        rule("Gatsby") { $0.has("gatsby") },
        rule("Eleventy") { $0.has("eleventy") },
        rule("Hugo") { $0.has("hugo", followedBy: ["server"]) },
        rule("Jekyll") { $0.has("jekyll", followedBy: ["serve"]) },
        rule("Rails") { $0.has("rails", followedBy: ["server", "s"]) || $0.hasPathSuffix("bin/rails") },
        { view, manifest in
            guard view.has("puma") else { return nil }
            return manifest?.dependencies.contains("rails") == true ? "Rails" : "Puma"
        },
        rule("Django") { $0.has("manage.py", followedBy: ["runserver"]) },
        rule("Flask") { $0.has("flask", followedBy: ["run"]) || $0.hasModule("flask") },
        { view, manifest in
            if view.has("fastapi", followedBy: ["dev", "run"]) { return "FastAPI" }
            guard view.has("uvicorn") || view.hasModule("uvicorn") else { return nil }
            return manifest?.dependencies.contains("fastapi") == true ? "FastAPI" : "Uvicorn"
        },
        rule("Gunicorn") { $0.has("gunicorn") },
        rule("Python http.server") { $0.hasModule("http.server") },
        rule("Jupyter") { $0.hasPrefix("jupyter") },
        rule("PHP built-in server") { $0.hasPrefix("php") && $0.hasArgument("-S") },
    ]

    /// Frameworks whose dev server is started as `vite`, keyed by their package.json dependency.
    static let viteMetaFrameworks: [(dependency: String, name: String)] = [
        ("@sveltejs/kit", "SvelteKit"),
        ("@builder.io/qwik-city", "Qwik"),
        ("@qwik.dev/router", "Qwik"),
        ("@solidjs/start", "SolidStart"),
        ("@tanstack/react-start", "TanStack Start"),
        ("@tanstack/solid-start", "TanStack Start"),
        ("@react-router/dev", "React Router"),
        ("@remix-run/dev", "Remix"),
        ("@analogjs/platform", "Analog"),
        ("vike", "Vike"),
        ("astro", "Astro"),
        ("nuxt", "Nuxt"),
    ]

    @Sendable static func viteMetaFramework(_ manifest: ManifestFacts) -> String? {
        guard manifest.kinds.contains(.packageJSON) else { return nil }
        return viteMetaFrameworks.first { manifest.dependencies.contains($0.dependency) }?.name
    }

    /// package.json dependencies, most specific first (meta-frameworks depend on vite).
    /// `scriptWord` is looked for in `scripts.dev` when no dependency matched.
    static let packageDependencies: [(dependency: String, scriptWord: String, name: String)] = [
        ("next", "next", "Next.js"),
        ("astro", "astro", "Astro"),
        ("@remix-run/*", "remix", "Remix"),
        ("@react-router/dev", "react-router", "React Router"),
        ("@sveltejs/kit", "svelte-kit", "SvelteKit"),
        ("@builder.io/qwik-city", "qwik", "Qwik"),
        ("@qwik.dev/router", "qwik", "Qwik"),
        ("@solidjs/start", "solid-start", "SolidStart"),
        ("@tanstack/react-start", "tanstack", "TanStack Start"),
        ("nuxt", "nuxt", "Nuxt"),
        ("@angular/core", "ng serve", "Angular"),
        ("gatsby", "gatsby", "Gatsby"),
        ("vite", "vite", "Vite"),
    ]

    static let rubyDependencies: [(dependency: String, name: String)] = [
        ("rails", "Rails"),
        ("sinatra", "Sinatra"),
    ]

    static let pythonDependencies: [(dependency: String, name: String)] = [
        ("django", "Django"),
        ("fastapi", "FastAPI"),
        ("flask", "Flask"),
    ]

    /// Headers that identify a server when only the runtime is known.
    static let poweredBy: [(prefix: String, name: String)] = [
        ("next.js", "Next.js"),
        ("express", "Express"),
    ]

    static let serverHeader: [(prefix: String, name: String)] = [
        ("simplehttp", "Python http.server"),
        ("werkzeug", "Flask"),
        ("uvicorn", "Uvicorn"),
        ("webrick", "WEBrick"),
        ("puma", "Puma"),
    ]
}
