import EventKit

private let dayOfWeekMap: [EKWeekday: String] = [
    .monday: "MO", .tuesday: "TU", .wednesday: "WE",
    .thursday: "TH", .friday: "FR", .saturday: "SA", .sunday: "SU",
]

private let frequencyMap: [EKRecurrenceFrequency: String] = [
    .daily: "daily", .weekly: "weekly", .monthly: "monthly", .yearly: "yearly",
]

extension EKReminder: @retroactive Encodable {
    private enum EncodingKeys: String, CodingKey {
        case externalId
        case lastModified
        case creationDate
        case title
        case notes
        case url
        case location
        case locationTitle
        case completionDate
        case isCompleted
        case priority
        case startDate
        case dueDate
        case allDay
        case list
        case reminderUrl
        case remindMeDate
        case recurrence
    }

    private struct RecurrenceInfo: Encodable {
        let frequency: String
        let interval: Int
        let daysOfTheWeek: [String]?
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: EncodingKeys.self)
        try container.encode(self.calendarItemExternalIdentifier, forKey: .externalId)
        try container.encode(self.title, forKey: .title)
        try container.encode(self.isCompleted, forKey: .isCompleted)
        try container.encode(self.priority, forKey: .priority)
        try container.encode(self.calendar.title, forKey: .list)
        // URL is stored in notes (EventKit .url doesn't sync with Reminders UI)
        let parsed = NoteUrl.extract(from: self.notes)
        try container.encodeIfPresent(parsed.content, forKey: .notes)
        try container.encodeIfPresent(parsed.url, forKey: .url)
        try container.encodeIfPresent(format(self.completionDate), forKey: .completionDate)

        for alarm in self.alarms ?? [] {
            if let location = alarm.structuredLocation {
                try container.encodeIfPresent(location.title, forKey: .locationTitle)
                if let geoLocation = location.geoLocation {
                    let geo = "\(geoLocation.coordinate.latitude), \(geoLocation.coordinate.longitude)"
                    try container.encode(geo, forKey: .location)
                }
                break
            }
        }

        if let startDateComponents = self.startDateComponents {
            try container.encodeIfPresent(format(startDateComponents.date), forKey: .startDate)
        }

        if let dueDateComponents = self.dueDateComponents {
            try container.encodeIfPresent(format(dueDateComponents.date), forKey: .dueDate)
            try container.encode(dueDateComponents.hour == nil, forKey: .allDay)
        }

        if let lastModifiedDate = self.lastModifiedDate {
            try container.encode(format(lastModifiedDate), forKey: .lastModified)
        }

        if let creationDate = self.creationDate {
            try container.encode(format(creationDate), forKey: .creationDate)
        }

        // x-apple-reminderkit:// URL (experimental: calendarItemExternalIdentifier may not be stable)
        if let externalId = self.calendarItemExternalIdentifier {
            try container.encode("x-apple-reminderkit://REMCDReminder/\(externalId)", forKey: .reminderUrl)
        }

        // First time-based alarm as remind-me-date
        if let alarm = self.alarms?.first(where: { $0.structuredLocation == nil }),
           let date = alarm.absoluteDate {
            try container.encode(format(date), forKey: .remindMeDate)
        }

        // Recurrence rule
        if let rule = self.recurrenceRules?.first {
            let freq = frequencyMap[rule.frequency] ?? "unknown"
            let days = rule.daysOfTheWeek?.compactMap { dayOfWeekMap[$0.dayOfTheWeek] }
            let info = RecurrenceInfo(
                frequency: freq,
                interval: rule.interval,
                daysOfTheWeek: days?.isEmpty == true ? nil : days)
            try container.encode(info, forKey: .recurrence)
        }
    }

    private func format(_ date: Date?) -> String? {
        if #available(macOS 12.0, *) {
            return date?.ISO8601Format()
        } else {
            return date?.description(with: .current)
        }
    }
}
