//
//  RepoFactory.swift
//  munki
//
//  Created by Greg Neagle on 6/29/24.
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

func repoConnect(url: String, plugin: String = "FileRepo") throws -> Repo {
    // Factory function that returns an instance of a specific Repo class
    switch plugin {
    case "FileRepo":
        return try FileRepo(url)
    case "GitFileRepo":
        return try GitFileRepo(url)
    default:
        throw MunkiError("No repo plugin named \"\(plugin)\"")
    }
}