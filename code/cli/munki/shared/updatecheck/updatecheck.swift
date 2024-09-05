//
//  updatecheck.swift
//  munki
//
//  Created by Greg Neagle on 8/26/24.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//       https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

import Foundation

func downloadIconsForActiveItems(_ installInfo: PlistDict) {
    // download display icons for optional installs
    // and active installs/removals
    var itemList = [PlistDict]()
    for key in ["optional_installs", "managed_installs", "removals", "problem_items"] {
        itemList += installInfo[key] as? [PlistDict] ?? []
    }
    // TODO: getStagedOSInstallerInfo()
    // if let stagedOSInstallerInfo = getStagedOSInstallerInfo() {
    //    itemList.append(stagedOSInstallerInfo)
    // }
    downloadIcons(itemList)
}

func cleanUpDownloadCache(_ installInfo: PlistDict) {
    // clean up cache dir
    // remove any item in the cache that isn't scheduled
    // to be used for an install or removal
    // this could happen if an item is downloaded on one
    // updatecheck run, but later removed from the manifest
    // before it is installed or removed - so the cached item
    // is no longer needed.
    let managedInstalls = installInfo["managed_installs"] as? [PlistDict] ?? []
    let removals = installInfo["removals"] as? [PlistDict] ?? []
    let problemItems = installInfo["problem_items"] as? [PlistDict] ?? []
    let optionalInstalls = installInfo["optional_installs"] as? [PlistDict] ?? []
    var keepList = managedInstalls.map {
        $0["installer_item"] as? String ?? ""
    }
    keepList += removals.map {
        $0["uninstaller_item"] as? String ?? ""
    }.filter {
        !$0.isEmpty
    }
    // Don't delete problem item partial downloads
    keepList += problemItems.map {
        $0["installer_item"] as? String ?? ""
    }.filter {
        !$0.isEmpty
    }
    // Don't delete optional installs that are designated as precache
    keepList += optionalInstalls.filter {
        $0["precache"] as? Bool ?? false
    }.map {
        baseName($0["installer_item_location"] as? String ?? "")
    }.filter {
        !$0.isEmpty
    }

    let cacheDir = managedInstallsDir(subpath: "Cache")
    if let cacheNames = try? FileManager.default.contentsOfDirectory(atPath: cacheDir) {
        for item in cacheNames {
            let fullPath = (cacheDir as NSString).appendingPathComponent(item)
            if item.hasSuffix(".download") {
                // we have a partial download here
                let simpleName = (item as NSString).deletingPathExtension
                if cacheNames.contains(simpleName) {
                    // we have a partial and a full download
                    // for the same item. (This shouldn't happen.)
                    // remove the partial download.
                    displayDetail("Removing partial download \(item) from cache")
                    try? FileManager.default.removeItem(atPath: fullPath)
                } else if !keepList.contains(simpleName) {
                    // abandoned partial download
                    displayDetail("Removing partial download \(item) from cache")
                    try? FileManager.default.removeItem(atPath: fullPath)
                }
            } else if !keepList.contains(item) {
                displayDetail("Removing \(item) from cache")
                try? FileManager.default.removeItem(atPath: fullPath)
            }
        }
    }
}

func processLocalOnlyManifest(catalogList: [String], installInfo: inout PlistDict) async throws {
    // processes the LocalOnlyManifest if defined and present
    guard let localOnlyManifestName = stringPref("LocalOnlyManifest"),
          !localOnlyManifestName.isEmpty,
          !catalogList.isEmpty
    else {
        return
    }

    // if the manifest already exists, the name is being reused
    if Manifests.shared.list().contains(localOnlyManifestName) {
        displayError("LocalOnlyManifest \(localOnlyManifestName) has the same name as an existing manifest, skipping...")
        return
    }

    let localOnlyManifestPath = managedInstallsDir(
        subpath: "manifests/" + localOnlyManifestName)
    if !pathExists(localOnlyManifestPath) {
        displayDebug1("LocalOnlyManifest \(localOnlyManifestName) is defined but is not present. Skipping.")
        return
    }
    guard var localOnlyManifest = manifestData(localOnlyManifestPath) else {
        displayError("Could not get manifest data from \(localOnlyManifestPath)")
        return
    }
    Manifests.shared.set(localOnlyManifestName, path: localOnlyManifestPath)

    // Finally ready to actually process it!
    displayDetail("**Processing local-only manifest**")
    // remove catalogs, included_manifests, and conditional_items if present
    for key in ["catalogs", "included_manifests", "conditional_items"] {
        if localOnlyManifest[key] != nil {
            displayWarning("Local-only manifest \(localOnlyManifestName) contains section '\(key)`. Ignoring.")
            localOnlyManifest[key] = nil
        }
    }
    for key in ["managed_installs", "managed_uninstalls", "managed_updates", "optional_installs"] {
        _ = try await processManifest(
            localOnlyManifest,
            forKey: key,
            installInfo: &installInfo
        )
        if stopRequested() {
            return
        }
    }
}

