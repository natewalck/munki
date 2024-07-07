//
//  pkgutils.swift
//  munki
//
//  Created by Greg Neagle on 7/2/24.
//

import Foundation

func getPkgRestartInfo(_ pkgpath: String) -> PlistDict {
    var installerinfo = PlistDict()
    let results = runCLI(
        "/usr/sbin/installer",
        arguments: ["-query", "RestartAction",
                   "-pkg", pkgpath,
                   "-plist"]
    )
    if results.exitcode != 0 {
        displayError("installer -query for \(pkgpath) failed: \(results.error)")
        return installerinfo
    }
    let (pliststr, _) = parseFirstPlist(fromString: results.output)
    if !pliststr.isEmpty {
        if let plist = try? readPlistFromString(pliststr) as? PlistDict {
            if let restartAction = plist["RestartAction"] as? String {
                if restartAction != "None" {
                    installerinfo["RestartAction"] = restartAction
                }
            }
        }
    }
    return installerinfo
}


func getVersionString(plist: PlistDict, key: String = "") -> String {
    // Gets a version string from the plist.
    //
    // If a key is explicitly specified, the string value of that key is returned
    // without modification, or an empty string if the key does not exist or the value
    // is not a string.
    //
    // If key is not specified:
    // if there"s a valid CFBundleShortVersionString, returns that.
    // else if there"s a CFBundleVersion, returns that
    // else returns an empty string.
    
    if !key.isEmpty {
        return plist[key] as? String ?? ""
    }
    for aKey in ["CFBundleShortVersionString", "CFBundleVersion"] {
        if let version = plist[aKey] as? String {
            return version
        }
    }
    return ""
}

// MARK: bundle functions

func getBundleInfo(_ bundlepath: String) -> PlistDict? {
    // Returns Info.plist data if available for bundle at bundlepath
    var infopath = (bundlepath as NSString).appendingPathComponent("Contents/Info.plist")
    let filemanager = FileManager.default
    if !filemanager.fileExists(atPath: infopath) {
        infopath = (bundlepath as NSString).appendingPathComponent("Resources/Info.plist")
    }
    if filemanager.fileExists(atPath: infopath) {
        return try? readPlist(infopath) as? PlistDict
    }
    return nil
}


func getAppBundleExecutable(_ bundlepath: String) -> String {
    // Returns path to the actual executable in an app bundle or empty string
    var executableName = (bundlepath as NSString).lastPathComponent
    executableName = (executableName as NSString).deletingPathExtension
    if let plist = getBundleInfo(bundlepath) {
        if let cfBundleExecutable = plist["CFBundleExecutable"] as? String {
            executableName = cfBundleExecutable
        } else if let cfBundleName = plist["CFBundleName"] as? String {
            executableName = cfBundleName
        }
    }
    var executablePath = (bundlepath as NSString).appendingPathComponent("Contents/MacOS")
    executablePath = (executablePath as NSString).appendingPathComponent(executableName)
    if FileManager.default.fileExists(atPath: executablePath) {
        return executablePath
    }
    return ""
}


func parseInfoFileText(_ text: String) -> [String:String] {
    var info = [String:String]()
    for line in text.components(separatedBy: .newlines) {
        let parts = line.components(separatedBy: .whitespaces)
        if parts.count > 1 {
            let key = parts[0]
            let value = parts[1...].joined(separator: " ")
            info[key] = value
        }
    }
    return info
}


func parseInfoFile(_ infofilepath: String) -> PlistDict {
    // parses an ancient data format in old bundle-style packages
    // and returns a PlistDict
    if let filedata = NSData(contentsOfFile: infofilepath) {
        if let filetext = String(data: filedata as Data, encoding: .macOSRoman) {
            return parseInfoFileText(filetext)
        } else if let filetext = String(data: filedata as Data, encoding: .utf8) {
            return parseInfoFileText(filetext)
        }
    }
    return PlistDict()
}

func getOldStyleInfoFile(_ bundlepath: String) -> String? {
    // returns a path to an old-style .info file inside the
    // bundle if present
    let infopath = (bundlepath as NSString).appendingPathComponent("Contents/Resources/English.lproj")
    if pathIsDirectory(infopath) {
        let filemanager = FileManager.default
        if let dirlist = try? filemanager.contentsOfDirectory(atPath: infopath) {
            for item in dirlist {
                if item.hasSuffix(".info") {
                    return (infopath as NSString).appendingPathComponent(item)
                }
            }
        }
    }
    return nil
}


