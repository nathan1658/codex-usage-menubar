import Foundation

func expandTilde(_ path: String) -> String {
    guard path == "~" || path.hasPrefix("~/") else {
        return path
    }

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == "~" {
        return home
    }

    return home + String(path.dropFirst())
}

func abbreviatedHomePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path == home || path.hasPrefix(home + "/") else {
        return path
    }

    if path == home {
        return "~"
    }

    return "~" + String(path.dropFirst(home.count))
}
