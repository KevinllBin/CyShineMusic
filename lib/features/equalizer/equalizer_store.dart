import 'dart:async';
import 'dart:convert';

import 'package:bass_player/bass_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/settings_store.dart';

const equalizerMinFrequencyHz = 20.0;
const equalizerMaxFrequencyHz = 20000.0;
const equalizerMinGainDb = -24.0;
const equalizerMaxGainDb = 24.0;
const equalizerMinQ = 0.1;
const equalizerMaxQ = 10.0;
const equalizerMaxBands = 32;

const _equalizerStorageKey = 'bass_equalizer_settings_v1';
const _persistDelay = Duration(milliseconds: 350);

enum EqualizerFilterType {
  peaking('峰值', 'Peaking', BassBiquadFilter.peaking, true),
  lowShelf('低架', 'LowShelf', BassBiquadFilter.lowShelf, true),
  highShelf('高架', 'HighShelf', BassBiquadFilter.highShelf, true),
  lowPass('低通', 'LowPass', BassBiquadFilter.lowPass, false),
  highPass('高通', 'HighPass', BassBiquadFilter.highPass, false);

  const EqualizerFilterType(
    this.label,
    this.serializedName,
    this.bassType,
    this.usesGain,
  );

  final String label;
  final String serializedName;
  final BassBiquadFilter bassType;
  final bool usesGain;

  static EqualizerFilterType fromName(String? value) {
    final normalized = value?.replaceAll(RegExp(r'[_\s-]'), '').toLowerCase();
    return switch (normalized) {
      'lowshelf' => lowShelf,
      'highshelf' => highShelf,
      'lowpass' => lowPass,
      'highpass' => highPass,
      // Early CyShineMusic builds exposed filters that Salt does not use.
      _ => peaking,
    };
  }
}

@immutable
class EqualizerBandSetting {
  const EqualizerBandSetting({
    required this.id,
    required this.frequencyHz,
    this.enabled = true,
    this.gainDb = 0,
    this.q = 0.707,
    this.filter = EqualizerFilterType.peaking,
  });

  final String id;
  final bool enabled;
  final double frequencyHz;
  final double gainDb;
  final double q;
  final EqualizerFilterType filter;

  EqualizerBandSetting copyWith({
    String? id,
    bool? enabled,
    double? frequencyHz,
    double? gainDb,
    double? q,
    EqualizerFilterType? filter,
  }) {
    return EqualizerBandSetting(
      id: id ?? this.id,
      enabled: enabled ?? this.enabled,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      gainDb: gainDb ?? this.gainDb,
      q: q ?? this.q,
      filter: filter ?? this.filter,
    );
  }

  EqualizerBandSetting sanitized() {
    return copyWith(
      id: id.trim(),
      frequencyHz: _finiteOr(
        frequencyHz,
        1000,
      ).clamp(equalizerMinFrequencyHz, equalizerMaxFrequencyHz),
      gainDb: _finiteOr(
        gainDb,
        0,
      ).clamp(equalizerMinGainDb, equalizerMaxGainDb),
      q: _finiteOr(q, 0.707).clamp(equalizerMinQ, equalizerMaxQ),
    );
  }

  BassEqualizerBand toBassBand() {
    final value = sanitized();
    return BassEqualizerBand(
      id: value.id,
      enabled: value.enabled,
      filter: value.filter.bassType,
      frequencyHz: value.frequencyHz,
      gainDb: value.filter.usesGain ? value.gainDb : 0,
      q: value.q,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'enabled': enabled,
    'type': filter.serializedName,
    'frequency': frequencyHz,
    'gain': filter.usesGain ? gainDb : 0,
    'q': q,
  };

  factory EqualizerBandSetting.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final frequency = _number(json['frequency'] ?? json['frequencyHz']);
    if (id.isEmpty || frequency == null || !frequency.isFinite) {
      throw const FormatException('均衡器频段数据无效');
    }
    return EqualizerBandSetting(
      id: id,
      enabled: json['enabled'] as bool? ?? true,
      frequencyHz: frequency,
      gainDb: _number(json['gain'] ?? json['gainDb']) ?? 0,
      q: _number(json['q']) ?? 0.707,
      filter: EqualizerFilterType.fromName(
        (json['type'] ?? json['filter'])?.toString(),
      ),
    ).sanitized();
  }
}