func processSelfServeManifest(mainManifest: PlistDict, installInfo: inout PlistDict) async throws {
    // processes the SelfServeManifest if present

    guard let parentCatalogs = mainManifest["catalogs"] as? [String] else {
        displayError("Primary manifest has no catalogs")
        return
    }

    // copy user-writable selfservice manifest if present
    updateSelfServeManifest()

    // process any default installs (adding to selfservice as needed)
    _ = try await processManifest(
        mainManifest,
        forKey: "default_installs",
        installInfo: &installInfo
    )

    let selfServeManifestPath = selfServiceManifestPath()
    if !pathExists(selfServeManifestPath) {
        // nothing to do!
        return
    }
    guard let selfServeManifest = manifestData(selfServeManifestPath) else {
        displayError("Selfserve manifest cannot be read!")
        return
    }

    displayDetail("**Processing self-serve choices**")
    if var installs = selfServeManifest["managed_installs"] as? [String],
       !installs.isEmpty
    {
        // build list of items in the optional_installs list
        // that have not exceeded available seats
        // and don't have notes (indicating why they can't be installed)
        let installInfoOptionalInstalls = installInfo["optional_installs"] as? [PlistDict] ?? []
        let availableOptionalInstalls = installInfoOptionalInstalls.filter {
            $0["note"] == nil && ($0["licensed_seats_available"] as? Bool ?? true)
        }.map {
            $0["name"] as? String ?? ""
        }.filter {
            !$0.isEmpty
        }
        installs = installs.filter {
            availableOptionalInstalls.contains($0)
        }
        for item in installs {
            _ = await processInstall(
                item,
                catalogList: parentCatalogs,
                installInfo: &installInfo,
                isOptionalInstall: true
            )
        }
    }
    if let uninstalls = selfServeManifest["managed_uninstalls"] as? [String],
       !uninstalls.isEmpty
    {
        for item in uninstalls {
            _ = await processRemoval(
                item,
                catalogList: parentCatalogs,
                installInfo: &installInfo
            )
        }
    }

    // update optional_installs with install/removal info
    if var optionalInstalls = installInfo["optional_installs"] as? [PlistDict] {
        let managedInstalls = installInfo["managed_installs"] as? [PlistDict] ?? []
        let removals = installInfo["removals"] as? [PlistDict] ?? []
        for (index, item) in optionalInstalls.enumerated() {
            let installed = item["installed"] as? Bool ?? false
            if !installed, itemInInstallInfo(item, theList: managedInstalls) {
                optionalInstalls[index]["will_be_installed"] = true
            } else if installed, itemInInstallInfo(item, theList: removals) {
                optionalInstalls[index]["will_be_removed"] = true
            }
        }
        installInfo["optional_installs"] = optionalInstalls
    }
}

enum UpdateCheckResult: Int {
    case checkDidntStart = -2
    case finishedWithErrors = -1
    case noUpdatesAvailable = 0
    case updatesAvailable = 1
}

