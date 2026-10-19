import 'package:flutter_test/flutter_test.dart';
import 'package:img2pdf/models/edit_params.dart';

void main() {
  test('quattro rotazioni tornano all\'origine', () {
    var p = const EditParams(crop: CropRect(0.1, 0.2, 0.3, 0.4));
    for (var i = 0; i < 4; i++) {
      p = p.rotateClockwise();
    }
    expect(p.quarterTurns, 0);
    expect(p.crop!.left, closeTo(0.1, 1e-9));
    expect(p.crop!.top, closeTo(0.2, 1e-9));
  });

  test('dimensione di output con rotazione, ritaglio e scala', () {
    const p = EditParams(
        quarterTurns: 1, crop: CropRect(0, 0, 0.5, 0.5), scale: 0.5);
    expect(p.outputSize(4000, 3000), (750, 1000));
  });
}
