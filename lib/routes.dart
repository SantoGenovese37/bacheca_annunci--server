import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:mime/mime.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'storage.dart';

class JobBoardApi {
  final LocalStorage storage;
  final Map<String, String> _sessions = {};

  JobBoardApi(this.storage);

  String _generateId(String prefix) {
    final rnd = Random.secure();
    final n = rnd.nextInt(99999999);
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}_$n';
  }

  String? _getAuthenticatedCompanyId(Request req) {
    final auth = req.headers['authorization'];

    if (auth == null || !auth.startsWith('Bearer ')) {
      return null;
    }

    final token = auth.substring(7).trim();
    return _sessions[token];
  }

  Response _json(int status, Object body) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
      },
    );
  }

  Router get router {
    final r = Router();

    // REGISTRAZIONE AZIENDA
    r.post('/auth/register', (Request req) async {
      final body =
          jsonDecode(await req.readAsString()) as Map<String, dynamic>;

      final name = (body['name'] ?? '').toString().trim();
      final email = (body['email'] ?? '').toString().trim().toLowerCase();
      final password = (body['password'] ?? '').toString();

      if (name.isEmpty || email.isEmpty || password.isEmpty) {
        return _json(400, {
          'error': 'Inserisci nome azienda, email e password.',
        });
      }

      final companies = await storage.readList(storage.companiesFile);

      if (companies.any((c) => c['email'] == email)) {
        return _json(409, {
          'error': 'Questa email è già registrata.',
        });
      }

      final company = {
        'id': _generateId('comp'),
        'name': name,
        'email': email,
        'password': password,
      };

      companies.add(company);
      await storage.writeList(storage.companiesFile, companies);

      return _json(201, {
        'id': company['id'],
        'name': name,
        'email': email,
      });
    });

    // LOGIN AZIENDA
    r.post('/auth/login', (Request req) async {
      final body =
          jsonDecode(await req.readAsString()) as Map<String, dynamic>;

      final email = (body['email'] ?? '').toString().trim().toLowerCase();
      final password = (body['password'] ?? '').toString();

      final companies = await storage.readList(storage.companiesFile);

      final matches = companies.where(
        (c) => c['email'] == email && c['password'] == password,
      );

      if (matches.isEmpty) {
        return _json(401, {
          'error': 'Email o password non validi.',
        });
      }

      final company = matches.first;
      final token = _generateId('tok');

      _sessions[token] = company['id'] as String;

      return _json(200, {
        'token': token,
        'companyId': company['id'],
        'companyName': company['name'],
      });
    });

    // ELENCO PUBBLICO DEGLI ANNUNCI
    r.get('/jobs', (Request req) async {
      final jobs = await storage.readList(storage.jobsFile);
      return _json(200, jobs);
    });

    // CREAZIONE ANNUNCIO
    r.post('/jobs', (Request req) async {
      final companyId = _getAuthenticatedCompanyId(req);

      if (companyId == null) {
        return _json(401, {
          'error': 'Devi effettuare il login.',
        });
      }

      final body =
          jsonDecode(await req.readAsString()) as Map<String, dynamic>;

      final title = (body['title'] ?? '').toString().trim();
      final description = (body['description'] ?? '').toString().trim();

      if (title.isEmpty || description.isEmpty) {
        return _json(400, {
          'error': 'Titolo e descrizione sono obbligatori.',
        });
      }

      final companies = await storage.readList(storage.companiesFile);

      final company = companies.firstWhere(
        (c) => c['id'] == companyId,
      );

      final jobs = await storage.readList(storage.jobsFile);

      final job = {
        'id': _generateId('job'),
        'companyId': companyId,
        'companyName': company['name'],
        'title': title,
        'description': description,
        'createdAt': DateTime.now().toIso8601String(),
      };

      jobs.add(job);
      await storage.writeList(storage.jobsFile, jobs);

      return _json(201, job);
    });

    // ANNUNCI DELL'AZIENDA AUTENTICATA
    r.get('/my-jobs', (Request req) async {
      final companyId = _getAuthenticatedCompanyId(req);

      if (companyId == null) {
        return _json(401, {
          'error': 'Devi effettuare il login.',
        });
      }

      final jobs = await storage.readList(storage.jobsFile);

      final mine = jobs
          .where((j) => j['companyId'] == companyId)
          .toList();

      return _json(200, mine);
    });

    // ELIMINAZIONE ANNUNCIO
    r.delete('/jobs/<jobId>', (Request req, String jobId) async {
      final companyId = _getAuthenticatedCompanyId(req);

      if (companyId == null) {
        return _json(401, {
          'error': 'Devi effettuare il login.',
        });
      }

      final jobs = await storage.readList(storage.jobsFile);

      final index = jobs.indexWhere(
        (j) => j['id'] == jobId,
      );

      if (index == -1) {
        return _json(404, {
          'error': 'Annuncio non trovato.',
        });
      }

      if (jobs[index]['companyId'] != companyId) {
        return _json(403, {
          'error': 'Non puoi eliminare un annuncio di un’altra azienda.',
        });
      }

      final applications =
          await storage.readList(storage.applicationsFile);

      final jobApplications = applications
          .where((a) => a['jobId'] == jobId)
          .toList();

      // Elimina i CV associati alle candidature dell'annuncio.
      for (final application in jobApplications) {
        final fileName = application['cvFileName']?.toString();

        if (fileName != null && fileName.isNotEmpty) {
          final file = File(
            '${storage.uploadsDir.path}/$fileName',
          );

          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      // Elimina le candidature associate.
      applications.removeWhere(
        (a) => a['jobId'] == jobId,
      );

      await storage.writeList(
        storage.applicationsFile,
        applications,
      );

      // Elimina l'annuncio.
      jobs.removeAt(index);

      await storage.writeList(
        storage.jobsFile,
        jobs,
      );

      return _json(200, {
        'message': 'Annuncio eliminato correttamente.',
      });
    });

    // INVIO CANDIDATURA
    r.post('/jobs/<jobId>/apply', (Request req, String jobId) async {
      final jobs = await storage.readList(storage.jobsFile);

      if (!jobs.any((j) => j['id'] == jobId)) {
        return _json(404, {
          'error': 'Annuncio non trovato.',
        });
      }

      final contentType = req.headers['content-type'];

      if (contentType == null ||
          !contentType.contains('multipart/form-data')) {
        return _json(400, {
          'error': 'Formato richiesta non valido (multipart/form-data).',
        });
      }

      final boundaryMatch =
          RegExp(r'boundary=([^;]+)').firstMatch(contentType);

      if (boundaryMatch == null) {
        return _json(400, {
          'error': 'Boundary multipart mancante.',
        });
      }

      final boundary =
          boundaryMatch.group(1)!.replaceAll('"', '').trim();

      final fields = <String, String>{};
      String? savedFileName;

      final transformer = MimeMultipartTransformer(boundary);

      await for (final part in transformer.bind(req.read())) {
        final disposition =
            part.headers['content-disposition'] ?? '';

        final nameMatch =
            RegExp(r'name="([^"]+)"').firstMatch(disposition);

        if (nameMatch == null) continue;

        final fieldName = nameMatch.group(1)!;

        final filenameMatch =
            RegExp(r'filename="([^"]+)"').firstMatch(disposition);

        if (filenameMatch != null) {
          final rawName = filenameMatch.group(1)!;

          final cleanName = rawName.replaceAll(
            RegExp(r'[^a-zA-Z0-9.\_-]'),
            '_',
          );

          final uniqueName =
              '${_generateId("cv")}_$cleanName';

          final file = File(
            '${storage.uploadsDir.path}/$uniqueName',
          );

          final sink = file.openWrite();

          await part.pipe(sink);
          await sink.close();

          savedFileName = uniqueName;
        } else {
          final value = await utf8.decoder.bind(part).join();
          fields[fieldName] = value.trim();
        }
      }

      final firstName = fields['firstName'] ?? '';
      final lastName = fields['lastName'] ?? '';
      final email = fields['email'] ?? '';

      if (firstName.isEmpty ||
          lastName.isEmpty ||
          email.isEmpty ||
          savedFileName == null) {
        return _json(400, {
          'error':
              'Compila nome, cognome, email e allega il curriculum.',
        });
      }

      final apps = await storage.readList(storage.applicationsFile);

      final application = {
        'id': _generateId('app'),
        'jobId': jobId,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'cvFileName': savedFileName,
        'submittedAt': DateTime.now().toIso8601String(),
      };

      apps.add(application);

      await storage.writeList(
        storage.applicationsFile,
        apps,
      );

      return _json(201, application);
    });

    // CANDIDATURE RICEVUTE PER UN ANNUNCIO
    r.get(
      '/my-jobs/<jobId>/applications',
      (Request req, String jobId) async {
        final companyId = _getAuthenticatedCompanyId(req);

        if (companyId == null) {
          return _json(401, {
            'error': 'Devi effettuare il login.',
          });
        }

        final jobs = await storage.readList(storage.jobsFile);

        final ownsJob = jobs.any(
          (j) => j['id'] == jobId && j['companyId'] == companyId,
        );

        if (!ownsJob) {
          return _json(403, {
            'error': 'Non hai i permessi per questo annuncio.',
          });
        }

        final apps =
            await storage.readList(storage.applicationsFile);

        final filtered = apps
            .where((a) => a['jobId'] == jobId)
            .toList();

        return _json(200, filtered);
      },
    );

    // DOWNLOAD / VISUALIZZAZIONE CV
    r.get('/cv/<filename>', (Request req, String filename) async {
      final safeName = filename
          .replaceAll('/', '')
          .replaceAll('\\', '');

      final file = File(
        '${storage.uploadsDir.path}/$safeName',
      );

      if (!await file.exists()) {
        return Response.notFound('Curriculum non trovato.');
      }

      final mimeType =
          lookupMimeType(file.path) ?? 'application/pdf';

      return Response.ok(
        file.openRead(),
        headers: {
          'Content-Type': mimeType,
          'Content-Disposition': 'inline; filename="$safeName"',
        },
      );
    });

    return r;
  }
}
