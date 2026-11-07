# omarchy-gcal-clock

An Omarchy bar clock with a calendar popup that shows your Google Calendar agenda for the selected day.

## Install

```bash
omarchy plugin add https://github.com/nanosch/omarchy-gcal-clock.git --enable
omarchy plugin disable omarchy.clock   # optional: hide the stock clock
```

## Google Calendar agenda

The agenda is loaded with the [`gws`](https://github.com/googleworkspace/cli) Google Workspace CLI from your `primary` calendar. Install it and log in once:

```bash
gws auth login -s calendar
```

Without `gws`, the clock and month grid still work; only the agenda shows an error. If the login expires, the popup offers a reconnect (`gws-reconnect.sh`).

## Update

```bash
omarchy plugin update nanosch.clock
```