func getBundleVersion(_ bundlepath: String, key: String = "") -> String {
    // Returns version number from a bundle.
    // Some extra code to deal with very old-style bundle packages
    //
    // Specify key to use a specific key in the Info.plist for the version string.
    
    if let plist = getBundleInfo(bundlepath) {
        let version = getVersionString(plist: plist, key: key)
        if !version.isEmpty {
            return version
        }
    }
    // no version number in Info.plist. Maybe old-style package?
    if let infofile = getOldStyleInfoFile(bundlepath) {
        let info = parseInfoFile(infofile)
        if let version = info["Version"] as? String {
            return version
        }
    }
    return ""
}

func getBomList(_ pkgpath: String) -> [String] {
    // Gets bom listing from pkgpath, which should be a path
    // to a bundle-style package
    // Returns a list of strings
    let contentsPath = (pkgpath as NSString).appendingPathComponent("Contents")
    if pathIsDirectory(contentsPath) {
        let filemanager = FileManager.default
        if let dirlist = try? filemanager.contentsOfDirectory(atPath: contentsPath) {
            for item in dirlist {
                if item.hasSuffix(".bom") {
                    let bompath = (contentsPath as NSString).appendingPathComponent(item)
                    let results = runCLI(
                        "/usr/bin/lsbom", arguments: ["-s", bompath])
                    if results.exitcode == 0 {
                        return results.output.components(separatedBy: .newlines)
                    }
                    break
                }
            }
        }
    }
    return [String]()
}

func getSinglePkgReceipt(_ pkgpath: String) -> PlistDict {
    // returns receipt info for a single bundle-style package
    var receipt = PlistDict()
    let pkgname = (pkgpath as NSString).lastPathComponent
    if let plist = getBundleInfo(pkgpath) {
        receipt["filename"] = pkgname
        if let identifier = plist["CFBundleIdentifier"] as? String {
            receipt["packageid"] = identifier
        } else if let identifier = plist["Bundle identifier"] as? String {
            receipt["packageid"] = identifier
        } else {
            receipt["packageid"] = pkgname
        }
        if let name = plist["CFBundleName"] as? String {
            receipt["name"] = name
        }
        if let installedSize = plist["IFPkgFlagInstalledSize"] as? Int {
            receipt["installed_size"] = installedSize
        }
        receipt["version"] = getBundleVersion(pkgpath)
    } else {
        // look for really old-style .info file
        if let infofile = getOldStyleInfoFile(pkgpath) {
            let info = parseInfoFile(infofile)
            receipt["version"] = info["Version"] as? String ?? "0.0"
            receipt["name"] = info["Title"] as? String ?? pkgname
            receipt["packageid"] = pkgname
            receipt["filename"] = pkgname
        }
    }
    return receipt
}

func getBundlePackageInfo(_ pkgpath: String) -> PlistDict {
    // get metadate from a bundle-style package
    var receiptarray = [PlistDict]()
    if pkgpath.hasSuffix(".pkg") {
        // try to get info as if this is a single component pkg
        let receipt = getSinglePkgReceipt(pkgpath)
        if !receipt.isEmpty {
            receiptarray.append(receipt)
            return ["receipts": receiptarray]
        }
    }
    // might be a mpkg
    let contentsPath = (pkgpath as NSString).appendingPathComponent("Contents")
    let filemanager = FileManager.default
    if pathIsDirectory(contentsPath) {
        if let dirlist = try? filemanager.contentsOfDirectory(atPath: contentsPath) {
            for item in dirlist {
                if item.hasSuffix(".dist") {
                    let distfilepath = (contentsPath as NSString).appendingPathComponent(item)
                    let receiptarray = receiptsFromDistFile(distfilepath)
                    return ["receipts": receiptarray]
                }
            }
        }
        // no .dist file found; let"s look for subpackages
        var searchDirs = [String]()
        if let info = getBundleInfo(pkgpath) {
            if let componentDir = info["IFPkgFlagComponentDirectory"] as? String {
                searchDirs.append(componentDir)
            }
        }
        if searchDirs.isEmpty {
            searchDirs = ["", "Contents", "Contents/Installers",
                            "Contents/Packages", "Contents/Resources",
                            "Contents/Resources/Packages"]
        }
        for dir in searchDirs {
            let searchDir = (pkgpath as NSString).appendingPathComponent(dir)
            guard pathIsDirectory(searchDir) else { continue }
            guard let dirlist = try? filemanager.contentsOfDirectory(atPath: searchDir) else { continue }
            for item in dirlist {
                let itempath = (searchDir as NSString).appendingPathComponent(item)
                guard pathIsDirectory(itempath) else { continue }
                if itempath.hasSuffix(".pkg") {
                    let receipt = getSinglePkgReceipt(itempath)
                    if !receipt.isEmpty {
                        receiptarray.append(receipt)
                    }
                } else if itempath.hasSuffix(".mpkg") {
                    let info = getBundlePackageInfo(itempath)
                    if !info.isEmpty {
                        if let receipts = info["receipts"] as? [PlistDict] {
                            receiptarray += receipts
                        }
                    }
                }
            }
        }
    }
    return ["receipts": receiptarray]
}


