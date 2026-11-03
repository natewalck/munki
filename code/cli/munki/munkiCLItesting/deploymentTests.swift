//
//  deploymentTests.swift
//  munkiCLItesting
//
//  Copyright 2026 The Munki Project. All rights reserved.
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
import Testing

/// "2026-10-20 09:00" as a UTC date, the frame pkginfo dates are compared in.
/// 2026-10-12 is a Monday, and 2026-10-17 and 18 are a weekend.
private func date(_ text: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: text.replacingOccurrences(of: " ", with: "T") + ":00Z")!
}

private func deployment(_ dict: [String: Any]) throws -> Deployment {
    return try Deployment(dict)
}

private func percent(_ deployment: Deployment, _ text: String) -> Int {
    return deployment.state(at: date(text)).currentPercent
}

struct DeploymentStrategyTests {
    @Test func twoWeekRollout() throws {
        let rollout = try deployment(["start": date("2026-10-12 00:00"), "end": date("2026-10-24 00:00")])

        let state = rollout.state(at: date("2026-10-14 09:30"))
        #expect(state.status == .inProgress)
        #expect(state.step == 58)
        #expect(state.totalSteps == 241)
        #expect(state.currentPercent == 25)
        #expect(state.nextStepDate == date("2026-10-14 10:00"))
        // steps 59 and 60 also round up to 25, so the percent next rises at step 61
        #expect(state.nextIncreaseDate == date("2026-10-14 12:00"))

        #expect(percent(rollout, "2026-10-11 23:59") == 0)
        #expect(percent(rollout, "2026-10-12 00:00") == 1)
        // rounding up would give 100 here, but only the last step reaches it
        #expect(percent(rollout, "2026-10-23 21:00") == 99)
        #expect(percent(rollout, "2026-10-23 23:59") == 99)
        #expect(percent(rollout, "2026-10-24 00:00") == 100)
    }

    @Test func fastRoll() throws {
        let rollout = try deployment(["start": date("2026-10-20 09:00"), "end": date("2026-10-20 17:00")])
        let expected = [12, 23, 34, 45, 56, 67, 78, 89, 100]
        for (index, value) in expected.enumerated() {
            #expect(percent(rollout, String(format: "2026-10-20 %02d:00", 9 + index)) == value)
        }
        #expect(percent(rollout, "2026-10-20 08:59") == 0)
        #expect(percent(rollout, "2026-10-20 16:59") == 89)
        #expect(rollout.state(at: date("2026-10-20 12:00")).totalSteps == 9)
    }

    @Test func overnight() throws {
        let rollout = try deployment(["start": date("2026-10-20 18:00"), "end": date("2026-10-21 06:00")])
        #expect(rollout.state(at: date("2026-10-20 18:00")).totalSteps == 13)
        #expect(percent(rollout, "2026-10-20 18:00") == 8)
        #expect(percent(rollout, "2026-10-20 19:00") == 16)
        #expect(percent(rollout, "2026-10-21 05:59") == 93)
        #expect(percent(rollout, "2026-10-21 06:00") == 100)
    }

    @Test func hourlyRate() throws {
        let rollout = try deployment(["start": date("2026-10-20 09:00"), "percent_per_hour": 10])
        for index in 0 ..< 10 {
            #expect(percent(rollout, String(format: "2026-10-20 %02d:00", 9 + index)) == (index + 1) * 10)
        }
        #expect(percent(rollout, "2026-10-20 17:59") == 90)
        #expect(rollout.state(at: date("2026-10-20 18:00")).status == .complete)
    }

    @Test func dailyBatches() throws {
        let rollout = try deployment([
            "start": date("2026-10-12 00:00"), "percent_per_step": 10, "step_hours": 24,
        ])
        #expect(percent(rollout, "2026-10-12 00:00") == 10)
        #expect(percent(rollout, "2026-10-12 23:59") == 10)
        #expect(percent(rollout, "2026-10-16 00:00") == 50)
        #expect(percent(rollout, "2026-10-17 12:00") == 50)
        #expect(percent(rollout, "2026-10-19 00:00") == 60)
        #expect(percent(rollout, "2026-10-22 23:59") == 90)
        #expect(percent(rollout, "2026-10-23 00:00") == 100)
        #expect(rollout.state(at: date("2026-10-16 12:00")).nextStepDate == date("2026-10-19 00:00"))
    }

    @Test func dailyRate() throws {
        let rollout = try deployment(["start": date("2026-10-12 00:00"), "percent_per_day": 20])
        #expect(percent(rollout, "2026-10-12 00:00") == 1)
        #expect(percent(rollout, "2026-10-16 21:59") == 99)
        // the design's "rounding up gets there an hour early"
        #expect(percent(rollout, "2026-10-16 22:00") == 100)
        #expect(rollout.state(at: date("2026-10-12 00:00")).totalSteps == 119)
    }

    @Test func percentPerStepOnConsecutiveDays() throws {
        let rollout = try deployment([
            "start": date("2026-10-12 00:00"), "percent_per_step": 20, "step_hours": 24,
        ])
        for (index, day) in ["12", "13", "14", "15", "16"].enumerated() {
            #expect(percent(rollout, "2026-10-\(day) 00:00") == (index + 1) * 20)
        }
    }

    @Test func staticPercent() throws {
        let canary = try deployment(["percent": 5])
        let state = canary.state(at: date("2026-10-20 09:00"))
        #expect(state.status == .fixed)
        #expect(state.currentPercent == 5)
        #expect(state.step == nil)
        #expect(state.totalSteps == nil)
        #expect(state.nextStepDate == nil)
        #expect(state.nextIncreaseDate == nil)

        #expect(try deployment(["percent": 100]).state(at: date("2026-10-20 09:00")).status == .complete)
    }

    @Test func staticPercentWithStart() throws {
        let canary = try deployment(["start": date("2026-11-05 00:00"), "percent": 5])

        let before = canary.state(at: date("2026-11-04 23:59"))
        #expect(before.status == .scheduled)
        #expect(before.currentPercent == 0)
        #expect(before.step == nil)
        #expect(before.nextStepDate == date("2026-11-05 00:00"))
        #expect(before.nextIncreaseDate == date("2026-11-05 00:00"))

        let after = canary.state(at: date("2026-11-05 00:00"))
        #expect(after.status == .fixed)
        #expect(after.currentPercent == 5)
        #expect(after.nextStepDate == nil)
        #expect(after.nextIncreaseDate == nil)
    }

    @Test func staticPercentWithWeekendStartBehavesLikeMonday() throws {
        let canary = try deployment(["start": date("2026-10-17 10:00"), "percent": 5])
        #expect(percent(canary, "2026-10-18 23:59") == 0)
        #expect(canary.state(at: date("2026-10-18 23:59")).nextStepDate == date("2026-10-19 00:00"))
        #expect(percent(canary, "2026-10-19 00:00") == 5)
    }

    @Test func staticHundredWithStartIsScheduledThenComplete() throws {
        let rollout = try deployment(["start": date("2026-11-05 00:00"), "percent": 100])
        #expect(rollout.state(at: date("2026-11-04 12:00")).status == .scheduled)
        #expect(rollout.state(at: date("2026-11-05 00:00")).status == .complete)
    }

    @Test func staticPercentIgnoresStepHours() throws {
        #expect(percent(try deployment(["percent": 5, "step_hours": 24]), "2026-10-20 09:00") == 5)
        #expect(percent(try deployment(["percent": 5, "step_hours": "bad"]), "2026-10-20 09:00") == 5)
    }
}

struct DeploymentStepTests {
    @Test func partialStartHour() throws {
        let rollout = try deployment(["start": date("2026-10-20 08:30"), "end": date("2026-10-20 17:00")])
        #expect(rollout.state(at: date("2026-10-20 08:30")).totalSteps == 10)
        #expect(percent(rollout, "2026-10-20 08:29") == 0)
        #expect(percent(rollout, "2026-10-20 08:30") == 10)
        #expect(percent(rollout, "2026-10-20 08:59") == 10)
        #expect(percent(rollout, "2026-10-20 09:00") == 20)
        #expect(percent(rollout, "2026-10-20 17:00") == 100)
    }

