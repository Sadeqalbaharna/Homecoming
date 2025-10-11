import 'package:flutter/material.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.transparent, // keep it invisible behind the avatar
      child: child,
    );
  }
}