// MARK: XML file functions (mostly for flat packages)

func getProductVersionFromDist(_ filepath: String) -> String {
    // Extracts product version from a Distribution file
    guard let data = NSData(contentsOfFile: filepath) else { return "" }
    guard let doc = try? XMLDocument(data: data as Data, options: []) else { return "" }
    guard let products = try? doc.nodes(forXPath: "//product") else { return "" }
    guard let product = products[0] as? XMLElement else { return "" }
    guard let versionAttr = product.attribute(forName: "version") else { return "" }
    return versionAttr.stringValue ?? ""
}

func getMinOSVersFromDist(_ filepath: String) -> String {
    // attempts to get a minimum os version
    guard let data = NSData(contentsOfFile: filepath) else { return "" }
    guard let doc = try? XMLDocument(data: data as Data, options: []) else { return "" }
    guard let volumeChecks = try? doc.nodes(forXPath: "//volume-check") else { return "" }
    guard let allowedOSVersions = try? volumeChecks[0].nodes(forXPath: "child::allowed-os-versions") else { return "" }
    guard let osVersions = try? allowedOSVersions[0].nodes(forXPath: "child::os-version") else { return "" }
    var minOSVersionStrings = [String]()
    for osVersion in osVersions {
        guard let element = osVersion as? XMLElement else { continue }
        if let minAttr = element.attribute(forName: "min") {
            if let os = minAttr.stringValue {
                minOSVersionStrings.append(os)
            }
        }
    }
    // if there's more than one, use the highest minimum OS
    let versions = minOSVersionStrings.map( { MunkiVersion($0) })
    if let maxVersion = versions.max() {
        return maxVersion.value
    }
    return ""
}


func receiptFromPackageInfoFile(_ filepath: String) -> PlistDict {
    // parses a PackageInfo file and returns a package receipt
    // No official Apple documentation on the format of this file, but
    // http://s.sudre.free.fr/Stuff/Ivanhoe/FLAT.html has some
    guard let data = NSData(contentsOfFile: filepath) else { return PlistDict() }
    guard let doc = try? XMLDocument(data: data as Data, options: []) else { return PlistDict() }
    guard let nodes = try? doc.nodes(forXPath: "//pkg-info") else { return PlistDict() }
    for node in nodes {
        guard let element = node as? XMLElement else { continue }
        if let identifierAttr = element.attribute(forName: "identifier"),
           let versionAttr = element.attribute(forName: "version") {
            var pkginfo = PlistDict()
            if let identifier = identifierAttr.stringValue {
                pkginfo["packageid"] = identifier
            }
            if let version = versionAttr.stringValue {
                pkginfo["version"] = version
            }
            if let payloads = try? element.nodes(forXPath: "child::payload") {
                guard let payload = payloads[0] as? XMLElement else { continue }
                if let sizeAttr = payload.attribute(forName: "installKBytes") {
                    if let size = sizeAttr.stringValue {
                        pkginfo["installed_size"] = Int(size)
                    }
                }
                return pkginfo
            }
        }
    }
    return PlistDict()
}


func partialFileURLToRelativePath(_ partialURL: String) -> String {
    //
    // converts the partial file urls found in Distribution pkg-refs
    // to relative file paths
    // TODO: handle pkg-ref content that starts with "file:"
    
    var temp = partialURL
    if temp.hasPrefix("#") {
        temp.removeFirst()
    }
    let fileurl = URL(string: "file:///")
    if let url = URL(string: temp, relativeTo: fileurl) {
        return url.relativePath
    }
    // fallback in case that failed
    return temp.removingPercentEncoding ?? ""
}