    @Test func partialStartHourWithStepHours() throws {
        let rollout = try deployment([
            "start": date("2026-10-20 08:30"), "end": date("2026-10-20 17:00"), "step_hours": 2,
        ])
        #expect(rollout.state(at: date("2026-10-20 08:30")).totalSteps == 6)
        #expect(rollout.state(at: date("2026-10-20 08:30")).nextStepDate == date("2026-10-20 10:00"))
        #expect(percent(rollout, "2026-10-20 09:59") == 17)
        #expect(percent(rollout, "2026-10-20 10:00") == 34)
    }

    @Test func partialEndHour() throws {
        let rollout = try deployment(["start": date("2026-10-20 09:00"), "end": date("2026-10-20 11:30")])
        #expect(rollout.state(at: date("2026-10-20 09:00")).totalSteps == 4)
        #expect(percent(rollout, "2026-10-20 11:00") == 75)
        #expect(rollout.state(at: date("2026-10-20 11:00")).nextStepDate == date("2026-10-20 11:30"))
        #expect(percent(rollout, "2026-10-20 11:30") == 100)
    }

    @Test func stepHoursLastStepCanBeShort() throws {
        let rollout = try deployment([
            "start": date("2026-10-20 08:00"), "end": date("2026-10-20 17:00"), "step_hours": 2,
        ])
        let expected = [("08:00", 17), ("10:00", 34), ("12:00", 50), ("14:00", 67), ("16:00", 84), ("17:00", 100)]
        for (time, value) in expected {
            #expect(percent(rollout, "2026-10-20 \(time)") == value)
        }
        #expect(percent(rollout, "2026-10-20 15:59") == 67)
    }

    @Test func endLandingOnAStepIsNotCountedTwice() throws {
        let rollout = try deployment([
            "start": date("2026-10-20 08:00"), "end": date("2026-10-20 18:00"), "step_hours": 2,
        ])
        #expect(rollout.state(at: date("2026-10-20 08:00")).totalSteps == 6)
    }

    @Test func roundingUpSeventeenSteps() throws {
        let rollout = try deployment(["start": date("2026-10-12 00:00"), "end": date("2026-10-12 16:00")])
        #expect(rollout.state(at: date("2026-10-12 00:00")).totalSteps == 17)
        #expect(percent(rollout, "2026-10-12 00:00") == 6)
        #expect(percent(rollout, "2026-10-12 01:00") == 12)
        #expect(percent(rollout, "2026-10-12 02:00") == 18)
        #expect(percent(rollout, "2026-10-12 15:00") == 95)
        #expect(percent(rollout, "2026-10-12 16:00") == 100)
    }

    @Test func staysAtOneHundred() throws {
        let rollout = try deployment(["start": date("2026-10-20 09:00"), "percent_per_hour": 50])
        let state = rollout.state(at: date("2030-06-05 12:00"))
        #expect(state.currentPercent == 100)
        #expect(state.status == .complete)
        #expect(state.nextStepDate == nil)
        #expect(state.nextIncreaseDate == nil)
    }

    @Test func beforeStart() throws {
        let rollout = try deployment(["start": date("2026-10-20 09:00"), "end": date("2026-10-20 17:00")])
        let state = rollout.state(at: date("2026-10-19 09:00"))
        #expect(state.status == .scheduled)
        #expect(state.currentPercent == 0)
        #expect(state.step == 0)
        #expect(state.nextStepDate == date("2026-10-20 09:00"))
        #expect(state.nextIncreaseDate == date("2026-10-20 09:00"))
    }
}

struct DeploymentWeekendTests {
    private let acrossWeekend: [String: Any] = [
        "start": date("2026-10-16 20:00"), "end": date("2026-10-19 02:00"),
    ]

    @Test func weekendHoursAreNotCounted() throws {
        let rollout = try deployment(acrossWeekend)
        #expect(rollout.state(at: date("2026-10-16 20:00")).totalSteps == 7)
        #expect(percent(rollout, "2026-10-16 23:00") == 58)
        #expect(percent(rollout, "2026-10-17 00:00") == 58)
        #expect(percent(rollout, "2026-10-18 23:59") == 58)
        #expect(percent(rollout, "2026-10-19 00:00") == 72)
        #expect(rollout.state(at: date("2026-10-17 12:00")).nextStepDate == date("2026-10-19 00:00"))
    }

    @Test func weekendStartBehavesLikeMonday() throws {
        let rollout = try deployment(["start": date("2026-10-17 10:00"), "end": date("2026-10-19 02:00")])
        #expect(rollout.state(at: date("2026-10-18 12:00")).status == .scheduled)
        #expect(rollout.state(at: date("2026-10-18 12:00")).nextStepDate == date("2026-10-19 00:00"))
        #expect(rollout.state(at: date("2026-10-19 00:00")).totalSteps == 3)
        #expect(percent(rollout, "2026-10-18 23:59") == 0)
        #expect(percent(rollout, "2026-10-19 00:00") == 34)
        #expect(percent(rollout, "2026-10-19 02:00") == 100)
    }

    @Test func weekendEndMovesBackToSaturdayMidnight() throws {
        for end in ["2026-10-17 00:00", "2026-10-17 12:00", "2026-10-18 15:00"] {
            let rollout = try deployment(["start": date("2026-10-16 20:00"), "end": date(end)])
            #expect(rollout.state(at: date("2026-10-16 20:00")).totalSteps == 5)
            #expect(percent(rollout, "2026-10-16 23:59") == 80)
            #expect(rollout.state(at: date("2026-10-16 23:30")).nextStepDate == date("2026-10-17 00:00"))
            #expect(percent(rollout, "2026-10-17 00:00") == 100)
            #expect(percent(rollout, "2026-10-18 12:00") == 100)
        }
    }

    @Test func mondayMidnightEndDoesNotFinishOverTheWeekend() throws {
        let rollout = try deployment(["start": date("2026-10-16 20:00"), "end": date("2026-10-19 00:00")])
        #expect(percent(rollout, "2026-10-18 12:00") == 80)
        #expect(percent(rollout, "2026-10-19 00:00") == 100)
    }

    @Test func startAndEndWithNoWeekdayBetweenAreInvalid() {
        let cases = [
            ("2026-10-17 10:00", "2026-10-18 10:00"),
            ("2026-10-17 10:00", "2026-10-17 11:00"),
            ("2026-10-17 10:00", "2026-10-19 00:00"),
        ]
        for (start, end) in cases {
            #expect(throws: MunkiError.self) {
                try deployment(["start": date(start), "end": date(end)])
            }
        }
    }

    @Test func rateModesPauseOverTheWeekend() throws {
        let rollout = try deployment(["start": date("2026-10-16 20:00"), "percent_per_hour": 10])
        #expect(percent(rollout, "2026-10-16 23:00") == 40)
        #expect(percent(rollout, "2026-10-17 12:00") == 40)
        #expect(percent(rollout, "2026-10-19 00:00") == 50)
    }

    @Test func dailyStepsCarryTheirHourAcrossTheWeekend() throws {
        let rollout = try deployment([
            "start": date("2026-10-16 09:00"), "percent_per_step": 20, "step_hours": 24,
        ])
        #expect(percent(rollout, "2026-10-16 09:00") == 20)
        #expect(percent(rollout, "2026-10-19 08:59") == 20)
        #expect(percent(rollout, "2026-10-19 09:00") == 40)
    }
}

struct DeploymentLocalTimeTests {
    /// Converts the way subtractTZOffsetFromDate does, for a named time zone.
    private func toRealDate(in zone: String) -> (Date) -> Date {
        let timeZone = TimeZone(identifier: zone)!
        return { $0.addingTimeInterval(-Double(timeZone.secondsFromGMT(for: $0))) }
    }

    /// 09:00Z in the pkginfo means 09:00 local on each machine.
    @Test func stepsOpenAtLocalTime() throws {
        let rollout = try deployment(["start": date("2026-10-20 09:00"), "end": date("2026-10-20 17:00")])
        let losAngeles = toRealDate(in: "America/Los_Angeles") // UTC-7 in October
        #expect(rollout.state(at: date("2026-10-20 15:59"), toRealDate: losAngeles).currentPercent == 0)
        #expect(rollout.state(at: date("2026-10-20 16:00"), toRealDate: losAngeles).currentPercent == 12)

        let tokyo = toRealDate(in: "Asia/Tokyo") // UTC+9
        #expect(rollout.state(at: date("2026-10-19 23:59"), toRealDate: tokyo).currentPercent == 0)
        #expect(rollout.state(at: date("2026-10-20 00:00"), toRealDate: tokyo).currentPercent == 12)
    }

