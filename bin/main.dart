
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:server/routes.dart';
import 'package:server/storage.dart';

Future<void> main() async {
  final storage = LocalStorage();
  await storage.init();

  final api = JobBoardApi(storage);

  final server = await shelf_io.serve(
    api.router,
    InternetAddress.anyIPv4,
    8080,
  );

  print('Server avviato su http://0.0.0.0:${server.port}');
}
