import Foundation
import UniformTypeIdentifiers
public enum BuiltinRules {
    public static func catalog(localeIdentifier: String = "en") -> [Rule] {
        let categories: [(String, [String], String?)] = [
            ("3D Models", ["obj","fbx","gltf","glb","stl","blend","usd","usdz","usda","usdc","dae","3ds","c4d"], nil),
            ("Audio", ["mp3","wav","aiff","aif","m4a","flac","ogg","aac","wma","mid","midi"], "public.audio"),
            ("Bookmarks", ["webloc","url"], nil),
            ("Developer Files", ["xcodeproj","xcworkspace","playground","framework","xcassets"], nil),
            ("Disk Images", ["dmg","iso","img","sparseimage","sparsebundle"], "public.disk-image"),
            ("eBooks", ["epub","mobi","azw","azw3","fb2"], nil),
            ("Emails", ["eml","emlx","msg","mbox"], nil),
            ("Fonts", ["ttf","otf","woff","woff2","dfont","ttc"], "public.font"),
            ("Images", ["png","jpg","jpeg","heic","heif","gif","webp","tif","tiff","bmp","svg","psd","ai","eps","avif","raw","cr2","nef","exr"], "public.image"),
            ("Markdown", ["md","markdown","mdown"], nil),
            ("Movies", ["mov","mp4","m4v","mkv","avi","webm","mpeg","mpg"], "public.movie"),
            ("PDFs", ["pdf"], "com.adobe.pdf"),
            ("PowerPoint", ["ppt","pptx","pps","ppsx"], nil),
            ("Presentations", ["key","odp"], "public.presentation"),
            ("Scripts", ["sh","bash","zsh","command","scpt","applescript","bat","ps1"], "public.script"),
            ("Source Code", ["swift","c","cpp","h","hpp","m","mm","py","js","ts","tsx","jsx","rs","go","java","kt","rb","php","html","css","sql"], "public.source-code"),
            ("Spreadsheets", ["xlsx","xls","numbers","csv","tsv","ods"], "public.spreadsheet"),
            ("Text Files", ["txt","rtf","log","json","yaml","yml","xml","toml","ini","conf"], "public.text"),
            ("Word Processing", ["doc","docx","pages","odt"], nil),
            ("Zip & Archives", ["zip","7z","rar","tar","gz","bz2","xz","zst","tgz","pkg"], "public.archive")
        ]
        var result = categories.enumerated().map { index, entry in
            var nodes = entry.1.map { RuleNode.condition(.init(field: .fileExtension, comparison: .equals, value: $0)) }
            if let type = entry.2 { nodes.append(.condition(.init(field: .type, comparison: .equals, value: type))) }
            return Rule(id: stableID(index), name: entry.0, destination: entry.0, group: .init(mode: .any, children: nodes), builtin: true)
        }
        result.append(Rule(id: stableID(20), name: "Unknown", destination: "Unknown", group: .init(children: [.condition(.init(field: .kind, comparison: .equals, value: "regularFile"))]), builtin: true))
        for (offset, kind, name) in [(21, "directory", "Folders"), (22, "alias", "Aliases")] {
            result.append(Rule(id: stableID(offset), name: name, enabled: false, destination: name, group: .init(children: [.condition(.init(field: .kind, comparison: .equals, value: kind))]), builtin: true))
        }
        return result
    }
    private static func stableID(_ index: Int) -> UUID { UUID(uuidString: String(format: "54494459-0000-4000-8000-%012d", index + 1))! }
    public static func settingEnabled(_ rules: [Rule], enabled: Bool) -> [Rule] {
        rules.map { r in var r = r; r.enabled = enabled && !(r.builtin && ["Folders", "Aliases"].contains(r.name)); return r }
    }
}
public enum FileTypeClassifier {
    public static func typeIdentifier(forExtension ext: String) -> String? { UTType(filenameExtension: ext.lowercased())?.identifier }
}
