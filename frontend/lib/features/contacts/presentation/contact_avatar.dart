import 'package:communication_platform/features/contacts/domain/contact_model.dart';
import 'package:flutter/material.dart';

class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    required this.username,
    required this.semanticLabel,
    this.authenticatedSeed,
    this.radius = 24,
    super.key,
  });

  final String username;
  final String semanticLabel;
  final int? authenticatedSeed;
  final double radius;

  static const _colors = <Color>[
    Color(0xff315c9b),
    Color(0xff276749),
    Color(0xff805ad5),
    Color(0xff9c4221),
    Color(0xff2c7a7b),
    Color(0xff97266d),
    Color(0xff744210),
    Color(0xff4a5568),
  ];

  @override
  Widget build(BuildContext context) {
    final placeholder = PlaceholderAvatarStyle.fromUsername(username);
    final index = authenticatedSeed == null
        ? placeholder.paletteIndex
        : authenticatedSeed!.abs() % _colors.length;
    return Semantics(
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: CircleAvatar(
          radius: radius,
          backgroundColor: _colors[index],
          foregroundColor: Colors.white,
          child: Text(
            placeholder.initials,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: radius * .72,
            ),
          ),
        ),
      ),
    );
  }
}