    @Test func returnedDatesAreConverted() throws {
        let rollout = try deployment(["start": date("2026-10-20 09:00"), "end": date("2026-10-20 17:00")])
        let state = rollout.state(at: date("2026-10-20 12:00"), toRealDate: toRealDate(in: "America/Los_Angeles"))
        #expect(state.nextStepDate == date("2026-10-20 16:00"))
        #expect(state.nextIncreaseDate == date("2026-10-20 16:00"))
    }

    @Test func staticStartUsesLocalTime() throws {
        let canary = try deployment(["start": date("2026-11-05 00:00"), "percent": 5])
        let tokyo = toRealDate(in: "Asia/Tokyo")
        #expect(canary.state(at: date("2026-11-04 14:59"), toRealDate: tokyo).currentPercent == 0)
        #expect(canary.state(at: date("2026-11-04 15:00"), toRealDate: tokyo).currentPercent == 5)
    }

    @Test func usesTheSameConversionAsForceInstall() throws {
        let rollout = try deployment(["start": date("2026-10-20 09:00"), "end": date("2026-10-20 17:00")])
        let firstStep = subtractTZOffsetFromDate(date("2026-10-20 09:00"))
        let state = rollout.state(at: firstStep, toRealDate: subtractTZOffsetFromDate)
        #expect(state.currentPercent == 12)
        let before = rollout.state(at: firstStep.addingTimeInterval(-1), toRealDate: subtractTZOffsetFromDate)
        #expect(before.currentPercent == 0)
    }

    /// Clocks change in Los Angeles on Sunday 2026-03-08 and 2026-11-01. A schedule spanning
    /// them must never go backward, and must still finish.
    @Test func clockChangesDoNotBreakASchedule() throws {
        let losAngeles = toRealDate(in: "America/Los_Angeles")
        for (start, end) in [("2026-03-06 20:00", "2026-03-10 02:00"), ("2026-10-30 20:00", "2026-11-03 02:00")] {
            let rollout = try deployment(["start": date(start), "end": date(end)])
            var previous = 0
            var now = date(start)
            while now < date(end).addingTimeInterval(24 * 3600) {
                let current = rollout.state(at: now, toRealDate: losAngeles).currentPercent
                #expect(current >= previous)
                previous = current
                now.addTimeInterval(900)
            }
            #expect(previous == 100)
        }
    }
}

struct DeploymentPropertyTests {
    /// Walks each schedule in half hours and checks what should hold for any deployment.
    @Test func schedulesBehaveAtEveryPoint() throws {
        let start = date("2026-10-12 00:00")
        let schedules: [[String: Any]] = [
            ["start": start, "end": date("2026-10-24 00:00")],
            ["start": date("2026-10-14 08:30"), "end": date("2026-10-27 16:45")],
            ["start": date("2026-10-14 08:30"), "end": date("2026-10-18 12:00"), "step_hours": 5],
            ["start": date("2026-10-17 08:30"), "end": date("2026-10-26 12:00"), "step_hours": 24],
            ["start": date("2026-10-16 20:15"), "percent_per_hour": 7],
            ["start": date("2026-10-16 20:15"), "percent_per_step": 3, "step_hours": 7],
            ["start": start, "percent_per_day": 7],
            ["start": date("2026-10-15 13:00"), "percent_per_step": 13, "step_hours": 24],
        ]
        for dict in schedules {
            let rollout = try deployment(dict)
            var previous = 0
            for halfHour in 0 ..< (2 * 24 * 7 * 8) {
                let now = start.addingTimeInterval(Double(halfHour) * 1800)
                let state = rollout.state(at: now)
                #expect(state.currentPercent >= previous)
                #expect((0 ... 100).contains(state.currentPercent))
                #expect((state.currentPercent == 100) == (state.status == .complete))

                if state.currentPercent != 100 {
                    let nextStep = try #require(state.nextStepDate)
                    let nextIncrease = try #require(state.nextIncreaseDate)
                    #expect(nextStep > now)
                    #expect(nextIncrease >= nextStep)
                    #expect(rollout.state(at: nextStep).step == (state.step ?? 0) + 1)
                    #expect(rollout.state(at: nextIncrease).currentPercent > state.currentPercent)
                    #expect(rollout.state(at: nextIncrease.addingTimeInterval(-1)).currentPercent == state.currentPercent)
                }
                previous = state.currentPercent
            }
            #expect(previous == 100)
        }
    }

    /// A step only opens on a weekend when it's the end of a start/end deployment.
    @Test func noStepOpensOnAWeekend() throws {
        let rollout = try deployment(["start": date("2026-10-16 20:00"), "percent_per_hour": 1])
        var now = date("2026-10-17 00:00")
        let friday = rollout.state(at: date("2026-10-16 23:59")).currentPercent
        #expect(friday == 4)
        while now < date("2026-10-19 00:00") {
            #expect(rollout.state(at: now).currentPercent == friday)
            now.addTimeInterval(1800)
        }
        #expect(percent(rollout, "2026-10-19 00:00") == 5)
    }
}

struct DeploymentValidationTests {
    private let start = date("2026-10-20 09:00")
    private let end = date("2026-10-20 17:00")

    private func expectInvalid(_ value: Any?, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(throws: MunkiError.self, sourceLocation: sourceLocation) {
            try Deployment(value)
        }
    }

    @Test func notADictionary() {
        expectInvalid(nil)
        expectInvalid("deployment")
        expectInvalid(["percent"])
    }

    @Test func noMode() {
        expectInvalid([String: Any]())
        expectInvalid(["start": start])
        expectInvalid(["start": start, "step_hours": 2])
    }

    @Test func moreThanOneMode() {
        expectInvalid(["start": start, "end": end, "percent_per_hour": 10])
        expectInvalid(["start": start, "end": end, "percent_per_day": 10])
        expectInvalid(["start": start, "end": end, "percent": 10])
        expectInvalid(["start": start, "percent_per_hour": 10, "percent_per_day": 10])
        expectInvalid(["start": start, "percent_per_hour": 10, "percent": 10])
        expectInvalid(["percent_per_day": 10, "percent": 10])
        expectInvalid(["start": start, "end": end, "percent_per_step": 10, "step_hours": 2])
        expectInvalid(["start": start, "percent_per_hour": 10, "percent_per_step": 10, "step_hours": 2])
        expectInvalid(["start": start, "percent_per_day": 10, "percent_per_step": 10, "step_hours": 2])
        expectInvalid(["percent": 10, "percent_per_step": 10, "step_hours": 2])
    }

    @Test func datedModeWithoutStart() {
        expectInvalid(["end": end])
        expectInvalid(["percent_per_hour": 10])
        expectInvalid(["percent_per_day": 10])
        expectInvalid(["percent_per_step": 10, "step_hours": 2])
    }

    /// Any step_hours is invalid on these, even 1, so the rule stays simple.
    @Test func hourAndDayRatesRejectStepHours() {
        for stepHours in [1, 2, 24] {
            expectInvalid(["start": start, "percent_per_hour": 10, "step_hours": stepHours])
            expectInvalid(["start": start, "percent_per_day": 10, "step_hours": stepHours])
        }
    }

    @Test func percentPerStepRequiresStepHours() {
        expectInvalid(["start": start, "percent_per_step": 10])
    }

    /// The first step is the number the admin wrote, so 100 is clear and valid.
    @Test func percentPerStepOfOneHundredIsEveryoneAtStart() throws {
        let rollout = try deployment(["start": start, "percent_per_step": 100, "step_hours": 24])
        #expect(rollout.state(at: start).currentPercent == 100)
        #expect(rollout.state(at: start).totalSteps == 1)
    }

    /// Start/end keeps step_hours, and gives the same percents as the matching percent_per_step.
    @Test func startEndCoversBatches() throws {
        let startEnd = try deployment(["start": start, "end": end, "step_hours": 2])
        let perStep = try deployment(["start": start, "percent_per_step": 20, "step_hours": 2])
        for time in ["09:00", "10:59", "11:00", "13:00", "15:00", "17:00"] {
            #expect(percent(startEnd, "2026-10-20 \(time)") == percent(perStep, "2026-10-20 \(time)"))
        }
    }

    @Test func staticWithBadStartIsInvalid() {
        expectInvalid(["start": "2026-11-05T00:00:00Z", "percent": 5])
        expectInvalid(["start": Date(timeIntervalSince1970: 1e30), "percent": 5])
    }

