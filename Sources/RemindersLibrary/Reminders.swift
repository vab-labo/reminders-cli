import ArgumentParser
import EventKit
import Foundation

/// Stores URL in the notes field because EventKit's EKReminder.url
/// doesn't sync with the Reminders.app UI (Apple platform bug).
/// https://developer.apple.com/forums/thread/128140
enum NoteUrl {
    /// Extract user content and URL from combined notes string.
    /// Format: "content\n\nURL: https://..."
    static func extract(from notes: String?) -> (content: String?, url: String?) {
        guard let notes = notes, !notes.isEmpty else { return (nil, nil) }

        if let range = notes.range(of: "\n\nURL: ", options: .backwards) {
            let content = String(notes[..<range.lowerBound])
            let url = String(notes[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (content.isEmpty ? nil : content, url.isEmpty ? nil : url)
        }

        if notes.hasPrefix("URL: ") {
            let url = String(notes.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            return (nil, url.isEmpty ? nil : url)
        }

        return (notes, nil)
    }

    /// Combine user content and URL into a single notes string.
    static func combine(content: String?, url: String?) -> String? {
        let c = content?.isEmpty == false ? content : nil
        let u = url?.isEmpty == false ? url : nil
        switch (c, u) {
        case (nil, nil): return nil
        case (let c?, nil): return c
        case (nil, let u?): return "URL: \(u)"
        case (let c?, let u?): return "\(c)\n\nURL: \(u)"
        }
    }
}

private let Store = EKEventStore()
private let dateFormatter = RelativeDateTimeFormatter()
private func formattedDueDate(from reminder: EKReminder) -> String? {
    guard let components = reminder.dueDateComponents, let date = components.date else { return nil }
    let relative = dateFormatter.localizedString(for: date, relativeTo: Date())
    if let hour = components.hour {
        let minute = components.minute ?? 0
        return String(format: "%@ %02d:%02d", relative, hour, minute)
    }
    return relative
}

private extension EKReminder {
    var mappedPriority: EKReminderPriority {
        UInt(exactly: self.priority).flatMap(EKReminderPriority.init) ?? EKReminderPriority.none
    }

    /// First time-based alarm (not location-based)
    var firstTimeAlarm: EKAlarm? {
        self.alarms?.first { $0.structuredLocation == nil }
    }
}

public enum Recurrence: String, ExpressibleByArgument, CaseIterable {
    case daily, weekdays, weekly, biweekly, monthly, yearly

    public static let commaSeparatedCases = Self.allCases.map { $0.rawValue }.joined(separator: ", ")

    func toRule() -> EKRecurrenceRule {
        switch self {
        case .daily:
            return EKRecurrenceRule(
                recurrenceWith: .daily, interval: 1,
                daysOfTheWeek: nil, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil)
        case .weekdays:
            let weekdays = [
                EKRecurrenceDayOfWeek(.monday),
                EKRecurrenceDayOfWeek(.tuesday),
                EKRecurrenceDayOfWeek(.wednesday),
                EKRecurrenceDayOfWeek(.thursday),
                EKRecurrenceDayOfWeek(.friday),
            ]
            return EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1,
                daysOfTheWeek: weekdays, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil)
        case .weekly:
            return EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1,
                daysOfTheWeek: nil, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil)
        case .biweekly:
            return EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 2,
                daysOfTheWeek: nil, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil)
        case .monthly:
            return EKRecurrenceRule(
                recurrenceWith: .monthly, interval: 1,
                daysOfTheWeek: nil, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil)
        case .yearly:
            return EKRecurrenceRule(
                recurrenceWith: .yearly, interval: 1,
                daysOfTheWeek: nil, daysOfTheMonth: nil,
                monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }
}

/// Human-readable label for an EKRecurrenceRule
private func recurrenceLabel(for rule: EKRecurrenceRule) -> String {
    let freq: String
    switch rule.frequency {
    case .daily: freq = "daily"
    case .weekly:
        if let days = rule.daysOfTheWeek, days.count == 5,
           Set(days.map { $0.dayOfTheWeek }) == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) {
            freq = "weekdays"
        } else if rule.interval == 2 {
            freq = "biweekly"
        } else {
            freq = "weekly"
        }
    case .monthly: freq = "monthly"
    case .yearly: freq = "yearly"
    @unknown default: freq = "custom"
    }
    if rule.interval > 1 && freq != "biweekly" {
        return "every \(rule.interval) \(freq)"
    }
    return freq
}

private func format(_ reminder: EKReminder, at index: Int?, listName: String? = nil, isFlagged: Bool = false, tags: [String] = [], section: String? = nil) -> String {
    let dateString = formattedDueDate(from: reminder).map { " (\($0))" } ?? ""
    let priorityString = Priority(reminder.mappedPriority).map { " (priority: \($0))" } ?? ""
    let listString = listName.map { "\($0): " } ?? ""
    let notesString = reminder.notes.map { " (\($0))" } ?? ""
    let indexString = index.map { "\($0): " } ?? ""
    let flaggedString = isFlagged ? " (flagged)" : ""
    let tagsString = tags.isEmpty ? "" : " (tags: " + tags.map { "#\($0)" }.joined(separator: ", ") + ")"
    let sectionString = section.map { " (section: \($0))" } ?? ""

    var extras = ""
    if let rule = reminder.recurrenceRules?.first {
        extras += " (repeats: \(recurrenceLabel(for: rule)))"
    }
    if let alarm = reminder.firstTimeAlarm, let date = alarm.absoluteDate {
        let formatted = dateFormatter.localizedString(for: date, relativeTo: Date())
        extras += " (reminder: \(formatted))"
    }

    return "\(listString)\(indexString)\(reminder.title ?? "<unknown>")\(notesString)\(dateString)\(priorityString)\(flaggedString)\(tagsString)\(sectionString)\(extras)"
}

public enum OutputFormat: String, ExpressibleByArgument {
    case json, plain
}

public enum DisplayOptions: String, Decodable {
    case all
    case incomplete
    case complete
}

public enum Priority: String, ExpressibleByArgument {
    case none
    case low
    case medium
    case high

