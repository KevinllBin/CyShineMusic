import '../../../core/storage/settings_store.dart';

// Secondary lines keep readable defaults when the main lyrics are made
// smaller or lighter, and continue scaling up with larger lyric settings.
double lyricSecondaryFontWeight(double mainWeight) =>
    (mainWeight - 100).clamp(400.0, kLyricFontWeightMax);

double lyricTranslationFontSize(double mainSize) =>
    (14 * mainSize / kLyricFontSizeDefault).clamp(14.0, double.infinity);

double lyricRomanFontSize(double mainSize) =>
    (12 * mainSize / kLyricFontSizeDefault).clamp(12.0, double.infinity);
