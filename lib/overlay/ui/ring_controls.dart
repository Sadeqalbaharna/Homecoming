// lib/features/shell/ui/ring_controls.dart
part of floating_kai;

/* =============================== UI ATOMS (Ring Buttons/Badges) ================== */

class _RingButton extends StatelessWidget {
  final Offset center;
  final IconData icon;
  final VoidCallback onTap;
  const _RingButton(
      {required this.center, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    const stroke = Color(0xFFFFE7B0);
    return Positioned(
      left: center.dx - 26,
      top: center.dy - 26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: stroke, width: 2),
          ),
          child: Icon(icon, color: stroke),
        ),
      ),
    );
  }
}

class _RingBadge extends StatelessWidget {
  final Offset center;
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;

  const _RingBadge(
      {required this.center,
      required this.label,
      required this.onTap,
      this.labelColor});

  @override
  Widget build(BuildContext context) {
    const stroke = Color(0xFFFFE7B0);
    final textColor = labelColor ?? stroke;
    return Positioned(
      left: center.dx - 28,
      top: center.dy - 28,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: stroke, width: 2),
          ),
          child: Text(label,
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.w800, fontSize: 16)),
        ),
      ),
    );
  }
}
