import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

void configureDio(Dio dio) {
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    // Accept certificates for Railway and Supabase on mobile data
    client.badCertificateCallback = (X509Certificate cert, String host, int port) {
      return host.contains('railway.app') ||
          host.contains('supabase') ||
          host.contains('up.railway.app');
    };
    // Increase idle timeout for mobile data
    client.idleTimeout = const Duration(seconds: 60);
    // Enable auto-uncompress
    client.autoUncompress = true;
    return client;
  };
}
