import 'package:dio/dio.dart';

// No-op for web platform — SSL configuration is not needed
void configureDio(Dio dio) {
  // Web uses browser's built-in HTTP client
}
