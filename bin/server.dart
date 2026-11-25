import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:server/storage.dart';
import 'package:server/routes.dart';

Future<void> main() async {
  final storage = LocalStorage(basePath: 'data');
  await storage.init();

  final api = JobBoardApi(storage);
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(api.router.call);

  final port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Server avviato su http://${server.address.address}:${server.port}');
}
