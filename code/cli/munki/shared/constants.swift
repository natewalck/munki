//
//  constants.swift
//  munki
//
//  Created by Greg Neagle on 6/25/24.
//
//  Copyright 2024 Greg Neagle.
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

// NOTE: it's very important that defined exit codes are never changed!
// Preflight exit codes
let EXIT_STATUS_PREFLIGHT_FAILURE: Int32 = 1
// Client config exit codes.
let EXIT_STATUS_OBJC_MISSING: Int32 = 100 // no longer relevant
let EXIT_STATUS_MUNKI_DIRS_FAILURE: Int32 = 101
// Server connection exit codes.
let EXIT_STATUS_SERVER_UNAVAILABLE: Int32 = 150
// User related exit codes.
let EXIT_STATUS_INVALID_PARAMETERS: Int32 = 200
let EXIT_STATUS_ROOT_REQUIRED: Int32 = 201

let BUNDLE_ID = "ManagedInstalls" as CFString
#if DEBUG
    let DEFAULT_MANAGED_INSTALLS_DIR = "/Users/Shared/Managed Installs"
#else
    let DEFAULT_MANAGED_INSTALLS_DIR = "/Library/Managed Installs"
#endif
let DEFAULT_GUI_CACHE_AGE_SECS = 3600
let WRITEABLE_SELF_SERVICE_MANIFEST_PATH = "/Users/Shared/.SelfServeManifest"

let ADDITIONAL_HTTP_HEADERS_KEY = "AdditionalHttpHeaders"

let LOGINWINDOW = "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"

let CHECKANDINSTALLATSTARTUPFLAG = "/Users/Shared/.com.googlecode.munki.checkandinstallatstartup"
let INSTALLATSTARTUPFLAG = "/Users/Shared/.com.googlecode.munki.installatstartup"
let INSTALLATLOGOUTFLAG = "/private/tmp/com.googlecode.munki.installatlogout"
let UPDATECHECKLAUNCHFILE = "/private/tmp/.com.googlecode.munki.updatecheck.launchd"
let INSTALLWITHOUTLOGOUTFILE = "/private/tmp/.com.googlecode.munki.managedinstall.launchd"

// postinstall actions
let POSTACTION_NONE = 0
let POSTACTION_LOGOUT = 1
let POSTACTION_RESTART = 2
let POSTACTION_SHUTDOWN = 4

typealias PlistDict = [String: Any]