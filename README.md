# reminders-cli

A simple CLI for interacting with OS X reminders.

## Usage:

#### Show all lists

```
$ reminders show-lists
Soon
Eventually
```

#### Show reminders on a specific list

```
$ reminders show Soon
0 Write README
1 Ship reminders-cli
```

#### Complete an item on a list

```
$ reminders complete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli
```

#### Undo a completed item

```
$ reminders show Soon --only-completed
0 Write README
$ reminders uncomplete Soon 0
Uncompleted 'Write README'
$ reminders show Soon
0 Write README
```

#### Edit an item on a list

```
$ reminders edit Soon 0 Some edited text
Updated reminder 'Some edited text'
$ reminders show Soon
0 Ship reminders-cli
1 Some edited text
```

#### Delete an item on a list

```
$ reminders delete Soon 0
Completed 'Write README'
$ reminders show Soon
0 Ship reminders-cli
```

#### Add a reminder to a list

```
$ reminders add Soon Contribute to open source
$ reminders add Soon Go to the grocery store --due-date "tomorrow 9am"
$ reminders add Soon Something really important --priority high
$ reminders add Soon Daily standup --due-date "tomorrow 9am" --recurrence daily
$ reminders add Soon Call dentist --due-date "friday" --remind-me-date "friday 8:30"
$ reminders show Soon
0: Ship reminders-cli
1: Contribute to open source
2: Go to the grocery store (in 10 hours)
3: Something really important (priority: high)
4: Daily standup (in 10 hours) (repeats: daily)
5: Call dentist (in 3 days) (reminder: in 3 days)
```

#### Show reminders due on or by a date

```
$ reminders show-all --due-date today
1: Contribute to open source (in 3 hours)
$ reminders show-all --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
$ reminders show-all --has-due-date
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
2: Go to the grocery store (in 10 hours)
$ reminders show Soon --due-date today --include-overdue
0: Ship reminders-cli (2 days ago)
1: Contribute to open source (in 3 hours)
```

#### Edit recurrence and remind-me-date

```
$ reminders edit Soon 4 --recurrence weekly
Updated reminder 'Daily standup'
$ reminders edit Soon 4 --clear-recurrence
Updated reminder 'Daily standup'
$ reminders edit Soon 5 --remind-me-date "friday 9:00"
Updated reminder 'Call dentist'
$ reminders edit Soon 5 --clear-remind-me-date
Updated reminder 'Call dentist'
```

#### Show list colors

```
$ reminders show-lists --color
Soon (#1BADF8)
Eventually (#FF9500)
```

#### Flagged reminders

```
$ reminders add Soon Buy groceries --flagged
$ reminders show Soon --flagged
0: Buy groceries (flagged)
$ reminders edit Soon 0 --unflag
Updated reminder 'Buy groceries'
$ reminders edit Soon 0 --flagged
Updated reminder 'Buy groceries'
$ reminders show-all --flagged
Soon: 0: Buy groceries (flagged)
```

Note: Flagged status is read from the Reminders.app SQLite database and
written via AppleScript, since EventKit does not expose a flagged API.

#### Sort reminders

```
$ reminders show Soon --sort due-date
$ reminders show Soon --sort creation-date --sort-order descending
$ reminders show Soon --sort completion-date --include-completed
$ reminders show Soon --sort modification-date
```

#### See help for more examples

```
$ reminders --help
$ reminders show -h
```

## Installation:

#### With [Homebrew](http://brew.sh/)

```
$ brew install keith/formulae/reminders-cli
```

#### From GitHub releases

Download the latest release from
[here](https://github.com/keith/reminders-cli/releases)

```
$ tar -zxvf reminders.tar.gz
$ mv reminders /usr/local/bin
$ rm reminders.tar.gz
```

#### Building manually

This requires a recent Xcode installation.

```
$ cd reminders-cli
$ make build-release
$ cp .build/apple/Products/Release/reminders /usr/local/bin/reminders
```