@immutable
class EqualizerPreset {
  const EqualizerPreset({
    required this.id,
    required this.label,
    this.inputGainDb = 0,
    this.outputGainDb = 0,
    this.bands = const [],
  });

  final String id;
  final String label;
  final double inputGainDb;
  final double outputGainDb;
  final List<EqualizerBandSetting> bands;

  Map<String, Object> toJson() => {
    'id': id,
    'name': label,
    'inputGain': inputGainDb,
    'outputGain': outputGainDb,
    'bands': bands.map((band) => band.toJson()).toList(growable: false),
  };

  factory EqualizerPreset.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final rawBands = json['bands'];
    if (id.isEmpty || name.isEmpty || rawBands is! List) {
      throw const FormatException('均衡器预设格式无效');
    }
    return EqualizerPreset(
      id: id,
      label: name,
      inputGainDb: (_number(json['inputGain'] ?? json['inputGainDb']) ?? 0)
          .clamp(equalizerMinGainDb, equalizerMaxGainDb),
      outputGainDb: (_number(json['outputGain'] ?? json['outputGainDb']) ?? 0)
          .clamp(equalizerMinGainDb, equalizerMaxGainDb),
      bands: _decodeBands(rawBands),
    );
  }
}

@immutable
class EqualizerSettings {
  const EqualizerSettings({
    required this.enabled,
    required this.inputGainDb,
    required this.outputGainDb,
    required this.bands,
    this.presetId,
  });

  final bool enabled;
  final double inputGainDb;
  final double outputGainDb;
  final List<EqualizerBandSetting> bands;
  final String? presetId;

  String get summary {
    if (!enabled) return '已关闭 · 参数会保留';
    final preset = equalizerPresets
        .where((candidate) => candidate.id == presetId)
        .firstOrNull;
    final activeCount = bands.where((band) => band.enabled).length;
    return '${preset?.label ?? '自定义'} · $activeCount/${bands.length} 段启用';
  }

  EqualizerSettings copyWith({
    bool? enabled,
    double? inputGainDb,
    double? outputGainDb,
    List<EqualizerBandSetting>? bands,
    String? presetId,
    bool clearPreset = false,
  }) {
    return EqualizerSettings(
      enabled: enabled ?? this.enabled,
      inputGainDb: inputGainDb ?? this.inputGainDb,
      outputGainDb: outputGainDb ?? this.outputGainDb,
      bands: bands ?? this.bands,
      presetId: clearPreset ? null : presetId ?? this.presetId,
    );
  }

  EqualizerSettings sanitized() {
    if (bands.length > equalizerMaxBands) {
      throw const FormatException('均衡器最多支持 32 个频段');
    }
    final sanitizedBands = bands.map((band) => band.sanitized()).toList();
    if (sanitizedBands.any((band) => band.id.isEmpty) ||
        sanitizedBands.map((band) => band.id).toSet().length !=
            sanitizedBands.length) {
      throw const FormatException('均衡器频段 ID 无效或重复');
    }
    return copyWith(
      inputGainDb: _finiteOr(
        inputGainDb,
        0,
      ).clamp(equalizerMinGainDb, equalizerMaxGainDb),
      outputGainDb: _finiteOr(
        outputGainDb,
        0,
      ).clamp(equalizerMinGainDb, equalizerMaxGainDb),
      bands: List.unmodifiable(sanitizedBands),
    );
  }