func receiptsFromDistFile(_ filepath: String) -> [PlistDict] {
    // parses a package Distribution file and returns a list of
    // package receipts
    /* https://developer.apple.com/library/archive/documentation/DeveloperTools/Reference/DistributionDefinitionRef/Chapters/Distribution_XML_Ref.html
    */
    var info = [PlistDict]()
    var pkgrefDict = [String:PlistDict]()
    guard let data = NSData(contentsOfFile: filepath) else { return info }
    guard let doc = try? XMLDocument(data: data as Data, options: []) else {
        return info
    }
    guard let nodes = try? doc.nodes(forXPath: "//pkg-ref") else {
        return info
    }
    for node in nodes {
        guard let element = node as? XMLElement else { continue }
        guard let idAttr = element.attribute(forName: "id") else { continue }
        if let pkgid = idAttr.stringValue {
            if !pkgrefDict.keys.contains(pkgid) {
                pkgrefDict[pkgid] = ["packageid": pkgid]
            }
            if let versAttr = element.attribute(forName: "version") {
                if let version = versAttr.stringValue {
                    pkgrefDict[pkgid]?["version"] = version
                }
            }
            if let sizeAttr = element.attribute(forName: "installKBytes") {
                if let size = sizeAttr.stringValue {
                    pkgrefDict[pkgid]?["installed_size"] = Int(size)
                }
            }
            element.normalizeAdjacentTextNodesPreservingCDATA(false)
            var textvalue = ""
            if let textnodes = try? element.nodes(forXPath: "child::text()") {
                for textnode in textnodes {
                    if let str = textnode.stringValue {
                        textvalue += str
                    }
                }
            }
            if !textvalue.isEmpty {
                pkgrefDict[pkgid]?["file"] = partialFileURLToRelativePath(textvalue)
            }
        }
    }
    for pkgref in pkgrefDict.values {
        if pkgref.keys.contains("file") && pkgref.keys.contains("version") {
            var receipt = pkgref
            receipt["file"] = nil
            info.append(receipt)
        }
    }
    return info
}

// MARK: flat pkg methods

func getAbsolutePath(_ path: String) -> String {
    // returns absolute path to item referred to by path
    if (path as NSString).isAbsolutePath {
        return path
    }
    let cwd = FileManager.default.currentDirectoryPath
    let composedPath = (cwd as NSString).appendingPathComponent(path)
    return (composedPath as NSString).standardizingPath
}


func getFlatPackageInfo(_ pkgpath: String) -> PlistDict {
    // returns info for a flat package, including receipts array
    var info = PlistDict()
    var receiptarray = [PlistDict]()
    var productVersion = ""
    var minimumOSVersion = ""
    
    // get the absolute path to the pkg because we need to do a chdir later
    let absolutePkgPath = getAbsolutePath(pkgpath)
    // make a tmp dir to expand the flat package into
    guard let pkgTmpDir = TempDir.shared.makeTempDir() else { return info }
    // record our current working dir
    let filemanager = FileManager.default
    let cwd = filemanager.currentDirectoryPath
    // change into our tmpdir so we can use xar to unarchive the flat package
    filemanager.changeCurrentDirectoryPath(pkgTmpDir)
    // Get the TOC of the flat pkg so we can search it later
    let tocResults = runCLI("/usr/bin/xar", arguments: ["-tf", absolutePkgPath])
    if tocResults.exitcode == 0  {
        let tocEntries = tocResults.output.components(separatedBy: .newlines)
        for tocEntry in tocEntries {
            if tocEntry.hasSuffix("PackageInfo") {
                let extractResults = runCLI(
                    "/usr/bin/xar", arguments: ["-xf", absolutePkgPath, tocEntry])
                if extractResults.exitcode == 0 {
                    let packageInfoPath = getAbsolutePath(
                        (pkgTmpDir as NSString).appendingPathComponent(tocEntry))
                    receiptarray.append( receiptFromPackageInfoFile(packageInfoPath))
                } else {
                    displayWarning(
                        "An error occurred while extracting \(tocEntry): \(tocResults.error)")
                }
            }
        }
        // now get data from a Distribution file
        for tocEntry in tocEntries {
            if tocEntry.hasSuffix("Distribution") {
                let extractResults = runCLI(
                    "/usr/bin/xar", arguments: ["-xf", absolutePkgPath, tocEntry])
                if extractResults.exitcode == 0 {
                    let distributionPath = getAbsolutePath(
                        (pkgTmpDir as NSString).appendingPathComponent(tocEntry))
                    productVersion = getProductVersionFromDist(distributionPath)
                    minimumOSVersion = getMinOSVersFromDist(distributionPath)
                    if receiptarray.isEmpty {
                        receiptarray = receiptsFromDistFile(distributionPath)
                    }
                    break
                } else {
                    displayWarning(
                        "An error occurred while extracting \(tocEntry): \(tocResults.error)")
                }
            }
        }
        
        if receiptarray.isEmpty {
            displayWarning("No receipts found in Distribution or PackageInfo files within the package.")
        }
    } else {
        displayWarning(
            "An error occurred while geting table of contents for \(pkgpath): \(tocResults.error)")
    }
    // change back to original working dir
    filemanager.changeCurrentDirectoryPath(cwd)
    // clean up tmpdir
    try? filemanager.removeItem(atPath: pkgTmpDir)
    info["receipts"] = receiptarray
    if !productVersion.isEmpty {
        info["product_version"] = productVersion
    }
    if !minimumOSVersion.isEmpty {
        info["minimum_os_version"] = minimumOSVersion
    }
        
    return info
}

