// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of '../models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$IconButtonData implements DiagnosticableTreeMixin {

 Glyph get glyph; VoidCallback? get onPressed; String? get tooltip; bool get isLoading;/// Non-null makes the button a toggle that shows this state.
 bool? get isSelected;
/// Create a copy of IconButtonData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IconButtonDataCopyWith<IconButtonData> get copyWith => _$IconButtonDataCopyWithImpl<IconButtonData>(this as IconButtonData, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  final _this = this as IconButtonData;
  properties
    ..add(DiagnosticsProperty('type', 'IconButtonData'))
    ..add(DiagnosticsProperty('glyph', _this.glyph))..add(DiagnosticsProperty('onPressed', _this.onPressed))..add(DiagnosticsProperty('tooltip', _this.tooltip))..add(DiagnosticsProperty('isLoading', _this.isLoading))..add(DiagnosticsProperty('isSelected', _this.isSelected));
}

@override
bool operator ==(Object other) {
  final _this = this as IconButtonData;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is IconButtonData&&(identical(other.glyph, _this.glyph) || other.glyph == _this.glyph)&&(identical(other.onPressed, _this.onPressed) || other.onPressed == _this.onPressed)&&(identical(other.tooltip, _this.tooltip) || other.tooltip == _this.tooltip)&&(identical(other.isLoading, _this.isLoading) || other.isLoading == _this.isLoading)&&(identical(other.isSelected, _this.isSelected) || other.isSelected == _this.isSelected));
}


@override
int get hashCode {
  final _this = this as IconButtonData;
  return Object.hash(runtimeType,_this.glyph,_this.onPressed,_this.tooltip,_this.isLoading,_this.isSelected);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  final _this = this as IconButtonData;
  return 'IconButtonData(glyph: ${_this.glyph}, onPressed: ${_this.onPressed}, tooltip: ${_this.tooltip}, isLoading: ${_this.isLoading}, isSelected: ${_this.isSelected})';
}


}

