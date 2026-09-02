import 'package:flutter/widgets.dart';

import 'player_controller.dart';

/// Renders [controller] frames. Not a control bar.
class PlayerView extends StatelessWidget {
  const PlayerView({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: controller.textureIdListenable,
      builder: (context, textureId, _) {
        if (textureId == null) {
          return const ColoredBox(color: Color(0xFF000000));
        }
        return Texture(textureId: textureId);
      },
    );
  }
}