    var value: EKReminderPriority {
        switch self {
            case .none: return .none
            case .low: return .low
            case .medium: return .medium
            case .high: return .high
        }
    }

    init?(_ priority: EKReminderPriority) {
        switch priority {
            case .none: return nil
            case .low: self = .low
            case .medium: self = .medium
            case .high: self = .high
        @unknown default:
            return nil
        }
    }
}

public final class Reminders {
    public static func requestAccess() -> (Bool, Error?) {
        let semaphore = DispatchSemaphore(value: 0)
        var grantedAccess = false
        var returnError: Error? = nil
        if #available(macOS 14.0, *) {
            Store.requestFullAccessToReminders { granted, error in
                grantedAccess = granted
                returnError = error
                semaphore.signal()
            }
        } else {
            Store.requestAccess(to: .reminder) { granted, error in
                grantedAccess = granted
                returnError = error
                semaphore.signal()
            }
        }

        semaphore.wait()
        return (grantedAccess, returnError)
    }

    func getListNames() -> [String] {
        return self.getCalendars().map { $0.title }
    }

    func showLists(outputFormat: OutputFormat, showColor: Bool) {
        let calendars = self.getCalendars()
        switch (outputFormat) {
        case .json:
            print(encodeToJson(data: calendars.map { $0.title }))
        default:
            for cal in calendars {
                if showColor {
                    let hex = hexColor(from: cal.cgColor)
                    print("\(cal.title) (\(hex))")
                } else {
                    print(cal.title)
                }
            }
        }
    }

