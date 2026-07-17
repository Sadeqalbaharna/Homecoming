import 'package:flutter_test/flutter_test.dart';
import 'package:homecoming_app/services/core/reply_chunker_service.dart';

void main() {
  const chunker = ReplyChunkerService();

  test('splits long replies on paragraph boundaries instead of one wall', () {
    final chunks = chunker.chunks('''First short paragraph.

Second paragraph with the actual useful bit.

Third paragraph so the UI can reveal this like breathing instead of dropping a brick.''');

    expect(chunks, hasLength(3));
    expect(chunks[0], 'First short paragraph.');
    expect(chunks[1], 'Second paragraph with the actual useful bit.');
    expect(chunks[2], startsWith('Third paragraph'));
  });

  test('keeps fenced code blocks whole', () {
    final chunks = chunker.chunks('''Here is the patch:

```dart
void main() {
  print('tiny syntax criminal');
}
```

Then the explanation.''');

    expect(chunks, hasLength(3));
    expect(chunks[1], contains('```dart'));
    expect(chunks[1], contains("print('tiny syntax criminal')"));
    expect(chunks[1], contains('```'));
  });

  test('empty replies still render an honest placeholder', () {
    expect(chunker.chunks('   '), ['(no reply)']);
  });
}