    @Test func endAtOrBeforeStart() {
        expectInvalid(["start": end, "end": end])
        expectInvalid(["start": end, "end": start])
    }

    @Test func badDates() {
        expectInvalid(["start": "2026-10-20T09:00:00Z", "end": end])
        expectInvalid(["start": start, "end": "2026-10-20T17:00:00Z"])
        expectInvalid(["start": 12345, "percent_per_hour": 10])
        // these would trap converting to Int if they weren't rejected
        expectInvalid(["start": Date(timeIntervalSince1970: 1e30), "percent_per_hour": 10])
        expectInvalid(["start": Date(timeIntervalSince1970: -1e30), "percent_per_hour": 10])
        expectInvalid(["start": Date(timeIntervalSince1970: .infinity), "percent_per_hour": 10])
        expectInvalid(["start": Date(timeIntervalSince1970: .nan), "percent_per_hour": 10])
        expectInvalid(["start": start, "end": Date(timeIntervalSince1970: 1e30)])
    }

    @Test func percentAndRatesOutOfRangeOrWrongType() {
        let badValues: [Any] = [0, -1, 101, 5.5, 5.0, true, "5"]
        for value in badValues {
            expectInvalid(["percent": value])
            expectInvalid(["start": start, "percent_per_hour": value])
            expectInvalid(["start": start, "percent_per_day": value])
            expectInvalid(["start": start, "percent_per_step": value, "step_hours": 2])
        }
    }

    @Test func percentAndRateBoundsAreValid() throws {
        for value in [1, 100] {
            _ = try deployment(["percent": value])
            _ = try deployment(["start": start, "percent_per_hour": value])
            _ = try deployment(["start": start, "percent_per_day": value])
            _ = try deployment(["start": start, "percent_per_step": value, "step_hours": 2])
        }
    }

    @Test func badStepHours() {
        let badValues: [Any] = [0, -1, 1.5, 2.0, true, "2"]
        for value in badValues {
            expectInvalid(["start": start, "end": end, "step_hours": value])
            expectInvalid(["start": start, "percent_per_step": 10, "step_hours": value])
        }
    }

    @Test func hugeStepHoursDoesNotOverflow() throws {
        let startEnd = try deployment(["start": start, "end": end, "step_hours": Int.max])
        #expect(startEnd.state(at: start).totalSteps == 2)
        #expect(percent(startEnd, "2026-10-20 17:00") == 100)

        let perStep = try deployment(["start": start, "percent_per_step": 1, "step_hours": Int.max])
        #expect(perStep.state(at: start).currentPercent == 1)
        #expect(perStep.state(at: start).totalSteps == 100)
    }

    @Test func farOffDatesStayFast() throws {
        // over 12 million steps, so counting conversions catches a linear search
        let rollout = try deployment(["start": start, "end": date("4000-12-31 00:00")])
        var conversions = 0
        let state = rollout.state(at: date("3000-06-05 12:00")) { date in
            conversions += 1
            return date
        }
        #expect(state.status == .inProgress)
        #expect(conversions < 64)
    }