// MARK: higher-level functions for getting pkg metadata

func getPackageInfo(_ pkgpath: String) -> PlistDict {
    // get some package info (receipts, version, etc) and return as a dict
    guard hasValidPackageExt(pkgpath) else { return PlistDict() }
    displayDebug2("Examining \(pkgpath)...")
    if pathIsDirectory(pkgpath) {
        return getBundlePackageInfo(pkgpath)
    }
    return getFlatPackageInfo(pkgpath)
}


func getPackageMetaData(_ pkgpath: String) -> PlistDict {
    // Queries an installer item (.pkg, .mpkg, .dist)
    // and gets metadata. There are a lot of valid Apple package formats
    // and this function may not deal with them all equally well.
    //
    // metadata items include:
    // installer_item_size:  size of the installer item (.dmg, .pkg, etc)
    // installed_size: size of items that will be installed
    // RestartAction: will a restart be needed after installation?
    // name
    // version
    // receipts: an array of packageids that may be installed
    //           (some may not be installed on some machines)
    
    var pkginfo = PlistDict()
    if !hasValidPackageExt(pkgpath) {
        displayError("\(pkgpath) does not appear to be an Apple installer package.")
        return pkginfo
    }
    
    pkginfo = getPackageInfo(pkgpath)
    let restartInfo = getPkgRestartInfo(pkgpath)
    if let restartAction = restartInfo["RestartAction"] as? String {
        pkginfo["RestartAction"] = restartAction
    }
    var packageVersion = ""
    if let productVersion = pkginfo["product_version"] as? String {
        packageVersion = productVersion
        pkginfo["product_version"] = nil
    }
    if packageVersion.isEmpty {
        // get it from a bundle package
        let bundleVersion = getBundleVersion(pkgpath)
        if !bundleVersion.isEmpty {
            packageVersion = bundleVersion
        }
    }
    if packageVersion.isEmpty {
        // go through receipts and find highest version
        if let receipts = pkginfo["receipts"] as? [PlistDict] {
            let receiptVersions = receipts.map(
                { MunkiVersion($0["version"] as? String ?? "0.0") })
            if let maxVersion = receiptVersions.max() {
                packageVersion = maxVersion.value
            }
        }
    }
    if packageVersion.isEmpty {
        packageVersion = "0.0.0.0.0"
    }
    
    pkginfo["version"] = packageVersion
    let nameAndExt = (pkgpath as NSString).lastPathComponent
    let nameMaybeWithVersion = (nameAndExt as NSString).deletingPathExtension
    pkginfo["name"] = nameAndVersion(nameMaybeWithVersion).0
    var installedSize: Int = 0
    if let receipts = pkginfo["receipts"] as? [PlistDict] {
        pkginfo["receipts"] = receipts
        for receipt in receipts {
            if let size = receipt["installed_size"] as? Int {
                installedSize += size
            }
        }
    }
    if installedSize > 0 {
        pkginfo["installed_size"] = installedSize
    }
    
    return pkginfo
}

// MARK: miscellaneous functions

func hasValidPackageExt(_ path: String) -> Bool {
    // Verifies a path ends in '.pkg' or '.mpkg'
    let ext = (path as NSString).pathExtension
    return ["pkg", "mpkg"].contains(ext.lowercased())
}


func hasValidDiskImageExt(_ path: String) -> Bool {
    // Verifies a path ends in '.dmg' or '.iso'
    let ext = (path as NSString).pathExtension
    return ["dmg", "iso"].contains(ext.lowercased())
}


