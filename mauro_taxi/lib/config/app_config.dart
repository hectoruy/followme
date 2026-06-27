class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hoczdolplvaiupcqlmgv.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhvY3pkb2xwbHZhaXVwY3FsbWd2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg3MDY2NzcsImV4cCI6MjA5NDI4MjY3N30.8PiSDBCbmEDOChOSY1GSXD-llASolQ67Zg6QTJaO2U0',
  );

  static const clientBaseUrl = String.fromEnvironment(
    'CLIENT_BASE_URL',
    defaultValue: 'https://project-jcd2n.vercel.app/cliente',
  );

  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError('Missing Supabase configuration');
    }
  }
}
