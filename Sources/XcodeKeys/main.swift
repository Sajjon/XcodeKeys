import Foundation

struct AnyError: Error, CustomStringConvertible {
    let description: String
}
extension String {
    func intoError() -> Error {
        AnyError(description: self)
    }
}

typealias Plist = [String: Any]

func plistFromData(
    _ plistData: Data,
    format: PropertyListSerialization.PropertyListFormat = .xml
) throws -> Plist {
    var formatMut = format
    let plistAny: Any
    
    do {
        plistAny = try PropertyListSerialization.propertyList(
        from: plistData,
        options: .mutableContainersAndLeaves,
        format: &formatMut)
    } catch let error {
        throw "Failed to read plist file, underlying error: \(String(describing: error))".intoError()
    }
    
    guard let plist = plistAny as? Plist else {
        throw "Failed to cast plist value into dictionary".intoError()
    }
    
    return plist
}

func openPlist(
    at nonExpandedPath: String,
    fileManager: FileManager = .default,
    format: PropertyListSerialization.PropertyListFormat = .xml
) throws -> (plist: Plist, path: String)  {
    let path = NSString(string: nonExpandedPath).expandingTildeInPath
    guard let plistData = fileManager.contents(atPath: path) else {
        throw "No plist file found at path: \(path)".intoError()
    }
    
    let plist = try plistFromData(plistData, format: format)
    
    return (plist, path)
    
}

func writeFile(data contents: Data, to path: String, fileManager: FileManager = .default) throws -> SimpleFile {
    
    /*
     From discussion part of API documentation:
     `If a file already exists at path, this method overwrites the contents of that file if the current process has the appropriate privileges to do so.`
     */
    guard fileManager.createFile(
        atPath: path,
        contents: contents,
        attributes: nil
    ) else {
        throw "Failed to write file data to: '\(path)'".intoError()
    }
    
    return .init(url: .init(fileURLWithPath: path), data: contents)
}

func write(
    plist: Plist,
    to plistPath: String,
    fileManager: FileManager = .default,
    format: PropertyListSerialization.PropertyListFormat = .xml,
    options: PropertyListSerialization.WriteOptions = 0
) throws -> SimpleFile {
    
    let plistData = try PropertyListSerialization.data(
        fromPropertyList: plist,
        format: format,
        options: options
    )

    return try writeFile(data: plistData, to: plistPath, fileManager: fileManager)
}

protocol XcodeKey {
    var xcodeValue: String { get }
    var humanReadable: String { get }
}

extension XcodeKey {
    var xcodeValue: String { humanReadable }
}

extension Character: XcodeKey {
    var humanReadable: String {
        String(describing: self)
    }
}

struct Shortcut: CustomStringConvertible {
    enum Key: XcodeKey {
        enum Modifier: XcodeKey {
            case command
            case shift
            var xcodeValue: String {
                switch self {
                case .command: return "@"
                case .shift: return "$"
                }
            }
            var humanReadable: String {
                switch self {
                case .command: return "CMD"
                case .shift: return "SHIFT"
                }
            }
        }
        case modifier(Modifier), character(Character)
        
        var xcodeValue: String {
            switch self {
            case .modifier(let modifier): return modifier.xcodeValue
            case .character(let character): return character.xcodeValue
            }
        }
        
        var humanReadable: String {
            switch self {
            case .modifier(let modifier): return modifier.humanReadable
            case .character(let character): return character.humanReadable
            }
        }
    }
    private let keys: [Key]
    init(keys: [Key]) {
        self.keys = keys
    }
    
    var description: String {
        keys.map { $0.humanReadable }.joined(separator: "+")
    }
    
    var value: String { keys.map { $0.xcodeValue }.joined(separator: "") }
}

enum Instruction: String {
    case moveToBeginningOfLine = "moveToBeginningOfLine"
    case deleteToEndOfLine = "deleteToEndOfLine"
    case yank = "yank"
    case insertNewline = "insertNewline"
    case selectLine = "selectLine"
    case deleteBackward = "deleteBackward"
    case moveToEndOfLine = "moveToEndOfLine"
}

struct XcodeCommand: CustomStringConvertible {
    let name: String
    private let instructions: [Instruction]
    private let shortcut: Shortcut
    
    init(name: String, instructions: [Instruction], shortcut: Shortcut) {
        self.name = name
        self.instructions = instructions
        self.shortcut = shortcut
    }
    
    /// Convenience
    init(name: String, instructions: [Instruction], keys: [Shortcut.Key]) {
        self.init(name: name, instructions: instructions, shortcut: .init(keys: keys))
    }
    
    var instructionsValue: String { instructions.map { $0.rawValue + ":" }.joined(separator: ", ") }

    var instructionsValues: [String] { instructions.map { $0.rawValue + ":" } }
    var shortcutValue: String { shortcut.value }

    var description: String {
        "\(name): \(shortcut)"
    }
}


func createKeyBindings(
    newCommands: [XcodeCommand],
    customizedDictionaryName: String = "Customized",
    fileManager: FileManager = .default
) throws -> SimpleFile {
    
    let nonExpandedAvailableBindingsPath = "/Applications/Xcode.app/Contents/Frameworks/IDEKit.framework/Resources/IDETextKeyBindingSet.plist"

    let format: PropertyListSerialization.PropertyListFormat = .xml
    
    var (bindingsPlist, bindingsPath) = try openPlist(
        at: nonExpandedAvailableBindingsPath,
        format: format
    )
    
    let secondaryCustomized = (bindingsPlist[customizedDictionaryName] as? Plist) ?? [:]
    
    let mainCustomized = Plist(uniqueKeysWithValues: newCommands.map { command in
        (key: command.name, value: command.instructionsValue)
    })
    
    // Merge
    let mergedCustomized = mainCustomized.merging(secondaryCustomized) { (current, _) in current }
    bindingsPlist[customizedDictionaryName] = mergedCustomized
    
    let writtenFile = try write(plist: bindingsPlist, to: bindingsPath)
    
    return writtenFile
}


