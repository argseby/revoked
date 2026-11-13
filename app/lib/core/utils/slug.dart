import 'dart:math';

/// The characters a generated slug is drawn from; the server's slug pattern
/// accepts them all.
const String slugAlphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// A generated slug's length: 24 of 36 symbols is about 124 bits.
const int slugLength = 24;

final Random _random = Random.secure();

/// A share or request slug. The slug alone opens `/s/{slug}` and
/// `/api/public/*`, so it comes from the CSPRNG and is long enough that
/// guessing one is hopeless.
String randomSlug([int length = slugLength]) => String.fromCharCodes(
  Iterable.generate(
    length,
    (_) => slugAlphabet.codeUnitAt(_random.nextInt(slugAlphabet.length)),
  ),
);
