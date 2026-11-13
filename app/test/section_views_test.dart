import 'package:flutter_test/flutter_test.dart';
import 'package:revoked_app/core/models/record.dart' as models;
import 'package:revoked_app/features/vault/views/builtin_views.dart';
import 'package:revoked_app/features/vault/views/view_data.dart';
import 'package:revoked_app/features/vault/views/view_spec.dart';

models.Record _r(String key, String value, {String format = 'default'}) =>
    models.Record(
      id: 'id-$key',
      key: key,
      value: value,
      label: key,
      type: 'text',
      format: format,
      user: 'u',
      workspace: 'w',
    );

ViewSpec _view(String id) => builtinViews.firstWhere((v) => v.id == id);

ScheduleBlock _schedule() =>
    _view('medication').blocks.whereType<ScheduleBlock>().single;

void main() {
  test('every built-in view parses', () {
    expect(builtinViews.map((v) => v.id), [
      'medication',
      'vehicle',
      'emergency',
      'wifi',
    ]);
  });

  test('a view newer than this app or without blocks is not drawn', () {
    expect(
      ViewSpec.parse({
        'version': viewFormatVersion + 1,
        'id': 'x',
        'match': ['a'],
        'blocks': [
          {'type': 'divider'},
        ],
      }),
      isNull,
    );
    expect(
      ViewSpec.parse({
        'version': 1,
        'id': 'x',
        'match': ['a'],
        'blocks': [
          {'type': 'unknown'},
        ],
      }),
      isNull,
    );
  });

  test('a view matches on the section\'s own keys, not the vault\'s', () {
    final vault = [_r('network_name', 'Home'), _r('wifi_password', 'pw')];
    final elsewhere = ViewData(section: [_r('note', 'x')], vault: vault);
    expect(elsewhere.matches(_view('wifi')), isFalse);
    final own = ViewData(section: vault);
    expect(own.matches(_view('wifi')), isTrue);
  });

  test('hidden values stay dots until revealed; filters escape', () {
    final data = ViewData(
      section: [
        _r('network_name', 'My;Net'),
        _r('wifi_password', 'a:b', format: 'hidden'),
      ],
    );
    expect(data.fill('{wifi_password}'), '••••••');
    expect(
      data.fill(
        'S:{network_name|wifi};P:{wifi_password|wifi}',
        revealed: {'wifi_password'},
      ),
      r'S:My\;Net;P:a\:b',
    );
    expect(data.complete('{network_name} {missing}'), isFalse);
  });

  test('a record group gathers members by number and skips empty ones', () {
    final data = ViewData(
      section: [
        _r('medication-2-name', 'Metformin'),
        _r('medication-1-name', 'Ramipril'),
        _r('medication-1-dose', '5 mg'),
        _r('medication-3-name', ''),
      ],
    );
    final group = data.group('medication');
    expect(group.map((m) => m['name']), ['Ramipril', 'Metformin']);
    expect(group.first['dose'], '5 mg');
    expect(data.matches(_view('medication')), isTrue);
  });

  test('schedule amounts read the ways people write them', () {
    expect(scheduleAmount('1'), 1);
    expect(scheduleAmount('½'), 0.5);
    expect(scheduleAmount('1/2'), 0.5);
    expect(scheduleAmount('1,5'), 1.5);
    expect(scheduleAmount('–'), 0);
    expect(scheduleAmount(''), 0);
  });

  test('the next dose is the earliest running one from now on', () {
    final b = _schedule();
    final members = [
      const ViewGroupMember(1, {'name': 'Ramipril', 'morning': '1'}),
      const ViewGroupMember(2, {
        'name': 'Metformin',
        'morning': '1',
        'evening': '1',
      }),
      const ViewGroupMember(3, {
        'name': 'Zopiclon',
        'night': '½',
        'until': '2026-01-01',
      }),
    ];
    final afternoon = DateTime(2026, 3, 10, 14);
    final next = nextDose(members, b, afternoon)!;
    expect(next.at, DateTime(2026, 3, 10, 18));
    expect(next.members.map((m) => m['name']), ['Metformin']);

    // After the evening dose, and with Zopiclon ended, it is tomorrow's.
    final late = DateTime(2026, 3, 10, 19);
    final tomorrow = nextDose(members, b, late)!;
    expect(tomorrow.at, DateTime(2026, 3, 11, 8));
    expect(tomorrow.members.length, 2);
  });

  test('stock lasts whole days at the daily amount', () {
    final b = _schedule();
    expect(
      daysOfStock(
        const ViewGroupMember(1, {
          'morning': '1',
          'evening': '1',
          'stock': '13',
        }),
        b,
      ),
      6,
    );
    expect(daysOfStock(const ViewGroupMember(1, {'morning': '1'}), b), isNull);
  });
}