  BassEqualizerConfiguration toBassConfiguration() {
    final value = sanitized();
    return BassEqualizerConfiguration(
      enabled: value.enabled,
      inputGainDb: value.inputGainDb,
      outputGainDb: value.outputGainDb,
      bands: value.bands
          .map((band) => band.toBassBand())
          .toList(growable: false),
    );
  }

  Map<String, Object?> toJson() => {
    'version': 2,
    'enabled': enabled,
    'inputGainDb': inputGainDb,
    'outputGainDb': outputGainDb,
    'presetId': presetId,
    'bands': bands.map((band) => band.toJson()).toList(growable: false),
  };

  String toPersistedJson() => jsonEncode(toJson());

  String toSpeq() {
    final preset = EqualizerPreset(
      id: presetId ?? 'cyshine.custom',
      label:
          equalizerPresets
              .where((candidate) => candidate.id == presetId)
              .firstOrNull
              ?.label ??
          'CyShineMusic',
      inputGainDb: inputGainDb,
      outputGainDb: outputGainDb,
      bands: bands,
    );
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'speq.equalizer-presets',
      'version': 1,
      'presets': [preset.toJson()],
    });
  }

  factory EqualizerSettings.fromJson(Map<String, dynamic> json) {
    final rawBands = json['bands'];
    if (rawBands is! List) {
      throw const FormatException('均衡器频段数据无效');
    }
    return EqualizerSettings(
      enabled: json['enabled'] as bool? ?? false,
      inputGainDb: _number(json['inputGainDb'] ?? json['inputGain']) ?? 0,
      outputGainDb: _number(json['outputGainDb'] ?? json['outputGain']) ?? 0,
      bands: _decodeBands(rawBands),
      presetId: json['presetId']?.toString(),
    ).sanitized();
  }

  factory EqualizerSettings.fromSpeq(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map) throw const FormatException('均衡器文件不是有效对象');
    final root = Map<String, dynamic>.from(decoded);
    if (root['format'] == 'speq.equalizer-presets') {
      if (root['version'] != 1 || root['presets'] is! List) {
        throw const FormatException('不支持的 .speq 格式');
      }
      final presets = root['presets'] as List;
      if (presets.isEmpty) throw const FormatException('.speq 中没有预设');
      final preset = EqualizerPreset.fromJson(
        Map<String, dynamic>.from(presets.first as Map),
      );
      return EqualizerSettings(
        enabled: true,
        inputGainDb: preset.inputGainDb,
        outputGainDb: preset.outputGainDb,
        bands: preset.bands,
      ).sanitized();
    }
    return EqualizerSettings.fromJson(root);
  }

  static const fallback = EqualizerSettings(
    enabled: false,
    inputGainDb: 0,
    outputGainDb: 0,
    bands: [],
    presetId: 'builtin.original',
  );
}

EqualizerBandSetting _band(
  String id,
  EqualizerFilterType type,
  double frequency,
  double gain, [
  double q = 0.7,
]) {
  return EqualizerBandSetting(
    id: id,
    filter: type,
    frequencyHz: frequency,
    gainDb: gain,
    q: q,
  );
}

EqualizerPreset _preset(
  String id,
  String label,
  double inputGain,
  List<EqualizerBandSetting> bands,
) {
  return EqualizerPreset(
    id: id,
    label: label,
    inputGainDb: inputGain,
    bands: List.unmodifiable(bands),
  );
}

