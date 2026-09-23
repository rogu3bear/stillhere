import Foundation
import Testing
@testable import TermWebCore

@Suite struct FrameworkDetectorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var argv: [String]
        var name = "node"
        var exe: String?
        var cwd: String? = "/Users/dev/proj"
        var manifest: ManifestFacts?
        var expected: String
        var source: FrameworkGuess.Source = .argv

        var testDescription: String { "\(expected): \(argv.joined(separator: " "))" }
    }

    static let project = URL(fileURLWithPath: "/Users/dev/proj")
    static func manifest(_ kinds: Set<ManifestKind>, _ deps: Set<String> = [], dev: String? = nil) -> ManifestFacts {
        ManifestFacts(directory: project, kinds: kinds, dependencies: deps, devScript: dev)
    }

    static let argvCases: [Case] = [
        Case(argv: ["next-server (v15.0.0)"], expected: "Next.js"),
        Case(argv: ["node", "/p/node_modules/.bin/next", "dev"], expected: "Next.js"),
        Case(argv: ["node", "/p/node_modules/next/dist/bin/next", "start", "-p", "3000"], expected: "Next.js"),
        Case(argv: ["/usr/local/bin/node", "/Users/dev/proj/node_modules/.bin/vite"], expected: "Vite"),
        Case(argv: ["node", "/p/node_modules/vite/bin/vite.js", "--port", "5173"], expected: "Vite"),
        Case(argv: ["node", "/p/node_modules/.bin/astro", "dev"], expected: "Astro"),
        Case(argv: ["node", "/p/node_modules/.bin/remix-serve", "build/index.js"], expected: "Remix"),
        Case(argv: ["node", "/p/node_modules/.bin/react-router", "dev"], expected: "React Router"),
        Case(argv: ["node", "/p/node_modules/.bin/nuxi", "dev"], expected: "Nuxt"),
        Case(argv: ["node", "/p/node_modules/.bin/svelte-kit", "dev"], expected: "SvelteKit"),
        Case(argv: ["node", "/p/node_modules/.bin/webpack-dev-server"], expected: "webpack"),
        Case(argv: ["node", "/p/node_modules/.bin/webpack", "serve"], expected: "webpack"),
        Case(argv: ["node", "/p/node_modules/.bin/parcel", "index.html"], expected: "Parcel"),
        Case(argv: ["node", "/p/node_modules/.bin/storybook", "dev", "-p", "6006"], expected: "Storybook"),
        Case(argv: ["node", "/p/node_modules/.bin/wrangler", "dev"], expected: "Wrangler"),
        Case(argv: ["node", "/p/node_modules/.bin/ng", "serve"], expected: "Angular"),
        Case(argv: ["node", "/p/node_modules/.bin/expo", "start"], expected: "Expo"),
        Case(argv: ["node", "/p/node_modules/.bin/metro", "serve"], expected: "Metro"),
        Case(argv: ["node", "/p/node_modules/.bin/gatsby", "develop"], expected: "Gatsby"),
        Case(argv: ["node", "/p/node_modules/.bin/eleventy", "--serve"], expected: "Eleventy"),
        Case(argv: ["hugo", "server", "-D"], name: "hugo", expected: "Hugo"),
        Case(argv: ["ruby", "/usr/local/bin/jekyll", "serve"], name: "ruby", expected: "Jekyll"),
        Case(argv: ["ruby", "bin/rails", "server"], name: "ruby", expected: "Rails"),
        Case(argv: ["ruby", "bin/rails", "s", "-p", "3001"], name: "ruby", expected: "Rails"),
        Case(argv: ["puma 6.4.2 (tcp://localhost:3000) [store]"], name: "ruby", manifest: manifest([.gemfile], ["rails", "puma"]), expected: "Rails"),
        Case(argv: ["puma 6.4.2 (tcp://0.0.0.0:9292) [api]"], name: "ruby", expected: "Puma"),
        Case(argv: ["python3", "manage.py", "runserver"], name: "python3", expected: "Django"),
        Case(argv: ["/p/.venv/bin/python", "/p/.venv/bin/flask", "run"], name: "python", expected: "Flask"),
        Case(argv: ["python3", "-m", "flask", "--app", "app", "run"], name: "python3", expected: "Flask"),
        Case(argv: ["/p/.venv/bin/python", "/p/.venv/bin/uvicorn", "main:app"], name: "python", manifest: manifest([.pyproject], ["fastapi", "uvicorn"]), expected: "FastAPI"),
        Case(argv: ["python", "-m", "uvicorn", "main:app", "--reload"], name: "python", expected: "Uvicorn"),
        Case(argv: ["/p/.venv/bin/python", "/p/.venv/bin/fastapi", "dev", "main.py"], name: "python", expected: "FastAPI"),
        Case(argv: ["/p/.venv/bin/python", "/p/.venv/bin/gunicorn", "app:app"], name: "python", expected: "Gunicorn"),
        Case(argv: ["/opt/homebrew/Cellar/python@3.13/Python.app/Contents/MacOS/Python", "-m", "http.server", "8765"], name: "Python", expected: "Python http.server"),
        Case(argv: ["/p/.venv/bin/python", "/p/.venv/bin/jupyter-lab"], name: "python", expected: "Jupyter"),
        Case(argv: ["php", "-S", "localhost:8000"], name: "php", expected: "PHP built-in server"),
    ]

    @Test(arguments: argvCases)
    func argvHeuristics(_ testCase: Case) {
        let guess = FrameworkDetector.guess(FrameworkSignals(
            argv: testCase.argv, name: testCase.name, executablePath: testCase.exe,
            cwd: testCase.cwd, manifest: testCase.manifest
        ))
        #expect(guess == FrameworkGuess(name: testCase.expected, source: testCase.source))
    }

    static let manifestCases: [Case] = [
        Case(argv: ["node", "server.js"], manifest: manifest([.packageJSON], ["next", "react"]), expected: "Next.js", source: .manifest),
        Case(argv: ["node", "server.js"], manifest: manifest([.packageJSON], ["astro", "vite"]), expected: "Astro", source: .manifest),
        Case(argv: ["node", "server.js"], manifest: manifest([.packageJSON], ["@remix-run/node", "vite"]), expected: "Remix", source: .manifest),
        Case(argv: ["node", "server.js"], manifest: manifest([.packageJSON], ["@sveltejs/kit", "vite"]), expected: "SvelteKit", source: .manifest),
        Case(argv: ["node", "server.js"], manifest: manifest([.packageJSON], ["nuxt"]), expected: "Nuxt", source: .manifest),
        Case(argv: ["node", "server.js"], manifest: manifest([.packageJSON], ["@angular/core"]), expected: "Angular", source: .manifest),
        Case(argv: ["node", "server.js"], manifest: manifest([.packageJSON], ["gatsby"]), expected: "Gatsby", source: .manifest),
        Case(argv: ["node", "server.js"], manifest: manifest([.packageJSON], ["vite", "react"]), expected: "Vite", source: .manifest),
        Case(argv: ["node", "dev.mjs"], manifest: manifest([.packageJSON], ["react"], dev: "vite --host"), expected: "Vite", source: .manifest),
        Case(argv: ["ruby", "config.ru"], name: "ruby", manifest: manifest([.gemfile], ["rails"]), expected: "Rails", source: .manifest),
        Case(argv: ["ruby", "app.rb"], name: "ruby", manifest: manifest([.gemfile], ["sinatra"]), expected: "Sinatra", source: .manifest),
        Case(argv: ["python", "app.py"], name: "python", manifest: manifest([.pyproject], ["django"]), expected: "Django", source: .manifest),
        Case(argv: ["python", "app.py"], name: "python", manifest: manifest([.requirements], ["fastapi"]), expected: "FastAPI", source: .manifest),
        Case(argv: ["python", "app.py"], name: "python", manifest: manifest([.requirements], ["flask"]), expected: "Flask", source: .manifest),
        Case(argv: ["/p/bin/server"], name: "server", manifest: manifest([.cargo]), expected: "Rust", source: .manifest),
        Case(argv: ["/p/bin/server"], name: "server", manifest: manifest([.goMod]), expected: "Go", source: .manifest),
        Case(argv: ["/p/bin/server"], name: "server", manifest: manifest([.denoJSON]), expected: "Deno", source: .manifest),
        // A known runtime beats a language-only manifest.
        Case(argv: ["node", "server.js"], manifest: manifest([.cargo]), expected: "Node", source: .runtime),
    ]

    @Test(arguments: manifestCases)
    func manifestHeuristics(_ testCase: Case) {
        argvHeuristics(testCase)
    }

    static let runtimeCases: [Case] = [
        Case(argv: ["bun", "../scripts/preview-site.mjs"], name: "bun", cwd: "/Users/dev/token-bar/site", expected: "Bun", source: .runtime),
        Case(argv: ["deno", "run", "main.ts"], name: "deno", expected: "Deno", source: .runtime),
        Case(argv: ["/usr/local/bin/node", "srv.js"], expected: "Node", source: .runtime),
        Case(argv: ["python3", "serve.py"], name: "python3", expected: "Python", source: .runtime),
        Case(argv: ["ruby", "serve.rb"], name: "ruby", expected: "Ruby", source: .runtime),
        Case(argv: ["java", "-jar", "app.jar"], name: "java", expected: "Java", source: .runtime),
        Case(argv: ["target/debug/founder"], name: "founder", cwd: "/Users/dev/mln-web", expected: "Rust (cargo)", source: .runtime),
        Case(argv: [], name: "founder", exe: "/Users/dev/mln-web/target/release/founder", expected: "Rust (cargo)", source: .runtime),
        Case(argv: ["/usr/local/bin/mystery"], name: "mystery", expected: "mystery", source: .runtime),
    ]

    @Test(arguments: runtimeCases)
    func runtimeFallback(_ testCase: Case) {
        argvHeuristics(testCase)
    }

    @Test func headersRefineOnlyRuntimeGuesses() {
        let node = FrameworkGuess(name: "Node", source: .runtime)
        let python = FrameworkGuess(name: "Python", source: .runtime)
        let ruby = FrameworkGuess(name: "Ruby", source: .runtime)
        func probe(server: String? = nil, poweredBy: String? = nil) -> ProbeResult {
            ProbeResult(host: "127.0.0.1", status: 200, serverHeader: server, poweredBy: poweredBy)
        }
        #expect(FrameworkDetector.refine(node, with: probe(poweredBy: "Next.js")) == FrameworkGuess(name: "Next.js", source: .header))
        #expect(FrameworkDetector.refine(node, with: probe(poweredBy: "Express")) == FrameworkGuess(name: "Express", source: .header))
        #expect(FrameworkDetector.refine(python, with: probe(server: "SimpleHTTP/0.6 Python/3.13.0")).name == "Python http.server")
        #expect(FrameworkDetector.refine(python, with: probe(server: "Werkzeug/3.0.1 Python/3.13.0")).name == "Flask")
        #expect(FrameworkDetector.refine(python, with: probe(server: "uvicorn")).name == "Uvicorn")
        #expect(FrameworkDetector.refine(ruby, with: probe(server: "WEBrick/1.8.1 (Ruby/3.3.0)")).name == "WEBrick")
        #expect(FrameworkDetector.refine(ruby, with: probe(server: "Puma 6.4")).name == "Puma")
        let vite = FrameworkGuess(name: "Vite", source: .argv)
        #expect(FrameworkDetector.refine(vite, with: probe(poweredBy: "Express")) == vite)
        #expect(FrameworkDetector.refine(node, with: probe(server: "nginx")) == node)
    }
}
