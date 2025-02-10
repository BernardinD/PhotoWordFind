// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$Location on _Location, Store {
  late final _$rawLocationAtom =
      Atom(name: '_Location.rawLocation', context: context);

  @override
  String get rawLocation {
    _$rawLocationAtom.reportRead();
    return super.rawLocation;
  }

  @override
  set rawLocation(String value) {
    _$rawLocationAtom.reportWrite(value, super.rawLocation, () {
      super.rawLocation = value;
    });
  }

  late final _$timezoneAtom =
      Atom(name: '_Location.timezone', context: context);

  @override
  String? get timezone {
    _$timezoneAtom.reportRead();
    return super.timezone;
  }

  @override
  set timezone(String? value) {
    _$timezoneAtom.reportWrite(value, super.timezone, () {
      super.timezone = value;
    });
  }

  late final _$utcOffsetAtom =
      Atom(name: '_Location.utcOffset', context: context);

  @override
  int? get utcOffset {
    _$utcOffsetAtom.reportRead();
    return super.utcOffset;
  }

  @override
  set utcOffset(int? value) {
    _$utcOffsetAtom.reportWrite(value, super.utcOffset, () {
      super.utcOffset = value;
    });
  }

  @override
  String toString() {
    return '''
rawLocation: ${rawLocation},
timezone: ${timezone},
utcOffset: ${utcOffset}
    ''';
  }
}