/// @nodoc
abstract mixin class $IconButtonDataCopyWith<$Res>  {
  factory $IconButtonDataCopyWith(IconButtonData value, $Res Function(IconButtonData) _then) = _$IconButtonDataCopyWithImpl;
@useResult
$Res call({
 Glyph glyph, VoidCallback? onPressed, String? tooltip, bool isLoading, bool? isSelected
});




}
/// @nodoc
class _$IconButtonDataCopyWithImpl<$Res>
    implements $IconButtonDataCopyWith<$Res> {
  _$IconButtonDataCopyWithImpl(this._self, this._then);

  final IconButtonData _self;
  final $Res Function(IconButtonData) _then;

/// Create a copy of IconButtonData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? glyph = null,Object? onPressed = freezed,Object? tooltip = freezed,Object? isLoading = null,Object? isSelected = freezed,}) {
  return _then(IconButtonData(
glyph: null == glyph ? _self.glyph : glyph // ignore: cast_nullable_to_non_nullable
as Glyph,onPressed: freezed == onPressed ? _self.onPressed : onPressed // ignore: cast_nullable_to_non_nullable
as VoidCallback?,tooltip: freezed == tooltip ? _self.tooltip : tooltip // ignore: cast_nullable_to_non_nullable
as String?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isSelected: freezed == isSelected ? _self.isSelected : isSelected // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

}


/// Adds pattern-matching-related methods to [IconButtonData].
extension IconButtonDataPatterns on IconButtonData {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _IconButtonData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _IconButtonData() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _IconButtonData value)  $default,){
final _that = this;
switch (_that) {
case _IconButtonData():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _IconButtonData value)?  $default,){
final _that = this;
switch (_that) {
case _IconButtonData() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( Glyph glyph,  VoidCallback? onPressed,  String? tooltip,  bool isLoading,  bool? isSelected)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _IconButtonData() when $default != null:
return $default(_that.glyph,_that.onPressed,_that.tooltip,_that.isLoading,_that.isSelected);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( Glyph glyph,  VoidCallback? onPressed,  String? tooltip,  bool isLoading,  bool? isSelected)  $default,) {final _that = this;
switch (_that) {
case _IconButtonData():
return $default(_that.glyph,_that.onPressed,_that.tooltip,_that.isLoading,_that.isSelected);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( Glyph glyph,  VoidCallback? onPressed,  String? tooltip,  bool isLoading,  bool? isSelected)?  $default,) {final _that = this;
switch (_that) {
case _IconButtonData() when $default != null:
return $default(_that.glyph,_that.onPressed,_that.tooltip,_that.isLoading,_that.isSelected);case _:
  return null;

}
}

}

/// @nodoc


class _IconButtonData with DiagnosticableTreeMixin implements IconButtonData {
  const _IconButtonData({required this.glyph, required this.onPressed, this.tooltip, this.isLoading = false, this.isSelected});
  

@override final  Glyph glyph;
@override final  VoidCallback? onPressed;
@override final  String? tooltip;
@override@JsonKey() final  bool isLoading;
/// Non-null makes the button a toggle that shows this state.
@override final  bool? isSelected;

/// Create a copy of IconButtonData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$IconButtonDataCopyWith<_IconButtonData> get copyWith => __$IconButtonDataCopyWithImpl<_IconButtonData>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    properties
    ..add(DiagnosticsProperty('type', 'IconButtonData'))
    ..add(DiagnosticsProperty('glyph', glyph))..add(DiagnosticsProperty('onPressed', onPressed))..add(DiagnosticsProperty('tooltip', tooltip))..add(DiagnosticsProperty('isLoading', isLoading))..add(DiagnosticsProperty('isSelected', isSelected));
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _IconButtonData&&(identical(other.glyph, glyph) || other.glyph == glyph)&&(identical(other.onPressed, onPressed) || other.onPressed == onPressed)&&(identical(other.tooltip, tooltip) || other.tooltip == tooltip)&&(identical(other.isLoading, isLoading) || other.isLoading == isLoading)&&(identical(other.isSelected, isSelected) || other.isSelected == isSelected));
}


@override
int get hashCode {
    return Object.hash(runtimeType,glyph,onPressed,tooltip,isLoading,isSelected);
}

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
    return 'IconButtonData(glyph: $glyph, onPressed: $onPressed, tooltip: $tooltip, isLoading: $isLoading, isSelected: $isSelected)';
}


}

/// @nodoc
abstract mixin class _$IconButtonDataCopyWith<$Res> implements $IconButtonDataCopyWith<$Res> {
  factory _$IconButtonDataCopyWith(_IconButtonData value, $Res Function(_IconButtonData) _then) = __$IconButtonDataCopyWithImpl;
@override @useResult
$Res call({
 Glyph glyph, VoidCallback? onPressed, String? tooltip, bool isLoading, bool? isSelected
});




}
/// @nodoc
class __$IconButtonDataCopyWithImpl<$Res>
    implements _$IconButtonDataCopyWith<$Res> {
  __$IconButtonDataCopyWithImpl(this._self, this._then);

  final _IconButtonData _self;
  final $Res Function(_IconButtonData) _then;

/// Create a copy of IconButtonData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? glyph = null,Object? onPressed = freezed,Object? tooltip = freezed,Object? isLoading = null,Object? isSelected = freezed,}) {
  return _then(_IconButtonData(
glyph: null == glyph ? _self.glyph : glyph // ignore: cast_nullable_to_non_nullable
as Glyph,onPressed: freezed == onPressed ? _self.onPressed : onPressed // ignore: cast_nullable_to_non_nullable
as VoidCallback?,tooltip: freezed == tooltip ? _self.tooltip : tooltip // ignore: cast_nullable_to_non_nullable
as String?,isLoading: null == isLoading ? _self.isLoading : isLoading // ignore: cast_nullable_to_non_nullable
as bool,isSelected: freezed == isSelected ? _self.isSelected : isSelected // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

// dart format on
