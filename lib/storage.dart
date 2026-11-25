import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalStorage {
  final Directory dataDir;
  final Directory uploadsDir;
  final File companiesFile;
  final File jobsFile;
  final File applicationsFile;

  LocalStorage({String basePath = 'data'})
      : dataDir = Directory(basePath),
        uploadsDir = Directory('$basePath/uploads'),
        companiesFile = File('$basePath/companies.json'),
        jobsFile = File('$basePath/jobs.json'),
        applicationsFile = File('$basePath/applications.json');

  Future<void> init() async {
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }

    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }

    if (!await companiesFile.exists()) {
      await companiesFile.writeAsString('[]');
    }

    if (!await jobsFile.exists()) {
      await jobsFile.writeAsString('[]');
    }

    if (!await applicationsFile.exists()) {
      await applicationsFile.writeAsString('[]');
    }
  }

  Future<List<Map<String, dynamic>>> readList(File file) async {
    final content = await file.readAsString();

    if (content.trim().isEmpty) {
      return [];
    }

    final decoded = jsonDecode(content) as List;

    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> writeList(
      File file,
      List<Map<String, dynamic>> data,
      ) async {
    final encoded = const JsonEncoder.withIndent('  ').convert(data);

    await file.writeAsString(encoded);
  }
}
