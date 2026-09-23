import Foundation
import Testing
@testable import TermWebCore

@Suite struct ManifestReaderTests {
    @Test func readsPackageJSONGemfileAndPython() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try #"{"dependencies":{"React":"^19"},"devDependencies":{"vite":"^6"},"scripts":{"dev":"vite --host"}}"#
            .write(to: dir.appending(path: "package.json"), atomically: true, encoding: .utf8)
        try "source 'https://rubygems.org'\ngem \"rails\", \"~> 8.0\"\n  gem 'puma'\n# gem 'ignored'\n"
            .write(to: dir.appending(path: "Gemfile"), atomically: true, encoding: .utf8)
        try "[project]\ndependencies = [\"fastapi[standard]>=0.115\", \"Django==5.1\"]\n"
            .write(to: dir.appending(path: "pyproject.toml"), atomically: true, encoding: .utf8)

        let facts = await ManifestReader().facts(in: dir)
        #expect(facts.kinds == [.packageJSON, .gemfile, .pyproject])
        #expect(facts.devScript == "vite --host")
        for name in ["react", "vite", "rails", "puma", "fastapi", "django"] {
            #expect(facts.dependencies.contains(name), "missing \(name)")
        }
        #expect(!facts.dependencies.contains("ignored"))
    }

    @Test func cachesUntilModificationDateChanges() async throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "package.json")
        try #"{"dependencies":{"vite":"1"}}"#.write(to: file, atomically: true, encoding: .utf8)
        let reader = ManifestReader()

        #expect(await reader.facts(in: dir).dependencies == ["vite"])
        #expect(await reader.facts(in: dir).dependencies == ["vite"])
        #expect(await reader.readCount == 1)

        try #"{"dependencies":{"next":"1"}}"#.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        #expect(await reader.facts(in: dir).dependencies == ["next"])
        #expect(await reader.readCount == 2)
    }

    @Test func malformedPackageJSONYieldsNoDependencies() {
        let parsed = ManifestReader.parsePackageJSON(Data("{not json".utf8))
        #expect(parsed.dependencies.isEmpty)
        #expect(parsed.devScript == nil)
    }

    @Test func locatorWalksUpToNearestManifest() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appending(path: "dev/app")
        let nested = project.appending(path: "src/server")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "{}".write(to: project.appending(path: "package.json"), atomically: true, encoding: .utf8)

        #expect(ManifestLocator.locate(from: nested.path, home: home.path)?.path == project.standardizedFileURL.path)
        #expect(ManifestLocator.locate(from: project.path, home: home.path)?.path == project.standardizedFileURL.path)
    }

    @Test func locatorStopsAtGitRootAndHome() throws {
        let home = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        try "{}".write(to: home.appending(path: "package.json"), atomically: true, encoding: .utf8)
        let repo = home.appending(path: "repo")
        let inner = repo.appending(path: "docs")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: repo.appending(path: ".git"), withIntermediateDirectories: true)

        // The repo has no manifest; the walk stops at its .git root instead of reaching $HOME's package.json.
        #expect(ManifestLocator.locate(from: inner.path, home: "/nonexistent-home") == nil)
        // A manifest-free folder directly under home stops at home.
        let loose = home.appending(path: "loose")
        try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
        #expect(ManifestLocator.locate(from: loose.path, home: home.path) == nil)
        #expect(ManifestLocator.locate(from: "/", home: home.path) == nil)
    }
}
