import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart' as prism;

void main() {
  testWidgets('flat glass is left out of the host capture', (tester) async {
    Widget app({required bool flat}) => MaterialApp(
      home: prism.LiquidGlassScope(
        enabled: true,
        child: prism.LiquidGlassHost(
          enabled: true,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.teal)),
              Positioned(
                left: 20,
                top: 20,
                width: 120,
                height: 48,
                child: prism.LiquidGlassFlat(
                  flat: flat,
                  child: prism.LiquidGlass(
                    style: const prism.LiquidGlassStyle(
                      tint: Color(0x8AFDFDFD),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(flat: false));
    await tester.pump();
    expect(prism.LiquidGlassHost.debugLastCapture!.panes, hasLength(1));

    await tester.pumpWidget(app(flat: true));
    await tester.pump();
    expect(prism.LiquidGlassHost.debugLastCapture!.panes, isEmpty);

    await tester.pumpWidget(app(flat: false));
    await tester.pump();
    expect(prism.LiquidGlassHost.debugLastCapture!.panes, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