final equalizerPresets = List<EqualizerPreset>.unmodifiable([
  const EqualizerPreset(id: 'builtin.original', label: '原声'),
  _preset('builtin.studio_reference', '录音室参考', -2, [
    _band('reference.foundation', EqualizerFilterType.lowShelf, 90, 1.5),
    _band('reference.mud', EqualizerFilterType.peaking, 320, -1.2, 1.1),
    _band('reference.presence', EqualizerFilterType.peaking, 3200, 1.5, 1),
    _band('reference.air', EqualizerFilterType.highShelf, 10000, 1.8),
  ]),
  _preset('builtin.mix_translation', '混音校准', -2, [
    _band('translation.sub', EqualizerFilterType.lowShelf, 75, -0.8),
    _band('translation.mud', EqualizerFilterType.peaking, 250, -1.2, 1.1),
    _band('translation.box', EqualizerFilterType.peaking, 850, -0.7, 1.2),
    _band('translation.presence', EqualizerFilterType.peaking, 3000, 1.2, 1),
    _band('translation.air', EqualizerFilterType.highShelf, 11000, 1.5),
  ]),
  _preset('builtin.low_mid_cleanup', '低中频清理', -1.5, [
    _band('cleanup.warmth', EqualizerFilterType.peaking, 180, -1.2, 1),
    _band('cleanup.mud', EqualizerFilterType.peaking, 320, -3, 1.1),
    _band('cleanup.box', EqualizerFilterType.peaking, 650, -1.5, 1.2),
    _band('cleanup.focus', EqualizerFilterType.peaking, 2500, 1, 1),
  ]),
  _preset('builtin.smooth_treble', '柔顺高频', -1, [
    _band('smooth.balance', EqualizerFilterType.lowShelf, 120, 1),
    _band('smooth.presence', EqualizerFilterType.peaking, 3200, -1, 1.1),
    _band('smooth.sibilance', EqualizerFilterType.peaking, 5800, -2.5, 1.4),
    _band('smooth.top', EqualizerFilterType.highShelf, 10000, -1.5),
  ]),
  _preset('builtin.air_and_detail', '空气感与细节', -3, [
    _band('detail.clean', EqualizerFilterType.peaking, 420, -1, 1),
    _band('detail.presence', EqualizerFilterType.peaking, 2800, 1.2, 1),
    _band('detail.texture', EqualizerFilterType.peaking, 5800, 1.5, 1.1),
    _band('detail.air', EqualizerFilterType.highShelf, 10500, 3),
  ]),
  _preset('builtin.sub_bass_extension', '超低频延伸', -5, [
    _band('subextension.depth', EqualizerFilterType.lowShelf, 45, 4.5, 0.65),
    _band('subextension.weight', EqualizerFilterType.peaking, 72, 2, 0.9),
    _band('subextension.transition', EqualizerFilterType.peaking, 155, -1.2, 1),
    _band('subextension.clean', EqualizerFilterType.peaking, 320, -1.3, 1.1),
  ]),
  _preset('builtin.bass_boost', '低频解析', -4, [
    _band('bass.foundation', EqualizerFilterType.lowShelf, 78, 3.2),
    _band('bass.punch', EqualizerFilterType.peaking, 145, 2, 0.9),
    _band('bass.mud', EqualizerFilterType.peaking, 310, -1.8, 1.1),
    _band('bass.box', EqualizerFilterType.peaking, 720, -1.2, 1.2),
    _band('bass.definition', EqualizerFilterType.peaking, 2400, 0.8, 1),
  ]),
  _preset('builtin.vinyl', '黑胶', -2.5, [
    _band('vinyl.weight', EqualizerFilterType.lowShelf, 120, 3),
    _band('vinyl.body', EqualizerFilterType.peaking, 420, 1.8, 0.9),
    _band('vinyl.edge', EqualizerFilterType.peaking, 3200, -2.5, 1),
    _band('vinyl.rolloff', EqualizerFilterType.highShelf, 8500, -5),
    _band('vinyl.ceiling', EqualizerFilterType.lowPass, 16000, 0),
  ]),
  _preset('builtin.clear_vocals', '清澈人声', -4.5, [
    _band('vocal.rumble', EqualizerFilterType.lowShelf, 110, -2),
    _band('vocal.mud', EqualizerFilterType.peaking, 260, -3, 1),
    _band('vocal.box', EqualizerFilterType.peaking, 650, -1.5, 1.2),
    _band('vocal.presence', EqualizerFilterType.peaking, 2800, 5, 1),
    _band('vocal.air', EqualizerFilterType.highShelf, 9000, 3.5),
  ]),
  _preset('builtin.female_vocals', '女声', -4.5, [
    _band('female.rumble', EqualizerFilterType.lowShelf, 100, -2.5),
    _band('female.warmth', EqualizerFilterType.peaking, 280, -2, 1),
    _band('female.focus', EqualizerFilterType.peaking, 3200, 4.8, 1),
    _band('female.detail', EqualizerFilterType.peaking, 7000, 2.5, 1.1),
    _band('female.air', EqualizerFilterType.highShelf, 11000, 2.5),
  ]),
  _preset('builtin.male_vocals', '男声', -4, [
    _band('male.foundation', EqualizerFilterType.lowShelf, 110, 2.5),
    _band('male.chest', EqualizerFilterType.peaking, 280, 3, 0.9),
    _band('male.nasal', EqualizerFilterType.peaking, 900, -2, 1.2),
    _band('male.focus', EqualizerFilterType.peaking, 2200, 4.5, 1),
    _band('male.air', EqualizerFilterType.highShelf, 9000, 1.5),
  ]),
  _preset('builtin.acoustic', '原声乐器', -4, [
    _band('acoustic.body', EqualizerFilterType.lowShelf, 110, 2.5),
    _band('acoustic.mud', EqualizerFilterType.peaking, 300, -2.5, 1),
    _band('acoustic.wood', EqualizerFilterType.peaking, 1600, 2, 1),
    _band('acoustic.attack', EqualizerFilterType.peaking, 4500, 3.8, 1),
    _band('acoustic.air', EqualizerFilterType.highShelf, 10000, 2.5),
  ]),
  _preset('builtin.live_folk', '现场民谣', -5, [
    _band('folk.floor', EqualizerFilterType.lowShelf, 90, 3.5),
    _band('folk.wood', EqualizerFilterType.peaking, 260, 2.5, 0.9),
    _band('folk.hollow', EqualizerFilterType.peaking, 720, -2.5, 1.1),
    _band('folk.voice', EqualizerFilterType.peaking, 2500, 3.8, 1),
    _band('folk.strings', EqualizerFilterType.peaking, 7000, 3, 1),
    _band('folk.air', EqualizerFilterType.highShelf, 11000, 2),
  ]),
  _preset('builtin.ancient_style_stereo', '古风立体声', -5.5, [
    _band('ancient.depth', EqualizerFilterType.lowShelf, 90, 2.5),
    _band('ancient.warmth', EqualizerFilterType.peaking, 190, 3.5, 0.9),
    _band('ancient.space', EqualizerFilterType.peaking, 520, -3.5, 1),
    _band('ancient.pluck', EqualizerFilterType.peaking, 1800, 3, 1),
    _band('ancient.detail', EqualizerFilterType.peaking, 5200, 4.5, 1),
    _band('ancient.air', EqualizerFilterType.highShelf, 10000, 3.5),
  ]),
  _preset('builtin.concert', '演唱会', -6.5, [
    _band('concert.sub', EqualizerFilterType.lowShelf, 75, 5),
    _band('concert.body', EqualizerFilterType.peaking, 240, 2.5, 0.9),
    _band('concert.clean', EqualizerFilterType.peaking, 650, -3.5, 1),
    _band('concert.presence', EqualizerFilterType.peaking, 2600, 3.5, 1),
    _band('concert.energy', EqualizerFilterType.peaking, 7500, 4.5, 1),
    _band('concert.air', EqualizerFilterType.highShelf, 12000, 2.5),
  ]),
  _preset('builtin.music_hall', '音乐厅', -5, [
    _band('hall.floor', EqualizerFilterType.lowShelf, 85, 3),
    _band('hall.body', EqualizerFilterType.peaking, 300, 3.2, 0.9),
    _band('hall.space', EqualizerFilterType.peaking, 850, -3, 1),
    _band('hall.presence', EqualizerFilterType.peaking, 2800, 2.5, 1),
    _band('hall.air', EqualizerFilterType.highShelf, 9500, 3.5),
  ]),
  _preset('builtin.classical', '古典', -4, [
    _band('classical.depth', EqualizerFilterType.lowShelf, 90, 2.5),
    _band('classical.clean', EqualizerFilterType.peaking, 300, -1.5, 1),
    _band('classical.strings', EqualizerFilterType.peaking, 1800, 2, 1),
    _band('classical.detail', EqualizerFilterType.peaking, 4500, 2.8, 1),
    _band('classical.air', EqualizerFilterType.highShelf, 10000, 3.5),
  ]),
  _preset('builtin.jazz', '爵士', -4.5, [
    _band('jazz.bass', EqualizerFilterType.lowShelf, 100, 3.5),
    _band('jazz.body', EqualizerFilterType.peaking, 320, 2.5, 0.9),
    _band('jazz.clean', EqualizerFilterType.peaking, 850, -2.5, 1),
    _band('jazz.brass', EqualizerFilterType.peaking, 3000, 2.5, 1),
    _band('jazz.cymbal', EqualizerFilterType.highShelf, 8500, 3.5),
  ]),
  _preset('builtin.cinematic', '影院', -7.5, [
    _band('cinematic.sub', EqualizerFilterType.lowShelf, 65, 7),
    _band('cinematic.weight', EqualizerFilterType.peaking, 180, 3, 0.9),
    _band('cinematic.space', EqualizerFilterType.peaking, 700, -3.5, 1),
    _band('cinematic.dialog', EqualizerFilterType.peaking, 2400, 2.5, 1),
    _band('cinematic.impact', EqualizerFilterType.peaking, 6000, 3.5, 1),
    _band('cinematic.air', EqualizerFilterType.highShelf, 11000, 4),
  ]),
  _preset('builtin.acg', 'ACG', -5.5, [
    _band('acg.bass', EqualizerFilterType.lowShelf, 85, 3.5),
    _band('acg.clean', EqualizerFilterType.peaking, 320, -2.5, 1),
    _band('acg.space', EqualizerFilterType.peaking, 1100, -1.5, 1),
    _band('acg.vocal', EqualizerFilterType.peaking, 3400, 5.5, 1),
    _band('acg.sparkle', EqualizerFilterType.peaking, 7500, 3.5, 1),
    _band('acg.air', EqualizerFilterType.highShelf, 11000, 2.5),
  ]),
  _preset('builtin.hip_hop', '嘻哈', -7.5, [
    _band('hiphop.sub', EqualizerFilterType.lowShelf, 70, 7.5),
    _band('hiphop.punch', EqualizerFilterType.peaking, 160, 4, 0.9),
    _band('hiphop.clean', EqualizerFilterType.peaking, 500, -3.5, 1),
    _band('hiphop.voice', EqualizerFilterType.peaking, 2200, 3, 1),
    _band('hiphop.snap', EqualizerFilterType.highShelf, 8500, 4),
  ]),
  _preset('builtin.electronic', '电子', -6.5, [
    _band('electronic.sub', EqualizerFilterType.lowShelf, 70, 6),
    _band('electronic.clean', EqualizerFilterType.peaking, 280, -2.5, 1),
    _band('electronic.space', EqualizerFilterType.peaking, 1000, -2.5, 1),
    _band('electronic.lead', EqualizerFilterType.peaking, 4000, 4.5, 1),
    _band('electronic.air', EqualizerFilterType.highShelf, 9000, 4.5),
  ]),
  _preset('builtin.dance', '舞曲', -6.5, [
    _band('dance.sub', EqualizerFilterType.lowShelf, 75, 6),
    _band('dance.kick', EqualizerFilterType.peaking, 170, 3, 0.9),
    _band('dance.clean', EqualizerFilterType.peaking, 520, -3.5, 1),
    _band('dance.lead', EqualizerFilterType.peaking, 2800, 3.5, 1),
    _band('dance.sparkle', EqualizerFilterType.highShelf, 8500, 4.5),
  ]),
  _preset('builtin.rock', '摇滚', -5.5, [
    _band('rock.kick', EqualizerFilterType.lowShelf, 90, 4),
    _band('rock.body', EqualizerFilterType.peaking, 200, 2.5, 0.9),
    _band('rock.mud', EqualizerFilterType.peaking, 450, -3.5, 1),
    _band('rock.guitar', EqualizerFilterType.peaking, 1800, 3.5, 1),
    _band('rock.attack', EqualizerFilterType.peaking, 4200, 4.5, 1),
    _band('rock.air', EqualizerFilterType.highShelf, 10000, 2),
  ]),
  _preset('builtin.metal', '金属', -6.5, [
    _band('metal.kick', EqualizerFilterType.lowShelf, 85, 5),
    _band('metal.mud', EqualizerFilterType.peaking, 280, -3.5, 1),
    _band('metal.box', EqualizerFilterType.peaking, 800, -2.5, 1),
    _band('metal.guitar', EqualizerFilterType.peaking, 2200, 4.5, 1),
    _band('metal.attack', EqualizerFilterType.peaking, 5000, 5.5, 1),
    _band('metal.air', EqualizerFilterType.highShelf, 11000, 2.5),
  ]),
  _preset('builtin.warm', '温暖', -1.5, [
    _band('warm.low_shelf', EqualizerFilterType.lowShelf, 140, 3),
    _band('warm.edge', EqualizerFilterType.peaking, 3500, -1.5, 1),
    _band('warm.high_shelf', EqualizerFilterType.highShelf, 10000, -2),
  ]),
  _preset('builtin.bright', '明亮', -2, [
    _band('bright.presence', EqualizerFilterType.peaking, 4000, 2, 1),
    _band('bright.high_shelf', EqualizerFilterType.highShelf, 9500, 3.5),
  ]),
  _preset('builtin.lo_fi', 'Lo-Fi', -3.5, [
    _band('lofi.floor', EqualizerFilterType.highPass, 65, 0),
    _band('lofi.weight', EqualizerFilterType.lowShelf, 160, 3.5),
    _band('lofi.box', EqualizerFilterType.peaking, 450, 3, 1),
    _band('lofi.presence', EqualizerFilterType.peaking, 2500, -3.5, 1),
    _band('lofi.ceiling', EqualizerFilterType.lowPass, 9000, 0),
  ]),
  _preset('builtin.late_night', '深夜', -4.5, [
    _band('night.bass', EqualizerFilterType.lowShelf, 100, 4.5),
    _band('night.warmth', EqualizerFilterType.peaking, 320, 2.5, 0.9),
    _band('night.presence', EqualizerFilterType.peaking, 2800, -2.5, 1),
    _band('night.soft', EqualizerFilterType.highShelf, 7500, -5),
  ]),
]);