import Swiftline

struct SimpleFile: Equatable {
    let url: URL
    let data: Data
}
extension SimpleFile {
    var path: String {
        url.path
    }
}

extension SimpleFile {
    static func at(url: URL, fileManager: FileManager = .default) throws -> Self {
        guard fileManager.fileExists(atPath: url.path) else {
            throw "Plist not found".intoError()
        }
        
        guard let data = fileManager.contents(atPath: url.path) else {
            fatalError("File was not found. But earlier check said it does.")
        }
        
        return Self(url: url, data: data)
    }
    
    static func at(path: String, fileManager: FileManager = .default) throws -> Self {
        try .at(url: URL(fileURLWithPath: path), fileManager: fileManager)
    }
}

func defaultBindingsFile(fileManager: FileManager = .default) throws -> SimpleFile {
    
    // When building this SPM package from Xcode you will see a false error: `Type 'Bundle' has no member 'module'`
    // this is relating to this bug: https://bugs.swift.org/browse/SR-13773
    let bundle: Bundle = .module
    
    guard let sourceURL = bundle.url(forResource: "Default", withExtension: "idekeybindings") else {
        throw "Source bindings not found".intoError()
    }
    return try .at(url: sourceURL, fileManager: fileManager)
}


func targetBindingsFilePath(fileManager: FileManager = .default) throws -> String {
    let defaultBindingsFile = try defaultBindingsFile(fileManager: fileManager)
    let targetDirectory =  NSString("~/Library/Developer/Xcode/UserData/KeyBindings").expandingTildeInPath
    let targetPath = targetDirectory.appending("/").appending(URL(fileURLWithPath: defaultBindingsFile.path).lastPathComponent)
    return targetPath
}

func provideDefaultPlistIfNeeded(
    fileManager: FileManager = .default,
    promptUserForOverrideConfirmation: (String) -> Bool
) throws -> SimpleFile {
    
    let sourceFile = try defaultBindingsFile(fileManager: fileManager)
    
    let targetPath = try targetBindingsFilePath(fileManager: fileManager)
    
    if let existingData = fileManager.contents(atPath: targetPath) {
        if existingData != sourceFile.data {
            guard promptUserForOverrideConfirmation("\n⚠️  Earlier and DIFFERENT key bindings found at: '\(targetPath)'\nAre you sure you want to proceed? [Y\n]") else {
                throw "Aborted overriding of existing binding".intoError()
            }
            print("☑️  Overriden earlier key bindings.")
        } else {
            return .init(url: .init(fileURLWithPath: targetPath), data: existingData)
        }
    }
    
    return try writeFile(data: sourceFile.data, to: targetPath, fileManager: fileManager)
}

func setKeys(
    newCommands: [XcodeCommand],
    username: String? = nil,
    fileManager: FileManager = .default,
    promptUserForOverrideConfirmation: (String) -> Bool
) throws -> SimpleFile {
    
    let plistFile = try provideDefaultPlistIfNeeded(fileManager: fileManager, promptUserForOverrideConfirmation: promptUserForOverrideConfirmation)
    
    let format: PropertyListSerialization.PropertyListFormat = .xml

    var plist = try plistFromData(plistFile.data, format: format)
    let keyMeta = "Text Key Bindings"
    
    guard var textKeyBindingsMeta = plist[keyMeta] as? Plist else {
        throw "Failed to get text key bindings meta".intoError()
    }
    
    let keyBindings = "Key Bindings"
  
    guard var textKeyBindings = textKeyBindingsMeta[keyBindings] as? Plist else {
        throw "Failed to get text key bindings".intoError()
    }
    
    newCommands.forEach { command in
        textKeyBindings[command.shortcutValue] = command.instructionsValues
    }
    
    textKeyBindingsMeta[keyBindings] = textKeyBindings
    plist[keyMeta] = textKeyBindingsMeta
    
    try fileManager.removeItem(atPath: plistFile.path)
    let writtenFile = try write(plist: plist, to: plistFile.path)
    return writtenFile
}

func newCommands() -> [XcodeCommand] {
    let duplicateCurrentLine = XcodeCommand(
        name: "Duplicate current line",
        instructions: [
            .moveToBeginningOfLine,
            .deleteToEndOfLine,
            .yank,
            .insertNewline,
            .moveToBeginningOfLine,
            .yank
        ], shortcut: .init(keys: [
            .modifier(.command),
            .character("d")
        ])
    )
    
    let deleteCurrentLine = XcodeCommand(
        name: "Delete current line",
        instructions: [
            .selectLine,
            .deleteBackward
            // .moveToEndOfLine
        ], shortcut: .init(keys: [
            .modifier(.shift),
            .modifier(.command),
            .character("D")
        ])
    )
    
   return [duplicateCurrentLine, deleteCurrentLine]
   
}

func run(
    commands newCommands: [XcodeCommand]
) throws {

    _ = try createKeyBindings(
        newCommands: newCommands
    )
    
    _ = try setKeys(
        newCommands: newCommands,
        promptUserForOverrideConfirmation: {
            agree($0)
        }
    )

    print("✅ finished adding Xcode commands with shortcuts: \(newCommands)")
}

try run(commands: newCommands())
