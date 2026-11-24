import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sendoh_organizer/push_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new user defaults on while an existing opt-out survives', () async {
    FlutterSecureStorage.setMockInitialValues({'sendoh_push_existing': 'false'});
    expect(await PushService.optedIn('new'), isTrue);
    expect(await PushService.optedIn('existing'), isFalse);
  });

  test('a saved opt-in remains enabled', () async {
    FlutterSecureStorage.setMockInitialValues({'sendoh_push_existing': 'true'});
    expect(await PushService.optedIn('existing'), isTrue);
  });
}