    func showAllReminders(dueOn dueDate: DateComponents?, includeOverdue: Bool, hasDueDate: Bool,
        onlyFlagged: Bool = false, withTag: String? = nil, inSection: String? = nil,
        displayOptions: DisplayOptions, outputFormat: OutputFormat
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        let calendar = Calendar.current
        let flaggedKeys = RemindersDB.getFlaggedKeys()
        let tagMap = RemindersDB.getTagMap()
        let sectionMap = RemindersDB.getSectionMap()

        self.reminders(on: self.getCalendars(), displayOptions: displayOptions) { reminders in
            var matchingReminders: [(reminder: EKReminder, index: Int, listName: String, isFlagged: Bool, tags: [String], section: String?)] = []
            for (i, reminder) in reminders.enumerated() {
                let listName = reminder.calendar.title
                let key = RemindersDB.lookupKey(listName: listName, title: reminder.title ?? "")
                let isFlagged = flaggedKeys.contains(key)
                let tags = tagMap[key] ?? []
                let section = sectionMap[key]

                if onlyFlagged && !isFlagged { continue }
                if let tag = withTag, !tags.contains(tag) { continue }
                if let sec = inSection, section != sec { continue }

                if hasDueDate && reminder.dueDateComponents == nil {
                    continue
                }

                guard let dueDate = dueDate?.date else {
                    matchingReminders.append((reminder, i, listName, isFlagged, tags, section))
                    continue
                }

                guard let reminderDueDate = reminder.dueDateComponents?.date else {
                    continue
                }

                let sameDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedSame
                let earlierDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedAscending

                if sameDay || (includeOverdue && earlierDay) {
                    matchingReminders.append((reminder, i, listName, isFlagged, tags, section))
                }
            }

            switch outputFormat {
            case .json:
                let enriched = matchingReminders.map { EncodableReminder(reminder: $0.reminder, flagged: $0.isFlagged, tags: $0.tags, section: $0.section) }
                print(encodeToJson(data: enriched))
            case .plain:
                for match in matchingReminders {
                    print(format(match.reminder, at: match.index, listName: match.listName, isFlagged: match.isFlagged, tags: match.tags, section: match.section))
                }
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func showListItems(withName name: String, dueOn dueDate: DateComponents?, includeOverdue: Bool, hasDueDate: Bool,
        onlyFlagged: Bool = false, withTag: String? = nil, inSection: String? = nil,
        displayOptions: DisplayOptions, outputFormat: OutputFormat, sort: Sort, sortOrder: CustomSortOrder)
    {
        let semaphore = DispatchSemaphore(value: 0)
        let calendar = Calendar.current
        let flaggedKeys = RemindersDB.getFlaggedKeys()
        let tagMap = RemindersDB.getTagMap()
        let sectionMap = RemindersDB.getSectionMap()

        self.reminders(on: [self.calendar(withName: name)], displayOptions: displayOptions) { reminders in
            var matchingReminders: [(reminder: EKReminder, index: Int?, isFlagged: Bool, tags: [String], section: String?)] = []
            let reminders = sort == .none ? reminders : reminders.sorted(by: sort.sortFunction(order: sortOrder))
            for (i, reminder) in reminders.enumerated() {
                let index = sort == .none ? i : nil
                let key = RemindersDB.lookupKey(listName: name, title: reminder.title ?? "")
                let isFlagged = flaggedKeys.contains(key)
                let tags = tagMap[key] ?? []
                let section = sectionMap[key]

                if onlyFlagged && !isFlagged { continue }
                if let tag = withTag, !tags.contains(tag) { continue }
                if let sec = inSection, section != sec { continue }

                if hasDueDate && reminder.dueDateComponents == nil {
                    continue
                }

                guard let dueDate = dueDate?.date else {
                    matchingReminders.append((reminder, index, isFlagged, tags, section))
                    continue
                }

                guard let reminderDueDate = reminder.dueDateComponents?.date else {
                    continue
                }

                let sameDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedSame
                let earlierDay = calendar.compare(
                    reminderDueDate, to: dueDate, toGranularity: .day) == .orderedAscending

                if sameDay || (includeOverdue && earlierDay) {
                    matchingReminders.append((reminder, index, isFlagged, tags, section))
                }
            }

            switch outputFormat {
            case .json:
                let enriched = matchingReminders.map { EncodableReminder(reminder: $0.reminder, flagged: $0.isFlagged, tags: $0.tags, section: $0.section) }
                print(encodeToJson(data: enriched))
            case .plain:
                for match in matchingReminders {
                    print(format(match.reminder, at: match.index, isFlagged: match.isFlagged, tags: match.tags, section: match.section))
                }
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func newList(with name: String, source requestedSourceName: String?) {
        let store = EKEventStore()
        let sources = store.sources
        guard var source = sources.first else {
            print("No existing list sources were found, please create a list in Reminders.app")
            exit(1)
        }

        if let requestedSourceName = requestedSourceName {
            guard let requestedSource = sources.first(where: { $0.title == requestedSourceName }) else
            {
                print("No source named '\(requestedSourceName)'")
                exit(1)
            }

            source = requestedSource
        } else {
            let uniqueSources = Set(sources.map { $0.title })
            if uniqueSources.count > 1 {
                print("Multiple sources were found, please specify one with --source:")
                for source in uniqueSources {
                    print("  \(source)")
                }

                exit(1)
            }
        }

        let newList = EKCalendar(for: .reminder, eventStore: store)
        newList.title = name
        newList.source = source

        do {
            try store.saveCalendar(newList, commit: true)
            print("Created new list '\(newList.title)'!")
        } catch let error {
            print("Failed create new list with error: \(error)")
            exit(1)
        }
    }

    func edit(itemAtIndex index: String, onListNamed name: String, newText: String?, newNotes: String?,
              url: String? = nil, clearUrl: Bool = false,
              dueDateComponents: DateComponents? = nil, clearDueDate: Bool,
              priority: Priority?, clearPriority: Bool,
              remindMeDate: DateComponents? = nil, clearRemindMeDate: Bool = false,
              recurrence: Recurrence? = nil, clearRecurrence: Bool = false,
              flagged: Bool = false, unflag: Bool = false)
    {
        let calendar = self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)

        self.reminders(on: [calendar], displayOptions: .incomplete) { reminders in
            guard let reminder = self.getReminder(from: reminders, at: index) else {
                print("No reminder at index \(index) on \(name)")
                exit(1)
            }

            do {
                reminder.title = newText ?? reminder.title

                // URL is stored in notes (EventKit .url doesn't sync with Reminders UI)
                let existing = NoteUrl.extract(from: reminder.notes)
                let baseContent = newNotes ?? existing.content
                let finalUrl = clearUrl ? nil : (url ?? existing.url)
                reminder.notes = NoteUrl.combine(content: baseContent, url: finalUrl)

                if clearPriority {
                    reminder.priority = 0
                }
                else if priority != nil {
                    reminder.priority = Int(priority?.value.rawValue ?? UInt(reminder.priority))
                }

                if clearDueDate || (dueDateComponents != nil) {
                    reminder.dueDateComponents = nil
                    // Remove time-based alarms, keep location alarms
                    for alarm in reminder.alarms ?? [] {
                        if alarm.structuredLocation == nil {
                            reminder.removeAlarm(alarm)
                        }
                    }
                }
                if dueDateComponents != nil {
                    reminder.dueDateComponents = dueDateComponents
                    // Only add due-date auto-alarm if no explicit remind-me-date is set
                    if remindMeDate == nil && !clearRemindMeDate {
                        if let dueDate = dueDateComponents?.date, dueDateComponents?.hour != nil {
                            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
                        }
                    }
                }

                // Remind-me-date (time-based alarm)
                if clearRemindMeDate {
                    for alarm in reminder.alarms ?? [] {
                        if alarm.structuredLocation == nil {
                            reminder.removeAlarm(alarm)
                        }
                    }
                } else if let remindDate = remindMeDate?.date {
                    // Remove existing time-based alarms first
                    for alarm in reminder.alarms ?? [] {
                        if alarm.structuredLocation == nil {
                            reminder.removeAlarm(alarm)
                        }
                    }
                    reminder.addAlarm(EKAlarm(absoluteDate: remindDate))
                }

                // Recurrence
                if clearRecurrence {
                    if let rules = reminder.recurrenceRules {
                        for rule in rules {
                            reminder.removeRecurrenceRule(rule)
                        }
                    }
                } else if let recurrence = recurrence {
                    // Replace existing rules
                    if let rules = reminder.recurrenceRules {
                        for rule in rules {
                            reminder.removeRecurrenceRule(rule)
                        }
                    }
                    reminder.addRecurrenceRule(recurrence.toRule())
                }

                try Store.save(reminder, commit: true)

                // Set/clear flagged via AppleScript (not available in EventKit)
                if flagged || unflag {
                    if let externalId = reminder.calendarItemExternalIdentifier {
                        AppleScriptBridge.setFlagged(flagged, reminderId: externalId)
                    }
                }

                print("Updated reminder '\(reminder.title!)'")
            } catch let error {
                print("Failed to update reminder with error: \(error)")
                exit(1)
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func setComplete(_ complete: Bool, itemAtIndex index: String, onListNamed name: String) {
        let calendar = self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)
        let displayOptions = complete ? DisplayOptions.incomplete : .complete
        let action = complete ? "Completed" : "Uncompleted"

        self.reminders(on: [calendar], displayOptions: displayOptions) { reminders in
            print(reminders.map { $0.title! })
            guard let reminder = self.getReminder(from: reminders, at: index) else {
                print("No reminder at index \(index) on \(name)")
                exit(1)
            }

            do {
                reminder.isCompleted = complete
                try Store.save(reminder, commit: true)
                print("\(action) '\(reminder.title!)'")
            } catch let error {
                print("Failed to save reminder with error: \(error)")
                exit(1)
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func delete(itemAtIndex index: String, onListNamed name: String) {
        let calendar = self.calendar(withName: name)
        let semaphore = DispatchSemaphore(value: 0)

        self.reminders(on: [calendar], displayOptions: .incomplete) { reminders in
            guard let reminder = self.getReminder(from: reminders, at: index) else {
                print("No reminder at index \(index) on \(name)")
                exit(1)
            }

            do {
                try Store.remove(reminder, commit: true)
                print("Deleted '\(reminder.title!)'")
            } catch let error {
                print("Failed to delete reminder with error: \(error)")
                exit(1)
            }

            semaphore.signal()
        }

        semaphore.wait()
    }

    func addReminder(
        string: String,
        notes: String?,
        url: String? = nil,
        toListNamed name: String,
        dueDateComponents: DateComponents?,
        priority: Priority,
        remindMeDate: DateComponents? = nil,
        recurrence: Recurrence? = nil,
        flagged: Bool = false,
        outputFormat: OutputFormat)
    {
        let calendar = self.calendar(withName: name)
        let reminder = EKReminder(eventStore: Store)
        reminder.calendar = calendar
        reminder.title = string
        reminder.notes = NoteUrl.combine(content: notes, url: url)
        reminder.dueDateComponents = dueDateComponents
        reminder.priority = Int(priority.value.rawValue)

        // Alarm: prefer explicit remind-me-date, fallback to due-date auto-alarm
        if let remindDate = remindMeDate?.date {
            reminder.addAlarm(EKAlarm(absoluteDate: remindDate))
        } else if let dueDate = dueDateComponents?.date, dueDateComponents?.hour != nil {
            reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        }

        // Recurrence
        if let recurrence = recurrence {
            reminder.addRecurrenceRule(recurrence.toRule())
        }

        do {
            try Store.save(reminder, commit: true)

            // Set flagged via AppleScript after EventKit save (not available in EventKit)
            if flagged, let externalId = reminder.calendarItemExternalIdentifier {
                AppleScriptBridge.setFlagged(true, reminderId: externalId)
            }

            switch (outputFormat) {
            case .json:
                print(encodeToJson(data: EncodableReminder(reminder: reminder, flagged: flagged)))
            default:
                print("Added '\(reminder.title!)' to '\(calendar.title)'")
            }
        } catch let error {
            print("Failed to save reminder with error: \(error)")
            exit(1)
        }
    }

    // MARK: - Private functions

    private func reminders(
        on calendars: [EKCalendar],
        displayOptions: DisplayOptions,
        completion: @escaping (_ reminders: [EKReminder]) -> Void)
    {
        let predicate = Store.predicateForReminders(in: calendars)
        Store.fetchReminders(matching: predicate) { reminders in
            let reminders = reminders?
                .filter { self.shouldDisplay(reminder: $0, displayOptions: displayOptions) }
            completion(reminders ?? [])
        }
    }

    private func shouldDisplay(reminder: EKReminder, displayOptions: DisplayOptions) -> Bool {
        switch displayOptions {
        case .all:
            return true
        case .incomplete:
            return !reminder.isCompleted
        case .complete:
            return reminder.isCompleted
        }
    }

    private func calendar(withName name: String) -> EKCalendar {
        if let calendar = self.getCalendars().find(where: { $0.title.lowercased() == name.lowercased() }) {
            return calendar
        } else {
            print("No reminders list matching \(name)")
            exit(1)
        }
    }

    private func getCalendars() -> [EKCalendar] {
        return Store.calendars(for: .reminder)
                    .filter { $0.allowsContentModifications }
    }

    private func getReminder(from reminders: [EKReminder], at index: String) -> EKReminder? {
        precondition(!index.isEmpty, "Index cannot be empty, argument parser must be misconfigured")
        if let index = Int(index) {
            return reminders[safe: index]
        } else {
            return reminders.first { $0.calendarItemExternalIdentifier == index }
        }
    }

}

/// Wraps EKReminder with extra fields not available in EventKit (e.g. flagged, tags, section).
struct EncodableReminder: Encodable {
    let reminder: EKReminder
    let flagged: Bool
    let tags: [String]
    let section: String?

    init(reminder: EKReminder, flagged: Bool, tags: [String] = [], section: String? = nil) {
        self.reminder = reminder
        self.flagged = flagged
        self.tags = tags
        self.section = section
    }

    private enum ExtraKeys: String, CodingKey {
        case flagged, tags, section
    }

    func encode(to encoder: Encoder) throws {
        try reminder.encode(to: encoder)
        var container = encoder.container(keyedBy: ExtraKeys.self)
        try container.encode(flagged, forKey: .flagged)
        if !tags.isEmpty {
            try container.encode(tags, forKey: .tags)
        }
        if let section = section {
            try container.encode(section, forKey: .section)
        }
    }
}

/// Bridge to Reminders.app via AppleScript for features not in EventKit.
enum AppleScriptBridge {
    /// Set or clear the flagged status of a reminder.
    /// `reminderId` is EventKit's `calendarItemExternalIdentifier` (matches AppleScript `id` UUID).
    static func setFlagged(_ value: Bool, reminderId: String) {
        let appleScriptId = "x-apple-reminder://\(reminderId)"
        let valueStr = value ? "true" : "false"
        let script = """
            tell application "Reminders"
                set flagged of (reminder id "\(appleScriptId)") to \(valueStr)
            end tell
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                fputs("Warning: Failed to set flagged via AppleScript\n", stderr)
            }
        } catch {
            fputs("Warning: Failed to run AppleScript: \(error)\n", stderr)
        }
    }
}

private func encodeToJson(data: Encodable) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let encoded = try! encoder.encode(data)
    return String(data: encoded, encoding: .utf8) ?? ""
}

private func hexColor(from cgColor: CGColor) -> String {
    guard let components = cgColor.components, components.count >= 3 else {
        return "#000000"
    }
    let r = Int(components[0] * 255)
    let g = Int(components[1] * 255)
    let b = Int(components[2] * 255)
    return String(format: "#%02X%02X%02X", r, g, b)
}