func hasValidInstallerItemExt(_ path: String) -> Bool {
    // Verifies path refers to an item we can (possibly) install
    return hasValidPackageExt(path) || hasValidDiskImageExt(path)
}


func getChoiceChangesXML(_ pkgpath: String) -> [PlistDict]? {
    // Queries package for 'ChoiceChangesXML'
    var choices: [PlistDict]? = nil
    do {
        let results = runCLI(
            "/usr/sbin/installer",
            arguments: ["-showChoiceChangesXML", "-pkg", pkgpath])
        if results.exitcode == 0 {
            let (pliststr, _) = parseFirstPlist(fromString: results.output)
            let plist = try readPlistFromString(pliststr) as? [PlistDict] ?? [PlistDict]()
            choices = plist.filter {
                ($0["choiceAttribute"] as? String ?? "") == "selected"
            }
        }
    } catch {
        // nothing right now
    }
    return choices
}


func getInstalledPackageVersion(_ pkgid: String) -> String {
    // Checks a package id against the receipts to determine if a
    // package is already installed.
    // Returns the version string of the installed pkg if it exists, or
    // an empty string if it does not
    
    let results = runCLI(
        "/usr/sbin/pkgutil", arguments: ["--pkg-info-plist", pkgid])
    if results.exitcode == 0 {
        guard let plist = try? readPlistFromString(results.output),
              let receipt =  plist as? PlistDict else { return "" }
        guard let foundpkgid = receipt["pkgid"] as? String else { return ""}
        guard let foundversion = receipt["version"] as? String else { return ""}
        if foundpkgid == pkgid {
            displayDebug2(
                "\tThis machine has \(pkgid), version \(foundversion)")
            return foundversion
        }
    }
    // This package does not appear to be currently installed
    displayDebug2("\tThis machine does not have \(pkgid)")
    return ""
}


func nameAndVersion(_ str: String, onlySplitOnHyphens: Bool = true) -> (String, String) {
    // Splits a string into name and version
    // first look for hyphen or double-hyphen as separator
    for delim in ["--", "-"] {
        if str.contains(delim) {
            var parts = str.components(separatedBy: delim)
            if parts.count > 1 {
                let version = parts.removeLast()
                if "0123456789".contains(version.first ?? " ") {
                    let name = parts.joined(separator: delim)
                    return (name, version)
                }
            }
        }
    }
    if onlySplitOnHyphens {
        return (str, "")
    }
    
    // more loosey-goosey method (used when importing items)
    // use regex
    if let versionRange = str.range(
        of: "[0-9]+(\\.[0-9]+)((\\.|a|b|d|v)[0-9]+)+",
        options: .regularExpression) {
        let version = String(str[versionRange.lowerBound...])
        var name = String(str[..<versionRange.lowerBound])
        if let range = name.range(of: "[ v\\._-]+$", options: .regularExpression) {
            name = name.replacingCharacters(in: range, with: "")
        }
        return(name, version)
    }
    return (str, "")
}

func getInstalledPackages() async -> PlistDict {
    // Builds a dictionary of installed receipts and their version number
    var installedpkgs = PlistDict()
    
    let results = await runCliAsync(
        "/usr/sbin/pkgutil", arguments: ["--regexp", "--pkg-info-plist", ".*"])
    if results.exitcode == 0 {
        var out = results.output
        while !out.isEmpty {
            let (pliststr, tempOut) = parseFirstPlist(fromString: out)
            out = tempOut
            if pliststr.isEmpty {
                break
            }
            if let plist = try? readPlistFromString(pliststr) as? PlistDict {
                if let pkgid = plist["pkgid"] as? String,
                   let version = plist["pkg-version"] as? String {
                    installedpkgs[pkgid] = version
                }
            }
        }
    }
    return installedpkgs
}


// This function doesn't really have anything to do with packages or receipts
// but is used by makepkginfo, munkiimport, and installer.py, so it might as
// well live here for now
func isApplication(_ pathname: String) -> Bool {
    // Returns true if path appears to be a macOS application
    if pathIsDirectory(pathname) {
        if pathname.hasSuffix(".app") {
            return true
        }
        // if path extension is not absent (and it's not .app) we can't be an application
        guard (pathname as NSString).pathExtension == "" else { return false }
        // look to see if we have the structure of an application
        if let plist = getBundleInfo(pathname) {
            if let bundlePkgType = plist["CFBundlePackageType"] as? String {
                if bundlePkgType != "APPL" {
                    return false
                }
            }
            return !getAppBundleExecutable(pathname).isEmpty
        }
    }
    return false
}