    @Test func plistRoundTrip() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>valid</key><dict>
                <key>start</key><date>2026-10-12T00:00:00Z</date>
                <key>percent_per_step</key><integer>10</integer>
                <key>step_hours</key><integer>24</integer>
            </dict>
            <key>boolean</key><dict><key>percent</key><true/></dict>
            <key>real</key><dict><key>percent</key><real>5</real></dict>
            <key>stringDate</key><dict>
                <key>start</key><string>2026-10-12T00:00:00Z</string>
                <key>percent_per_day</key><integer>10</integer>
            </dict>
        </dict></plist>
        """
        let plist = try #require(
            PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any]
        )
        #expect(percent(try Deployment(plist["valid"]), "2026-10-13 00:00") == 20)
        expectInvalid(plist["boolean"])
        expectInvalid(plist["real"])
        expectInvalid(plist["stringDate"])
    }

    @Test func reasonsNameTheProblem() {
        let missingStart = #expect(throws: MunkiError.self) {
            try Deployment(["percent_per_day": 10])
        }
        #expect(missingStart?.description == "deployment percent_per_day requires start")
        let twoModes = #expect(throws: MunkiError.self) {
            try Deployment(["start": start, "end": end, "percent": 10])
        }
        #expect(twoModes?.description == "deployment has more than one mode: end, percent")
    }
}

struct DeployPercentHashTests {
    /// These values were calculated separately, with Python's hashlib. They must never change:
    /// if they do, machines move to different groups in every running deployment.
    @Test func hashIsStable() {
        #expect(machineDeployPercent(identifier: "C02ABC123DEF") == 89)
        #expect(machineDeployPercent(identifier: "VM0000000001") == 72)
        #expect(machineDeployPercent(identifier: "564D1234-ABCD-4EF0-9123-456789ABCDEF") == 92)
        #expect(packageDeployPercent(identifier: "C02ABC123DEF", itemName: "Firefox") == 36)
        #expect(packageDeployPercent(identifier: "C02ABC123DEF", itemName: "Zoom") == 73)
        #expect(packageDeployPercent(identifier: "VM0000000001", itemName: "Firefox") == 96)
        #expect(packageDeployPercent(identifier: "Ünï", itemName: "Fïrefox") == 75)
    }

    @Test func noIdentifierIsTheLastGroup() {
        #expect(machineDeployPercent(identifier: nil) == 100)
        #expect(packageDeployPercent(identifier: nil, itemName: "Firefox") == 100)
    }

    @Test func identifierPrefersSerial() {
        #expect(deployPercentIdentifier(serial: "ABC", hardwareUUID: "UUID") == "ABC")
        #expect(deployPercentIdentifier(serial: nil, hardwareUUID: "UUID") == "UUID")
        #expect(deployPercentIdentifier(serial: "", hardwareUUID: "UUID") == "UUID")
        #expect(deployPercentIdentifier(serial: "UNKNOWN", hardwareUUID: "UUID") == "UUID")
        #expect(deployPercentIdentifier(serial: "UNKNOWN", hardwareUUID: "") == nil)
        #expect(deployPercentIdentifier(serial: nil, hardwareUUID: nil) == nil)
    }

    /// The groups need to be about even, or a "10%" step won't reach about 10% of machines.
    /// The input is fixed, so this can't be flaky.
    @Test func valuesAreSpreadEvenly() {
        var counts = [Int: Int]()
        var saltedCounts = [Int: Int]()
        for index in 0 ..< 100_000 {
            let identifier = "SERIAL\(index)"
            counts[machineDeployPercent(identifier: identifier), default: 0] += 1
            saltedCounts[packageDeployPercent(identifier: identifier, itemName: "Firefox"), default: 0] += 1
        }
        for buckets in [counts, saltedCounts] {
            #expect(buckets.count == 100)
            #expect(buckets.keys.min() == 1)
            #expect(buckets.keys.max() == 100)
            #expect(buckets.values.allSatisfy { (850 ... 1150).contains($0) })
        }
    }

    /// Different items need different first groups.
    @Test func saltingChangesWhoGoesFirst() {
        let identifiers = (0 ..< 10000).map { "SERIAL\($0)" }
        let firefoxFirst = identifiers.filter { packageDeployPercent(identifier: $0, itemName: "Firefox") <= 10 }
        let zoomFirst = Set(identifiers.filter { packageDeployPercent(identifier: $0, itemName: "Zoom") <= 10 })
        let overlap = firefoxFirst.filter { zoomFirst.contains($0) }.count
        // independent groups of 10% overlap by about 10%
        #expect(Double(overlap) / Double(firefoxFirst.count) < 0.15)
    }
}

/// C02ABC123DEF's package_deploy_percent is 36 for Firefox and 73 for Zoom.
private let testSerial = "C02ABC123DEF"
private let testCatalogs = ["deployment_tests"]
private let notStarted: [String: Any] = ["start": date("2099-01-05 00:00"), "percent": 100]
private let installedPath = "/bin/ls"
private let missingPath = "/private/tmp/munki-deployment-tests-does-not-exist"
/// Some version is on disk, but not this one: the file exists with a different checksum.
private let otherVersionInstalled: PlistDict = [
    "installs": [["type": "file", "path": installedPath, "md5checksum": "00000000000000000000000000000000"]],
]

private func seedCatalog(_ items: [PlistDict], serial: String? = testSerial, uuid: String? = nil) {
    var facts: PlistDict = ["os_vers": "15.0", "arch": "arm64", "munki_version": "7.5.0"]
    facts["serial_number"] = serial
    facts["hardware_uuid"] = uuid
    MachineFacts.shared.facts = facts
    Catalogs.shared.set(testCatalogs[0], to: makeCatalogDB(items))
    DeploymentRecords.shared.reset()
}

/// A nopkg item, so nothing downloads. It's "installed" if its path exists.
private func item(
    _ name: String,
    _ version: String,
    percent: Int? = nil,
    deployment: [String: Any]? = nil,
    path: String = missingPath,
    extra: PlistDict = [:]
) -> PlistDict {
    var pkginfo: PlistDict = [
        "name": name,
        "version": version,
        "installer_type": "nopkg",
        "installs": [["type": "file", "path": path]],
    ]
    if let percent {
        pkginfo["deployment"] = ["percent": percent]
    }
    if let deployment {
        pkginfo["deployment"] = deployment
    }
    return pkginfo.merging(extra) { _, new in new }
}

private func lookup(
    _ name: String,
    skipMinimumOSCheck: Bool = false,
    skipDeploymentCheck: Bool = false
) async -> String? {
    let pkginfo = await getItemDetail(
        name,
        catalogList: testCatalogs,
        skipMinimumOSCheck: skipMinimumOSCheck,
        suppressWarnings: true,
        skipDeploymentCheck: skipDeploymentCheck
    )
    return pkginfo?["version"] as? String
}

private func entry(_ installInfo: PlistDict, _ name: String) -> PlistDict? {
    let entries = (installInfo["managed_installs"] as? [PlistDict] ?? []).filter { $0["name"] as? String == name }
    #expect(entries.count <= 1)
    return entries.first
}

/// All of these share singletons, so they can't run at the same time.
@Suite(.serialized) struct DeploymentClientTests {
    // MARK: catalog lookup

    @Test func eligibleAtOrBelowTheCurrentPercent() async {
        seedCatalog([item("Firefox", "2.0", percent: 36), item("Firefox", "1.0")])
        #expect(await lookup("Firefox") == "2.0")

        seedCatalog([item("Firefox", "2.0", percent: 35), item("Firefox", "1.0")])
        #expect(await lookup("Firefox") == "1.0")
    }

    @Test func fallsBackToNextHighestEligibleVersion() async {
        seedCatalog([item("Firefox", "3.0", percent: 1), item("Firefox", "2.0", percent: 50), item("Firefox", "1.0")])
        #expect(await lookup("Firefox") == "2.0")
    }

    @Test func noEligibleVersionIsWaitingNotAProblem() async {
        seedCatalog([item("Firefox", "2.0", percent: 1)])
        #expect(await lookup("Firefox") == nil)
        #expect(DeploymentRecords.shared.isWaiting("Firefox"))
    }

    @Test func aSpecificVersionHasNoFallback() async {
        seedCatalog([item("Firefox", "2.0", percent: 1), item("Firefox", "1.0")])
        #expect(await lookup("Firefox--2.0") == nil)
        #expect(DeploymentRecords.shared.isWaiting("Firefox"))
    }

    @Test func noMachineIsEligibleBeforeStart() async {
        seedCatalog([item("Firefox", "2.0", deployment: notStarted)])
        #expect(await lookup("Firefox") == nil)
    }

    @Test func invalidDeploymentFailsClosed() async {
        seedCatalog([item("Firefox", "2.0", deployment: ["percent": 0]), item("Firefox", "1.0")])
        #expect(await lookup("Firefox") == "1.0")
        seedCatalog([item("Firefox", "2.0", deployment: ["percent": 0])])
        #expect(await lookup("Firefox") == nil)
        #expect(DeploymentRecords.shared.isWaiting("Firefox"))
    }

    @Test func waitingFollowsTheLatestLookup() async {
        seedCatalog([item("Firefox", "2.0", percent: 1), item("Firefox", "1.0")])
        #expect(await lookup("Firefox--2.0") == nil)
        #expect(DeploymentRecords.shared.isWaiting("Firefox"))
        // found a version
        #expect(await lookup("Firefox") == "1.0")
        #expect(!DeploymentRecords.shared.isWaiting("Firefox"))

        #expect(await lookup("Firefox--2.0") == nil)
        #expect(DeploymentRecords.shared.isWaiting("Firefox"))
        // nothing found, and not because of a deployment
        #expect(await lookup("Firefox--9.9") == nil)
        #expect(!DeploymentRecords.shared.isWaiting("Firefox"))
    }

    @Test func namesWithHyphensAreNotConfused() async {
        seedCatalog([item("Foo-2", "5.0", percent: 1, path: installedPath), item("Foo", "1.0")])
        var installInfo = PlistDict()
        _ = await processInstall("Foo-2--5.0", catalogList: testCatalogs, installInfo: &installInfo)
        _ = await processInstall("Foo", catalogList: testCatalogs, installInfo: &installInfo)
        #expect(entry(installInfo, "Foo")?["version_to_install"] as? String == "1.0")
    }

    @Test func otherChecksComeFirst() async {
        seedCatalog([
            item("Firefox", "3.0", percent: 1, extra: ["minimum_os_version": "99.0"]),
            item("Firefox", "2.0", percent: 1, extra: ["supported_architectures": ["x86_64"]]),
            item("Firefox", "1.5", percent: 1, extra: ["minimum_munki_version": "99.0"]),
            item("Firefox", "1.0"),
        ])
        #expect(await lookup("Firefox") == "1.0")
        #expect(DeploymentRecords.shared.logged.isEmpty)
    }

    @Test func anotherRejectionStillCountsAsAProblem() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 1),
            item("Firefox", "1.0", extra: ["minimum_os_version": "99.0"]),
        ])
        #expect(await lookup("Firefox") == nil)
        #expect(!DeploymentRecords.shared.isWaiting("Firefox"))
    }

    @Test func removalLookupsSkipTheCheck() async {
        seedCatalog([item("Firefox", "2.0", percent: 1)])
        #expect(await lookup("Firefox", skipDeploymentCheck: true) == "2.0")
    }

    /// The "Requires macOS X" lookup: a machine that isn't eligible doesn't see the version.
    @Test func skippingMinimumOSDoesNotSkipTheDeployment() async {
        seedCatalog([item("Firefox", "2.0", percent: 1, extra: ["minimum_os_version": "99.0"])])
        #expect(await lookup("Firefox", skipMinimumOSCheck: true) == nil)

        seedCatalog([item("Firefox", "2.0", percent: 36, extra: ["minimum_os_version": "99.0"])])
        #expect(await lookup("Firefox", skipMinimumOSCheck: true) == "2.0")
    }

    @Test func noIdentifierIsTheLastGroup() async {
        seedCatalog([item("Firefox", "2.0", percent: 99), item("Firefox", "1.0")], serial: "UNKNOWN", uuid: "")
        #expect(await lookup("Firefox") == "1.0")

        seedCatalog([item("Firefox", "2.0", percent: 100), item("Firefox", "1.0")], serial: "UNKNOWN", uuid: "")
        #expect(await lookup("Firefox") == "2.0")
    }

    @Test func fallsBackToHardwareUUID() async {
        let uuid = "564D1234-ABCD-4EF0-9123-456789ABCDEF"
        let percent = packageDeployPercent(identifier: uuid, itemName: "Firefox")
        seedCatalog([item("Firefox", "2.0", percent: percent), item("Firefox", "1.0")], serial: "UNKNOWN", uuid: uuid)
        #expect(await lookup("Firefox") == "2.0")
    }

    // MARK: overrides

    @Test func overridePrecedence() {
        #expect(deployPercentOverride(commandLine: nil, preference: nil) == nil)
        #expect(deployPercentOverride(commandLine: nil, preference: 5)?.value == 5)
        #expect(deployPercentOverride(commandLine: nil, preference: 5)?.source == "preference")
        #expect(deployPercentOverride(commandLine: 9, preference: 5)?.value == 9)
        #expect(deployPercentOverride(commandLine: 9, preference: 5)?.source == "command_line")
    }

    @Test func preferenceOutOfRangeIsIgnored() {
        for preference in [0, -1, 101] {
            #expect(deployPercentOverride(commandLine: nil, preference: preference) == nil)
        }
        #expect(deployPercentOverride(commandLine: nil, preference: 1)?.value == 1)
        #expect(deployPercentOverride(commandLine: nil, preference: 100)?.value == 100)
    }

    @Test func overrideOneGetsEveryStartedDeployment() async {
        seedCatalog([item("Firefox", "2.0", percent: 1), item("Firefox", "1.0")])
        DeploymentRecords.shared.commandLineDeployPercent = 1
        #expect(await lookup("Firefox") == "2.0")
    }

    @Test func overrideOneHundredSkipsAnythingBelowOneHundred() async {
        seedCatalog([item("Firefox", "2.0", percent: 99), item("Firefox", "1.0")])
        DeploymentRecords.shared.commandLineDeployPercent = 100
        #expect(await lookup("Firefox") == "1.0")

        seedCatalog([item("Firefox", "2.0", percent: 100), item("Firefox", "1.0")])
        DeploymentRecords.shared.commandLineDeployPercent = 100
        #expect(await lookup("Firefox") == "2.0")
    }

    @Test func overrideDoesNotInstallBeforeStart() async {
        seedCatalog([item("Firefox", "2.0", deployment: notStarted), item("Firefox", "1.0")])
        DeploymentRecords.shared.commandLineDeployPercent = 1
        #expect(await lookup("Firefox") == "1.0")
    }

    @Test func overrideDoesNotUseTheHash() async {
        // Firefox hashes to 36 and Zoom to 73 on this machine, but the override applies to both
        seedCatalog([item("Firefox", "2.0", percent: 50), item("Zoom", "2.0", percent: 50)])
        DeploymentRecords.shared.commandLineDeployPercent = 50
        #expect(await lookup("Firefox") == "2.0")
        #expect(await lookup("Zoom") == "2.0")
    }

    // MARK: deploy_percent fact

    @Test func factIsTheUnsaltedValue() {
        DeploymentRecords.shared.reset()
        #expect(deployPercentFact(machine: ["serial_number": testSerial]) == 89)
    }

    @Test func factWithNoIdentifierIsTheLastGroup() {
        DeploymentRecords.shared.reset()
        #expect(deployPercentFact(machine: ["serial_number": "UNKNOWN", "hardware_uuid": ""]) == 100)
    }

    @Test func factUsesTheOverride() {
        DeploymentRecords.shared.reset()
        DeploymentRecords.shared.commandLineDeployPercent = 7
        #expect(deployPercentFact(machine: ["serial_number": testSerial]) == 7)
        DeploymentRecords.shared.reset()
    }

    @Test func predicateInfoIncludesTheFact() async {
        seedCatalog([])
        DeploymentRecords.shared.commandLineDeployPercent = 7
        defer { DeploymentRecords.shared.reset() }
        #expect(await generatePredicateInfo()["deploy_percent"] as? Int == 7)
    }

    @Test func installableConditionCanUseTheFact() async {
        let condition: PlistDict = ["installable_condition": "deploy_percent <= 10"]
        defer { PredicateInfo.shared.info = PlistDict() }

        PredicateInfo.shared.info = ["deploy_percent": 5]
        seedCatalog([item("Firefox", "2.0", extra: condition), item("Firefox", "1.0")])
        #expect(await lookup("Firefox") == "2.0")

        PredicateInfo.shared.info = ["deploy_percent": 50]
        seedCatalog([item("Firefox", "2.0", extra: condition), item("Firefox", "1.0")])
        #expect(await lookup("Firefox") == "1.0")
    }

    // MARK: report entries

    private func reportEntry(_ name: String, _ version: String) -> PlistDict? {
        return deploymentReportEntries().first {
            $0["name"] as? String == name && $0["version"] as? String == version
        }
    }

    @Test func reportEntryForAVersionNotEligibleFor() async throws {
        seedCatalog([
            item("Firefox", "2.0", deployment: ["start": date("2099-01-05 00:00"), "percent_per_hour": 10]),
            item("Firefox", "1.0"),
        ])
        _ = await lookup("Firefox")
        let found = try #require(reportEntry("Firefox", "2.0"))
        #expect(found["package_deploy_percent"] as? Int == 36)
        #expect(found["current_deploy_percent"] as? Int == 0)
        #expect(found["eligible"] as? Bool == false)
        #expect(found["next_step_date"] is Date)
        #expect(found["required_by"] == nil)
    }

    @Test func reportEntryForAnEligibleVersion() async throws {
        seedCatalog([item("Firefox", "2.0", percent: 50)])
        _ = await lookup("Firefox")
        let found = try #require(reportEntry("Firefox", "2.0"))
        #expect(found["current_deploy_percent"] as? Int == 50)
        #expect(found["eligible"] as? Bool == true)
        // a static deployment has no next step
        #expect(found["next_step_date"] == nil)
    }

    /// With over 100 steps a step can leave the percent unchanged. This is when it next rises.
    @Test func reportNextStepDateIsWhenThePercentNextRises() async throws {
        seedCatalog([item("Firefox", "2.0", deployment: ["start": date("2026-10-12 00:00"), "end": date("2026-10-24 00:00")])])
        DeploymentRecords.shared.now = subtractTZOffsetFromDate(date("2026-10-14 09:30"))
        _ = await lookup("Firefox")
        let found = try #require(reportEntry("Firefox", "2.0"))
        #expect(found["current_deploy_percent"] as? Int == 25)
        #expect(found["next_step_date"] as? Date == subtractTZOffsetFromDate(date("2026-10-14 12:00")))
    }

    @Test func noReportEntryWhenInstallableConditionFailsFirst() async {
        defer { PredicateInfo.shared.info = PlistDict() }
        PredicateInfo.shared.info = ["deploy_percent": 50]
        seedCatalog([item("Firefox", "2.0", percent: 1, extra: ["installable_condition": "deploy_percent <= 10"])])
        _ = await lookup("Firefox")
        #expect(deploymentReportEntries().isEmpty)
    }

    @Test func reportHasOneEntryPerVersion() async {
        seedCatalog([item("Firefox", "2.0", percent: 1), item("Firefox", "1.0", percent: 50), item("Firefox", "0.9")])
        _ = await lookup("Firefox")
        _ = await lookup("Firefox")
        // 0.9 has no deployment, so it has no entry
        #expect(deploymentReportEntries().map { $0["version"] as? String } == ["1.0", "2.0"])
    }

    @Test func reportEntryUsesTheOverride() async throws {
        seedCatalog([item("Firefox", "2.0", percent: 50)])
        DeploymentRecords.shared.commandLineDeployPercent = 7
        _ = await lookup("Firefox")
        #expect(try #require(reportEntry("Firefox", "2.0"))["package_deploy_percent"] as? Int == 7)
    }

    @Test func noReportEntryWhenAnotherCheckFailsFirst() async {
        seedCatalog([item("Firefox", "2.0", percent: 1, extra: ["minimum_os_version": "99.0"])])
        _ = await lookup("Firefox")
        #expect(deploymentReportEntries().isEmpty)
    }

    @Test func noReportEntryWhenTheCheckIsSkipped() async {
        seedCatalog([item("Firefox", "2.0", percent: 1)])
        _ = await lookup("Firefox", skipDeploymentCheck: true)
        #expect(deploymentReportEntries().isEmpty)
    }

    @Test func noReportEntryForAnInvalidDeployment() async {
        seedCatalog([item("Firefox", "2.0", deployment: ["percent": 0])])
        _ = await lookup("Firefox")
        #expect(deploymentReportEntries().isEmpty)
    }

    @Test func autoremoveChecksDoNotAddReportEntries() async {
        seedCatalog([item("Firefox", "2.0", percent: 1, extra: ["autoremove": true])])
        _ = await getAutoRemovalItems(installInfo: PlistDict(), catalogList: testCatalogs)
        #expect(deploymentReportEntries().isEmpty)
    }

    /// The report is saved as a plist, and one bad value stops it saving.
    @Test func reportEntriesCanBeSavedAsAPlist() async throws {
        seedCatalog([
            item("Firefox", "2.0", deployment: ["start": date("2099-01-05 00:00"), "percent_per_hour": 10]),
            item("Firefox", "1.0"),
        ])
        _ = await lookup("Firefox")
        let plist: PlistDict = ["Deployments": deploymentReportEntries()]
        _ = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    // MARK: autoremove

    private func autoRemovals() async -> [String] {
        return await getAutoRemovalItems(installInfo: PlistDict(), catalogList: testCatalogs)
    }

    @Test func autoremoveOnAVersionNotEligibleForDoesNotCount() async {
        seedCatalog([item("Firefox", "2.0", percent: 1, extra: ["autoremove": true]), item("Firefox", "1.0")])
        #expect(await autoRemovals() == [])
    }

    @Test func autoremoveCountsOnceEligible() async {
        seedCatalog([item("Firefox", "2.0", percent: 36, extra: ["autoremove": true]), item("Firefox", "1.0")])
        #expect(await autoRemovals() == ["Firefox"])
    }

    @Test func autoremoveOnAnEligibleOlderVersionStillCounts() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 1, extra: ["autoremove": true]),
            item("Firefox", "1.0", extra: ["autoremove": true]),
        ])
        #expect(await autoRemovals() == ["Firefox"])
    }

    @Test func autoremoveSkipsAnItemWaitingOnWhatItRequires() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom"], "autoremove": true]),
            item("Zoom", "2.0", deployment: notStarted),
        ])
        var installInfo = PlistDict()
        _ = await processInstall("Firefox", catalogList: testCatalogs, installInfo: &installInfo)
        #expect(await getAutoRemovalItems(installInfo: installInfo, catalogList: testCatalogs) == [])
    }

    @Test func autoremoveDoesNotConfuseHyphenatedNames() async {
        seedCatalog([item("Foo", "2.0", percent: 1), item("Foo-2", "1.0", extra: ["autoremove": true])])
        _ = await lookup("Foo")
        #expect(DeploymentRecords.shared.isWaiting("Foo"))
        #expect(await getAutoRemovalItems(installInfo: PlistDict(), catalogList: testCatalogs) == ["Foo-2"])
    }

    @Test func autoremoveSkipsAPinnedVersionNotEligibleFor() async {
        seedCatalog([item("Firefox", "2.0", percent: 1), item("Firefox", "1.0", extra: ["autoremove": true])])
        var installInfo = PlistDict()
        _ = await processInstall("Firefox--2.0", catalogList: testCatalogs, installInfo: &installInfo)
        #expect(await getAutoRemovalItems(installInfo: installInfo, catalogList: testCatalogs) == [])
    }

    // MARK: installs

    private func install(_ name: String) async -> (Bool, PlistDict) {
        var installInfo = PlistDict()
        let result = await processInstall(name, catalogList: testCatalogs, installInfo: &installInfo)
        return (result, installInfo)
    }

    @Test func eligibleInstallsNewestDirectly() async {
        seedCatalog([item("Firefox", "2.0", percent: 36), item("Firefox", "1.0")])
        let (result, installInfo) = await install("Firefox")
        #expect(result)
        #expect(entry(installInfo, "Firefox")?["version_to_install"] as? String == "2.0")
    }

    @Test func notEligibleInstallsTheOlderVersion() async {
        seedCatalog([item("Firefox", "2.0", percent: 1), item("Firefox", "1.0")])
        let (result, installInfo) = await install("Firefox")
        #expect(result)
        #expect(entry(installInfo, "Firefox")?["version_to_install"] as? String == "1.0")
    }

    @Test func noEligibleVersionInstallsNothing() async {
        seedCatalog([item("Firefox", "2.0", percent: 1)])
        let (result, installInfo) = await install("Firefox")
        #expect(!result)
        #expect(entry(installInfo, "Firefox") == nil)
    }

    @Test func aVersionWithoutADeploymentInstallsNow() async {
        seedCatalog([item("Firefox", "1.2", percent: 1), item("Firefox", "1.1"), item("Firefox", "1.0", path: installedPath)])
        let (_, installInfo) = await install("Firefox")
        #expect(entry(installInfo, "Firefox")?["version_to_install"] as? String == "1.1")
    }

    @Test func forceInstallDateOnlyAppliesOnceEligible() async {
        let forced: PlistDict = ["force_install_after_date": date("2020-01-06 00:00")]
        seedCatalog([item("Firefox", "2.0", percent: 1, extra: forced), item("Firefox", "1.0")])
        let (_, before) = await install("Firefox")
        #expect(entry(before, "Firefox")?["force_install_after_date"] == nil)

        seedCatalog([item("Firefox", "2.0", percent: 36, extra: forced), item("Firefox", "1.0")])
        let (_, after) = await install("Firefox")
        #expect(entry(after, "Firefox")?["force_install_after_date"] != nil)
    }

    // MARK: required packages

    /// A deployment only makes a version available or not, so what's required follows its own.
    @Test func aRequirementFollowsItsOwnDeployment() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom"]]),
            item("Zoom", "2.0", percent: 1),
            item("Zoom", "1.0"),
        ])
        let (result, installInfo) = await install("Firefox")
        #expect(result)
        #expect(entry(installInfo, "Zoom")?["version_to_install"] as? String == "1.0")
        #expect(entry(installInfo, "Firefox")?["version_to_install"] as? String == "2.0")
    }

    @Test func itemWaitsWhenMachineIsNotEligibleForWhatItRequires() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom"]]),
            item("Zoom", "2.0", percent: 1),
        ])
        let (result, installInfo) = await install("Firefox")
        #expect(!result)
        #expect(entry(installInfo, "Firefox") == nil)
    }

    /// Munki's normal checks decide, the same as a version rejected by any other check.
    @Test func normalChecksDecideWhenANewerVersionIsNotEligible() async {
        seedCatalog([item("Firefox", "2.0", percent: 1, path: installedPath), item("Firefox", "1.0", path: missingPath)])
        let (_, installInfo) = await install("Firefox")
        #expect(entry(installInfo, "Firefox")?["version_to_install"] as? String == "1.0")
    }

    @Test func itemWithoutADeploymentDoesNotBringAnythingAlong() async {
        seedCatalog([
            item("Firefox", "1.0", extra: ["requires": ["Zoom"]]),
            item("Zoom", "2.0", percent: 1),
            item("Zoom", "1.0"),
        ])
        let (_, installInfo) = await install("Firefox")
        #expect(entry(installInfo, "Zoom")?["version_to_install"] as? String == "1.0")
    }

    @Test func updateForDoesNotFollow() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36),
            item("Zoom", "2.0", percent: 1, extra: ["update_for": ["Firefox"]]),
            item("Zoom", "1.0", extra: ["update_for": ["Firefox"]]),
        ])
        let (_, installInfo) = await install("Firefox")
        #expect(entry(installInfo, "Zoom")?["version_to_install"] as? String == "1.0")
    }

    @Test func itemWaitsWhenWhatItRequiresHasNotStarted() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom"]]),
            item("Zoom", "2.0", deployment: notStarted),
        ])
        let (result, installInfo) = await install("Firefox")
        #expect(!result)
        // no entry means no problem item, and it installs once Zoom's deployment starts
        #expect(entry(installInfo, "Firefox") == nil)
        #expect(entry(installInfo, "Zoom") == nil)
        #expect(DeploymentRecords.shared.isWaiting("Firefox"))
    }

    @Test func waitingCarriesUpAChain() async {
        seedCatalog([
            item("Top", "1.0", extra: ["requires": ["Firefox"]]),
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom"]]),
            item("Zoom", "2.0", deployment: notStarted),
        ])
        let (result, installInfo) = await install("Top")
        #expect(!result)
        #expect(entry(installInfo, "Top") == nil)
        #expect(DeploymentRecords.shared.isWaiting("Top"))
    }

    @Test func itemWaitsWhenWhatItRequiresIsInvalid() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom"]]),
            item("Zoom", "2.0", deployment: ["percent": 0]),
        ])
        let (result, installInfo) = await install("Firefox")
        #expect(!result)
        #expect(entry(installInfo, "Firefox") == nil)
    }

    @Test func waitingWorksForARequirementWithAPath() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["apps/Zoom"]]),
            item("Zoom", "2.0", deployment: notStarted),
        ])
        let (result, installInfo) = await install("Firefox")
        #expect(!result)
        #expect(entry(installInfo, "Firefox") == nil)
    }

    @Test func aRealDependencyProblemIsStillAProblem() async {
        seedCatalog([item("Firefox", "2.0", percent: 36, extra: ["requires": ["DoesNotExist"]])])
        let (result, installInfo) = await install("Firefox")
        #expect(!result)
        #expect(entry(installInfo, "Firefox")?["note"] != nil)
    }

    @Test func anOrdinaryPinnedRequirementStillBehavesAsBefore() async {
        seedCatalog([
            item("Firefox", "2.0", extra: ["requires": ["Zoom--3.0"]]),
            item("Zoom", "1.0"),
        ])
        var installInfo = PlistDict()
        _ = await processInstall("Zoom", catalogList: testCatalogs, installInfo: &installInfo)
        let result = await processInstall("Firefox", catalogList: testCatalogs, installInfo: &installInfo)
        #expect(result)
    }

    /// An admin may want Zoom 2.0 and 3.0 both installed at different paths. Pinning 2.0 means
    /// 2.0, as it always has, whatever else is installed and whatever was looked up first.
    @Test func aPinnedVersionInstallsAlongsideANewerOne() async {
        let items = [
            item("Zoom", "3.0", deployment: notStarted, path: installedPath),
            item("Zoom", "2.0", path: missingPath),
        ]
        seedCatalog(items)
        let (result, installInfo) = await install("Zoom--2.0")
        #expect(result)
        #expect(entry(installInfo, "Zoom")?["version_to_install"] as? String == "2.0")

        seedCatalog(items)
        _ = await lookup("Zoom")
        let (_, afterLookup) = await install("Zoom--2.0")
        #expect(entry(afterLookup, "Zoom")?["version_to_install"] as? String == "2.0")
    }

    /// With no deployment anywhere, all of this has to match Munki's existing behavior.
    @Test func itemsWithoutADeploymentAreUntouched() async {
        seedCatalog([
            item("Firefox", "2.0", extra: ["requires": ["Zoom--3.0"], "autoremove": true]),
            item("Zoom", "2.0", path: installedPath),
            item("Zoom", "1.0"),
        ])
        var installInfo = PlistDict()
        _ = await processInstall("Zoom", catalogList: testCatalogs, installInfo: &installInfo)
        // existing behavior: any processed version counts as meeting a pinned requirement
        #expect(await processInstall("Firefox", catalogList: testCatalogs, installInfo: &installInfo))
        #expect(DeploymentRecords.shared.logged.isEmpty)
        #expect(DeploymentRecords.shared.waiting.isEmpty)
        #expect(deploymentReportEntries().isEmpty)
        #expect(await getAutoRemovalItems(installInfo: PlistDict(), catalogList: testCatalogs) == ["Firefox"])
    }

    @Test func aWaitingAndAFailingRequirementIsStillAProblem() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom", "DoesNotExist"]]),
            item("Zoom", "2.0", deployment: notStarted),
        ])
        let (result, installInfo) = await install("Firefox")
        #expect(!result)
        #expect(entry(installInfo, "Firefox")?["note"] != nil)
    }

    // MARK: removals

    private let removable: PlistDict = [
        "uninstallable": true, "uninstall_method": "uninstall_script", "uninstall_script": "#!/bin/sh\n",
    ]

    /// Removals are never gated, even for a version this machine isn't eligible for.
    @Test func removingASpecificVersionIgnoresItsDeployment() async {
        seedCatalog([item("Firefox", "2.0", percent: 1, path: installedPath, extra: removable)])
        var installInfo = PlistDict()
        _ = await processRemoval("Firefox--2.0", catalogList: testCatalogs, installInfo: &installInfo)
        let removals = installInfo["removals"] as? [PlistDict] ?? []
        #expect(removals.contains { $0["name"] as? String == "Firefox" })
    }

    /// Munki's existing rule: an item already processed counts as meeting an unpinned requirement,
    /// and a deployment doesn't change the install list once it's built.
    @Test func aRequirementLeavesAVersionProcessedEarlier() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom"]]),
            item("Zoom", "2.0", percent: 1),
            item("Zoom", "1.0"),
        ])
        var installInfo = PlistDict()
        _ = await processInstall("Zoom", catalogList: testCatalogs, installInfo: &installInfo)
        #expect(await processInstall("Firefox", catalogList: testCatalogs, installInfo: &installInfo))
        let order = (installInfo["managed_installs"] as? [PlistDict] ?? []).map { $0["version_to_install"] as? String }
        #expect(order == ["1.0", "2.0"])
    }

    /// Munki's existing rule: any processed version counts as meeting a pinned requirement, and
    /// the first one processed wins. A deployment on the version doesn't change that.
    @Test func aProcessedVersionMeetsAPinnedRequirement() async {
        for zoom3 in [item("Zoom", "3.0", percent: 1), item("Zoom", "3.0", deployment: notStarted)] {
            seedCatalog([
                item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom--3.0"]]),
                zoom3,
                item("Zoom", "1.0"),
            ])
            var installInfo = PlistDict()
            _ = await processInstall("Zoom", catalogList: testCatalogs, installInfo: &installInfo)
            #expect(await processInstall("Firefox", catalogList: testCatalogs, installInfo: &installInfo))
            #expect(entry(installInfo, "Zoom")?["version_to_install"] as? String == "1.0")
            #expect(entry(installInfo, "Firefox")?["version_to_install"] as? String == "2.0")
        }
    }

    /// The first one processed wins here too: the requirement's version, then the manifest's is skipped.
    @Test func aPinnedRequirementProcessedFirstWins() async {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: ["requires": ["Zoom--2.0"]]),
            item("Zoom", "2.0"),
            item("Zoom", "1.0"),
        ])
        var installInfo = PlistDict()
        _ = await processInstall("Firefox", catalogList: testCatalogs, installInfo: &installInfo)
        #expect(await processInstall("Zoom--1.0", catalogList: testCatalogs, installInfo: &installInfo))
        #expect(entry(installInfo, "Zoom")?["version_to_install"] as? String == "2.0")
    }

    // MARK: managed updates

    @Test func managedUpdateWaitsForEligibility() async {
        seedCatalog([item("Firefox", "2.0", percent: 1, extra: otherVersionInstalled), item("Firefox", "1.0", path: installedPath)])
        var installInfo = PlistDict()
        await processManagedUpdate("Firefox", catalogList: testCatalogs, installInfo: &installInfo)
        #expect(entry(installInfo, "Firefox")?["installed"] as? Bool == true)
        #expect(entry(installInfo, "Firefox")?["version_to_install"] == nil)
    }

    @Test func managedUpdateOffersTheVersionOnceEligible() async {
        seedCatalog([item("Firefox", "2.0", percent: 36, extra: otherVersionInstalled), item("Firefox", "1.0", path: installedPath)])
        var installInfo = PlistDict()
        await processManagedUpdate("Firefox", catalogList: testCatalogs, installInfo: &installInfo)
        #expect(entry(installInfo, "Firefox")?["version_to_install"] as? String == "2.0")
    }

    // MARK: optional installs

    private func optional(_ name: String) async -> PlistDict? {
        var installInfo = PlistDict()
        await processOptionalInstall(name, catalogList: testCatalogs, installInfo: &installInfo)
        let entries = installInfo["optional_installs"] as? [PlistDict] ?? []
        return entries.first { $0["name"] as? String == name }
    }

    /// 1.0 is installed and 2.0 is rolling out. Only 1.0 is available, and it can be uninstalled.
    @Test func optionalOffersOnlyTheEligibleVersion() async throws {
        seedCatalog([
            item("Firefox", "2.0", percent: 1, path: missingPath),
            item("Firefox", "1.0", path: installedPath, extra: ["uninstallable": true, "uninstall_method": "uninstall_script"]),
        ])
        let found = try #require(await optional("Firefox"))
        #expect(found["version_to_install"] as? String == "1.0")
        #expect(found["installed"] as? Bool == true)
        #expect(found["needs_update"] as? Bool == false)
        #expect(found["uninstallable"] as? Bool == true)
    }

    @Test func optionalOffersTheUpdateOnceEligible() async throws {
        seedCatalog([
            item("Firefox", "2.0", percent: 36, extra: otherVersionInstalled),
            item("Firefox", "1.0", path: installedPath),
        ])
        let found = try #require(await optional("Firefox"))
        #expect(found["version_to_install"] as? String == "2.0")
        #expect(found["needs_update"] as? Bool == true)
    }

    @Test func optionalWithNoEligibleVersionIsNotListed() async {
        seedCatalog([item("Firefox", "2.0", percent: 1)])
        #expect(await optional("Firefox") == nil)
    }
}
