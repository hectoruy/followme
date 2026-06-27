import 'package:flutter_test/flutter_test.dart';
import 'package:mauro_taxi/config/app_config.dart';

void main() {
  test('app config is present', () {
    expect(AppConfig.supabaseUrl, startsWith('https://'));
    expect(AppConfig.supabaseAnonKey, isNotEmpty);
    expect(AppConfig.clientBaseUrl, startsWith('https://'));
  });
}
