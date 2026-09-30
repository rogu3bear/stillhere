/// Pure parser for `lsof -a -p PIDS -d cwd -Fn`: `p<pid>`, `fcwd`, `n<path>`.
public enum LsofCwdParser {
    public static func parse(_ text: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var pid: Int32?
        for line in text.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value)
            case "n":
                if let pid, !value.isEmpty, result[pid] == nil { result[pid] = value }
            default: continue
            }
        }
        return result
    }
}
