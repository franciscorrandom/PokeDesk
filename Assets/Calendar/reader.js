/* Arcanine's adapter around unmodified ICAL.js 2.2.1. No network or filesystem access. */
function readCalendar(text, rangeStart, rangeEnd, localTimezone) {
  ICAL.TimezoneService.reset();
  var calendar = new ICAL.Component(ICAL.parse(text));
  if (calendar.name !== 'vcalendar') throw new Error('INVALID_CALENDAR');
  calendar.getAllSubcomponents('vtimezone').forEach(function (component) {
    var id = component.getFirstPropertyValue('tzid');
    if (id) ICAL.TimezoneService.register(id, new ICAL.Timezone({ component: component, tzid: id }));
  });
  var defaultZone = calendar.getFirstPropertyValue('x-wr-timezone') || localTimezone;
  var title = calendar.getFirstPropertyValue('x-wr-calname') || 'Google Calendar';
  var items = calendar.getAllSubcomponents('vevent');
  if (items.length > 30000) throw new Error('CALENDAR_LIMIT');
  var output = Object.create(null), total = 0, budget = 500000;
  function stamp(time, component, property) {
    if (!time) throw new Error('INVALID_DATE');
    if (!time.isDate && time.zone && time.zone.tzid !== 'floating') return time.toUnixTime();
    var prop = component.getFirstProperty(property || 'dtstart');
    var zone = prop && prop.getParameter('tzid') || defaultZone;
    var seconds = nativeTimestamp(JSON.stringify({ year: time.year, month: time.month, day: time.day,
      hour: time.hour || 0, minute: time.minute || 0, second: time.second || 0 }), zone);
    if (!isFinite(seconds)) throw new Error('UNKNOWN_TIMEZONE');
    return seconds;
  }
  function put(event, start, end, recurrence) {
    if (event.component.getFirstPropertyValue('status') === 'CANCELLED') return;
    var begin = stamp(start, event.component, 'dtstart');
    var finish = stamp(end, event.component, 'dtend');
    if (finish <= rangeStart || begin >= rangeEnd) return;
    if (!isFinite(begin) || !isFinite(finish) || finish < begin) throw new Error('INVALID_DATE');
    var uid = event.uid || 'event-' + begin;
    var key = uid + '#' + (recurrence ? recurrence.toString() : start.toString());
    var link = ['url', 'location', 'description', 'x-google-conference', 'conference'].map(function (name) {
      return String(event.component.getFirstPropertyValue(name) || '');
    }).join('\n');
    if (!output[key]) total++;
    output[key] = { id: key, title: event.summary || 'Reunión', start: begin, end: finish,
      calendarName: String(title), links: link, allDay: !!start.isDate };
    if (total > 10000) throw new Error('CALENDAR_LIMIT');
  }
  var cancelled = Object.create(null), exceptions = Object.create(null), cancelledOccurrences = Object.create(null);
  items.forEach(function (c) {
    var uid = c.getFirstPropertyValue('uid'), recurrence = c.getFirstPropertyValue('recurrence-id');
    if (recurrence) {
      if (c.getFirstPropertyValue('status') === 'CANCELLED') cancelledOccurrences[uid + '#' + recurrence.toString()] = true;
      else (exceptions[uid] || (exceptions[uid] = [])).push(c);
    } else if (c.getFirstPropertyValue('status') === 'CANCELLED') cancelled[uid] = true;
  });
  items.forEach(function (component) {
    if (!component.hasProperty('dtstart') || component.hasProperty('recurrence-id') || cancelled[component.getFirstPropertyValue('uid')]) return;
    var event = new ICAL.Event(component, { exceptions: exceptions[component.getFirstPropertyValue('uid')] || [], strictExceptions: true });
    if (!event.isRecurring()) { put(event, event.startDate, event.endDate, null); return; }
    var iterator = event.iterator(), occurrence, count = 0;
    while ((occurrence = iterator.next())) {
      if (++count > 100000 || --budget <= 0) throw new Error('RECURRENCE_LIMIT');
      var occurrenceStart = stamp(occurrence, component, 'dtstart');
      if (occurrenceStart >= rangeEnd + 86400 * 7) break;
      if (cancelledOccurrences[event.uid + '#' + occurrence.toString()]) continue;
      var details = event.getOccurrenceDetails(occurrence);
      put(details.item, details.startDate, details.endDate, details.recurrenceId);
    }
  });
  // Include an exception moved into the window even when its original occurrence lies outside it.
  items.forEach(function (component) {
    if (!component.hasProperty('dtstart') || !component.hasProperty('recurrence-id') || cancelled[component.getFirstPropertyValue('uid')]) return;
    var event = new ICAL.Event(component);
    put(event, event.startDate, event.endDate, event.recurrenceId);
  });
  return JSON.stringify({ name: String(title), events: Object.keys(output).map(function (key) { return output[key]; }).sort(function (a, b) { return a.start - b.start; }) });
}
