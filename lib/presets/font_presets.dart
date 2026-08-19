class FontChoice {
  final String family;
  final String label;

  /// Extra tracking that suits this face when set in caps.
  final double tracking;
  const FontChoice(this.family, this.label, {this.tracking = 0.3});
}

const List<FontChoice> kFonts = [
  FontChoice('Inter', 'Modern', tracking: 0.34),
  FontChoice('Montserrat', 'Geometric', tracking: 0.42),
  FontChoice('PlayfairDisplay', 'Editorial', tracking: 0.18),
  FontChoice('CormorantGaramond', 'Classic', tracking: 0.24),
  FontChoice('Cinzel', 'Roman', tracking: 0.5),
  FontChoice('Oswald', 'Condensed', tracking: 0.36),
  FontChoice('BebasNeue', 'Display', tracking: 0.6),
  FontChoice('JosefinSans', 'Deco', tracking: 0.48),
  FontChoice('SpaceMono', 'Technical', tracking: 0.2),
];

FontChoice fontByFamily(String family) =>
    kFonts.firstWhere((f) => f.family == family, orElse: () => kFonts.first);
