import 'package:flutter_test/flutter_test.dart';
import 'package:prinotes/core/router/app_router.dart';

void main() {
  String? r(String loc, {bool setup = true, bool locked = false, bool authed = true, String? pending}) =>
      appRedirect(isSetup: setup, isLocked: locked, isAuthenticated: authed, loc: loc, pending: pending);

  test('not set up: always the setup screen', () {
    expect(r('/', setup: false), '/setup');
    expect(r('/setup', setup: false), isNull);
  });

  test('locked: everything goes to the lock screen', () {
    expect(r('/todo', locked: true, authed: false), '/lock');
    expect(r('/lock', locked: true, authed: false), isNull);
  });

  test('after unlocking, the lock screen goes to the remembered page, else the notes list', () {
    expect(r('/lock', pending: '/todo'), '/todo', reason: 'widget or notification opened the app while it was locked');
    expect(r('/lock'), '/');
    expect(r('/setup'), '/');
  });

  test('unlocked with a remembered page: any location goes there (the new router after unlock starts at the notes list)', () {
    expect(r('/', pending: '/todo'), '/todo');
    expect(r('/todo', pending: '/todo'), isNull, reason: 'already there');
  });

  test('normal navigation is left alone', () {
    expect(r('/todo'), isNull);
    expect(r('/'), isNull);
  });

  test('remembers the page that was asked for while locked', () {
    expect(pendingForLock(target: '/lock', loc: '/todo'), '/todo');
    expect(pendingForLock(target: '/lock', loc: '/lock'), isNull);
    expect(pendingForLock(target: '/lock', loc: '/setup'), isNull);
    expect(pendingForLock(target: null, loc: '/todo'), isNull);
    expect(pendingForLock(target: '/lock', loc: '/'), isNull, reason: 'the notes list is the default, not a request');
  });
}
