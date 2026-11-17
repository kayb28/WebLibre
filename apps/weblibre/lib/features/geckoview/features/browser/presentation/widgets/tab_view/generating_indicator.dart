/*
 * Copyright (c) 2026 kayb28 and contributors.
 *
 * This file is part of WebLibre
 * (see https://weblibre.eu).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */
import 'package:flutter/material.dart';

/// A pulsing dot that marks a tab whose chat is currently generating an
/// answer. Purely visual: the same state that drives it also keeps the
/// keep-alive service running (see `chat_session.dart`), so what you see
/// here is what the service is protecting.
///
/// Renders a plain dot while the generation state is `generating` and a
/// static dimmed dot for `stabilizing` — the answer stream just closed and
/// completion is only announced after a short quiet period.
class GeneratingIndicator extends StatefulWidget {
  final bool stabilizing;

  const GeneratingIndicator({super.key, this.stabilizing = false});

  @override
  State<GeneratingIndicator> createState() => _GeneratingIndicatorState();
}

class _GeneratingIndicatorState extends State<GeneratingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.4,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final size = MediaQuery.textScalerOf(context).scale(11.0);

    return SizedBox(
      width: size + 8,
      height: size + 8,
      child: Center(
        child: widget.stabilizing
            ? Container(
                width: size,
                height: size,
                decoration: BoxDecoration(color: color.withAlpha(140), shape: BoxShape.circle),
              )
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _controller.value,
                    child: child,
                  );
                },
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ),
      ),
    );
  }
}