List<EqualizerBandSetting> defaultEqualizerBands([List<double>? gains]) {
  const frequencies = <double>[
    31.5,
    63,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000,
  ];
  final resolved = gains ?? List<double>.filled(frequencies.length, 0);
  return List.unmodifiable([
    for (var index = 0; index < frequencies.length; index++)
      EqualizerBandSetting(
        id: 'graphic-$index',
        frequencyHz: frequencies[index],
        gainDb: index < resolved.length ? resolved[index] : 0,
      ),
  ]);
}

double nextEqualizerBandFrequency(Iterable<EqualizerBandSetting> bands) {
  const candidates = <double>[60, 120, 250, 500, 1000, 2000, 4000, 8000, 16000];
  for (final candidate in candidates) {
    if (bands.every((band) => (band.frequencyHz - candidate).abs() >= 10)) {
      return candidate;
    }
  }
  return 1000;
}

class EqualizerNotifier extends Notifier<EqualizerSettings> {
  late SharedPreferences _preferences;
  Timer? _persistTimer;

  @override
  EqualizerSettings build() {
    _preferences = ref.read(sharedPreferencesProvider);
    ref.onDispose(() {
      _persistTimer?.cancel();
    });
    final encoded = _preferences.getString(_equalizerStorageKey);
    if (encoded == null) return EqualizerSettings.fallback;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const FormatException();
      return EqualizerSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      unawaited(_preferences.remove(_equalizerStorageKey));
      return EqualizerSettings.fallback;
    }
  }

  void setEnabled(bool value) => _update(state.copyWith(enabled: value));

  void setInputGain(double value) =>
      _update(state.copyWith(inputGainDb: value, clearPreset: true));

  void setOutputGain(double value) =>
      _update(state.copyWith(outputGainDb: value, clearPreset: true));

  void setBandEnabled(String id, bool value) {
    _replaceBand(id, (band) => band.copyWith(enabled: value));
  }

  void setBandGain(String id, double value) {
    _replaceBand(id, (band) => band.copyWith(gainDb: value));
  }

  void updateBand(EqualizerBandSetting band) {
    _replaceBand(band.id, (_) => band);
  }

  bool addBand(EqualizerBandSetting band) {
    if (state.bands.length >= equalizerMaxBands ||
        state.bands.any((current) => current.id == band.id)) {
      return false;
    }
    _update(
      state.copyWith(
        bands: List.unmodifiable([...state.bands, band]),
        clearPreset: true,
      ),
    );
    return true;
  }

  bool removeBand(String id) {
    if (!state.bands.any((band) => band.id == id)) return false;
    _update(
      state.copyWith(
        bands: List.unmodifiable(state.bands.where((band) => band.id != id)),
        clearPreset: true,
      ),
    );
    return true;
  }

  void applyPreset(EqualizerPreset preset) {
    _update(
      EqualizerSettings(
        enabled: state.enabled,
        inputGainDb: preset.inputGainDb,
        outputGainDb: preset.outputGainDb,
        bands: List.unmodifiable(preset.bands),
        presetId: preset.id,
      ),
    );
  }

  void reset() => _update(EqualizerSettings.fallback);

  void importSpeq(String value) {
    final imported = EqualizerSettings.fromSpeq(value);
    _update(imported.copyWith(enabled: state.enabled));
  }

  void _replaceBand(
    String id,
    EqualizerBandSetting Function(EqualizerBandSetting band) replace,
  ) {
    final index = state.bands.indexWhere((band) => band.id == id);
    if (index < 0) return;
    final bands = [...state.bands];
    bands[index] = replace(bands[index]);
    _update(state.copyWith(bands: List.unmodifiable(bands), clearPreset: true));
  }

  void _update(EqualizerSettings value) {
    state = value.sanitized();
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDelay, () {
      _persistTimer = null;
      unawaited(_persist(state));
    });
  }

  Future<void> _persist(EqualizerSettings value) {
    return _preferences.setString(
      _equalizerStorageKey,
      value.toPersistedJson(),
    );
  }
}

final equalizerProvider =
    NotifierProvider<EqualizerNotifier, EqualizerSettings>(
      EqualizerNotifier.new,
    );

List<EqualizerBandSetting> _decodeBands(List<dynamic> rawBands) {
  if (rawBands.length > equalizerMaxBands) {
    throw const FormatException('均衡器最多支持 32 个频段');
  }
  return List.unmodifiable(
    rawBands.map(
      (value) => EqualizerBandSetting.fromJson(
        Map<String, dynamic>.from(value as Map),
      ),
    ),
  );
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

double _finiteOr(double value, double fallback) =>
    value.isFinite ? value : fallback;