func checkForUpdates(clientID: String? = nil, localManifestPath: String? = nil) async throws -> UpdateCheckResult {
    // Checks for available new or updated managed software, downloading
    // installer items if needed. Returns UpdateCheckResult.

    // Auto-detect a Munki repo if one isn't defined in preferences
    autodetectRepoURLIfNeeded()

    await Report.shared.record(getMachineFacts(), to: "MachineInfo")

    // TODO: initialize our Munki keychain if we are using custom certs or CAs
    // MunkiKeychain()

    if DisplayOptions.shared.munkistatusoutput {
        munkiStatusActivate()
    }

    munkiLog("### Beginning managed software check ###")
    displayMajorStatus("Checking for available updates...")
    munkiStatusPercent(-1)
    munkiStatusDetail("")

    var success = true

    var mainManifestPath = ""
    if let localManifestPath {
        mainManifestPath = localManifestPath
    } else {
        do {
            mainManifestPath = try getPrimaryManifest(alternateIdentifier: clientID)
        } catch let err as ManifestError {
            displayError("Could not retrieve managed install primary manifest: \(err.localizedDescription)")
            throw err
        }
    }

    guard let mainManifest = manifestData(mainManifestPath) else {
        displayError("Could not get manifest data from main mainfest \(mainManifestPath)")
        return .finishedWithErrors
    }
    guard let mainManifestCatalogsList = mainManifest["catalogs"] as? [String],
          !mainManifestCatalogsList.isEmpty
    else {
        displayError("Main mainfest \(mainManifestPath) does not have a list of catalogs")
        return .finishedWithErrors
    }

    if stopRequested() {
        return .noUpdatesAvailable
    }

    // stop precaching_agent if it's running
    // TODO: stopPrecachingAgent()

    // prevent idle sleep only if we are on AC power
    var caffeinator: Caffeinator? = nil
    if onACPower() {
        caffeinator = Caffeinator(reason: "managedsoftwareupdate is checking for new software")
    }

    // initialize our installinfo record
    var installInfo: PlistDict = [
        "featured_items": [String](),
        "managed_installs": [PlistDict](),
        "managed_updates": [String](),
        "optional_installs": [PlistDict](),
        "problem_items": [PlistDict](),
        "processed_installs": [String](),
        "processed_uninstalls": [String](),
        "removals": [PlistDict](),
    ]

    // TODO: remove any staged os installer info we have; we'll check and
    // recreate if still valid
    // removeStagedOSInstallerInfo()

    do {
        // check managed_installs
        displayDetail("**Checking for installs**")
        _ = try await processManifest(
            mainManifest,
            forKey: "managed_installs",
            installInfo: &installInfo
        )
        if stopRequested() {
            return .noUpdatesAvailable
        }

        // reset progress indicator and detail field
        munkiStatusMessage("Checking for additional changes...")
        munkiStatusPercent(-1)
        munkiStatusDetail("")

        // check managed_uninstalls
        displayDetail("**Checking for removals**")
        _ = try await processManifest(
            mainManifest,
            forKey: "managed_uninstalls",
            installInfo: &installInfo
        )
        if stopRequested() {
            return .noUpdatesAvailable
        }

        // now check for implicit removals
        // use catalogs from main manifest
        let autoremovalItems = getAutoRemovalItems(installInfo: installInfo, catalogList: mainManifestCatalogsList)
        if !autoremovalItems.isEmpty {
            displayDetail("**Checking for implicit removals**")
            for item in autoremovalItems {
                if stopRequested() {
                    return .noUpdatesAvailable
                }
                _ = await processRemoval(
                    item,
                    catalogList: mainManifestCatalogsList,
                    installInfo: &installInfo
                )
            }
        }

        // process managed_updates
        displayDetail("**Checking for managed updates**")
        _ = try await processManifest(
            mainManifest,
            forKey: "managed_updates",
            installInfo: &installInfo
        )
        if stopRequested() {
            return .noUpdatesAvailable
        }

        // process LocalOnlyManifest (if defined and present)
        try await processLocalOnlyManifest(
            catalogList: mainManifestCatalogsList, installInfo: &installInfo
        )
        if stopRequested() {
            return .noUpdatesAvailable
        }

        // build list of optional installs
        _ = try await processManifest(
            mainManifest,
            forKey: "optional_installs",
            installInfo: &installInfo
        )
        if stopRequested() {
            return .noUpdatesAvailable
        }

        // build list of featured installs
        _ = try await processManifest(
            mainManifest,
            forKey: "featured_items",
            installInfo: &installInfo
        )
        if stopRequested() {
            return .noUpdatesAvailable
        }
        let inFeaturedItems = Set(installInfo["featured_items"] as? [String] ?? [])
        let inOptionalInstalls = Set(
            (installInfo["optional_installs"] as? [PlistDict] ?? []).map {
                $0["name"] as? String ?? ""
            }.filter {
                !$0.isEmpty
            }
        )
        for item in inFeaturedItems.subtracting(inOptionalInstalls) {
            displayWarning("\(item) is in the list of featured_items, but is not in the list of optional_installs. Will be ignored.")
        }

        // verify available license seats for optional installs
        if let optionalInstalls = installInfo["optional_installs"] as? [PlistDict],
           !optionalInstalls.isEmpty
        {
            installInfo["optional_installs"] = updateAvailableLicenseSeats(optionalInstalls)
        }

        // now process any self-serve choices
        try await processSelfServeManifest(
            mainManifest: mainManifest, installInfo: &installInfo
        )

        // filter managed_installs to get items already installed
        var managedInstalls = installInfo["managed_installs"] as? [PlistDict] ?? []
        let installedItems = managedInstalls.filter {
            $0["installed"] as? Bool ?? false
        }.map {
            $0["name"] as? String ?? ""
        }
        // filter managed_installs to get problem items:
        // not installed, but no installer item
        let problemItems = managedInstalls.filter {
            ($0["installed"] as? Bool ?? true) == false &&
                ($0["installer_item"] as? String ?? "").isEmpty
        }
        // filter removals to get items already removed
        // (or never installed)
        let removals = installInfo["removals"] as? [PlistDict] ?? []
        let removedItems = removals.filter {
            ($0["installed"] as? Bool ?? true) == false
        }.map {
            $0["name"] as? String ?? ""
        }

        // clean up any old managed_uninstalls in the SelfServeManifest
        cleanUpSelfServeManagedUninstalls(removals)

        // sort startosinstall items to the end of managed_installs
        let nonStartOSInstallItems = managedInstalls.filter {
            ($0["install_type"] as? String ?? "") != "startosinstall"
        }
        let startOSInstallItems = managedInstalls.filter {
            ($0["install_type"] as? String ?? "") == "startosinstall"
        }
        managedInstalls = nonStartOSInstallItems + startOSInstallItems
        installInfo["managed_installs"] = managedInstalls

        if startOSInstallItems.count > 1 {
            displayWarning("There are mulitple startosinstall items in managed_installs. Only the install of the first one will be attempted.")
        }

        // record detail before we throw it away...
        Report.shared.record(managedInstalls, to: "ManagedInstalls")
        Report.shared.record(installedItems, to: "InstalledItems")
        Report.shared.record(problemItems, to: "ProblemInstalls")
        Report.shared.record(removedItems, to: "RemovedItems")
        Report.shared.record(
            installInfo["processed_installs"] as? [String] ?? [],
            to: "managed_installs_list"
        )
        Report.shared.record(
            installInfo["processed_uninstalls"] as? [String] ?? [],
            to: "managed_uninstalls_list"
        )
        Report.shared.record(
            installInfo["managed_updates"] as? [String] ?? [],
            to: "managed_updates_list"
        )

        // now filter the managed_installs and removals lists
        // so they have only items that need action
        installInfo["managed_installs"] = managedInstalls.filter {
            $0["installer_item"] != nil
        }
        installInfo["removals"] = removals.filter {
            ($0["installed"] as? Bool ?? false)
        }
        installInfo["problem_items"] = problemItems

        // record the filtered lists
        Report.shared.record(
            installInfo["managed_installs"] as? [String] ?? [],
            to: "ItemsToInstall"
        )
        Report.shared.record(
            installInfo["removals"] as? [String] ?? [],
            to: "ItemsToRemove"
        )

        // download display icons for optional installs
        // and active installs/removals
        downloadIconsForActiveItems(installInfo)

        // get any custom client resources
        downloadClientResources()

        // record info object for conditional item comparisons
        var conditions = await predicateInfoObject()
        conditions["applications"] = nil
        conditions["catalogs"] = mainManifestCatalogsList
        Report.shared.record(conditions, to: "Conditions")

        // Clean up some directories
        cleanUpCatalogs()
        cleanUpManifests()
        cleanUpDownloadCache(installInfo)

        // write out installList so our installer has the metadata needed
        // for proper installs
        var installInfoChanged = true
        let installInfoPath = managedInstallsDir(subpath: "InstallInfo.plist")
        var oldInstallInfo = PlistDict()
        if pathExists(installInfoPath) {
            do {
                oldInstallInfo = try readPlist(fromFile: installInfoPath) as? PlistDict ?? PlistDict()
            } catch {
                displayError("Could not read InstallInfo.plist. Deleting...")
                try? FileManager.default.removeItem(atPath: installInfoPath)
            }
            if (installInfo as NSDictionary).isEqual(to: oldInstallInfo as NSDictionary) {
                installInfoChanged = false
                displayDetail("No change in InstallInfo.")
            }
        }
        if installInfoChanged {
            try writePlist(installInfo, toFile: installInfoPath)
        }

    } catch _ as ManifestError {
        // we had an error with a manifest
        // See if we have a valid InstallInfo from an earlier run
        success = false
        let installInfoPath = managedInstallsDir(subpath: "InstallInfo.plist")
        var installInfo = PlistDict()
        if let lastInstallInfo = (try? readPlist(fromFile: installInfoPath)) as? PlistDict {
            installInfo = lastInstallInfo
        }
        let managedInstalls = installInfo["managed_installs"] as? [PlistDict] ?? []
        let removals = installInfo["removals"] as? [PlistDict] ?? []
        Report.shared.record(managedInstalls, to: "ItemsToInstall")
        Report.shared.record(removals, to: "ItemsToRemove")
    }

    Report.shared.save()
    munkiLog("###    End managed software check    ###")

    var updateCount = (installInfo["managed_installs"] as? [PlistDict] ?? []).count
    updateCount += (installInfo["removals"] as? [PlistDict] ?? []).count

    // start our precaching agent
    // note -- this must happen _after_ InstallInfo.plist gets written to disk.
    // TODO: download.run_precaching_agent()

    if !success {
        return .finishedWithErrors
    }
    if updateCount > 0 {
        return .updatesAvailable
    }
    return .noUpdatesAvailable
}