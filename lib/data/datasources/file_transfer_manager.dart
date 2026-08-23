import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../domain/entities/chat_message.dart';

const int kChunkSizeBytes = 64 * 1024; // 64 KB per chunk

class FileMetadataPayload {
  final String fileId;
  final String fileName;
  final int totalBytes;
  final String mimeType;
  final int totalChunks;
  final String messageType;

  FileMetadataPayload({
    required this.fileId,
    required this.fileName,
    required this.totalBytes,
    required this.mimeType,
    required this.totalChunks,
    required this.messageType,
  });

  Map<String, dynamic> toMap() => {
        'fileId': fileId,
        'fileName': fileName,
        'totalBytes': totalBytes,
        'mimeType': mimeType,
        'totalChunks': totalChunks,
        'messageType': messageType,
      };

  factory FileMetadataPayload.fromMap(Map<String, dynamic> map) =>
      FileMetadataPayload(
        fileId: map['fileId'] as String? ?? '',
        fileName: map['fileName'] as String? ?? 'file',
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
        mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
        totalChunks: (map['totalChunks'] as num?)?.toInt() ?? 1,
        messageType: map['messageType'] as String? ?? 'file',
      );

  String toJson() => jsonEncode(toMap());
  factory FileMetadataPayload.fromJson(String str) =>
      FileMetadataPayload.fromMap(jsonDecode(str) as Map<String, dynamic>);
}

class FileChunkPayload {
  final String fileId;
  final int chunkIndex;
  final int totalChunks;
  final String dataBase64;

  FileChunkPayload({
    required this.fileId,
    required this.chunkIndex,
    required this.totalChunks,
    required this.dataBase64,
  });

  Map<String, dynamic> toMap() => {
        'fileId': fileId,
        'chunkIndex': chunkIndex,
        'totalChunks': totalChunks,
        'dataBase64': dataBase64,
      };

  factory FileChunkPayload.fromMap(Map<String, dynamic> map) =>
      FileChunkPayload(
        fileId: map['fileId'] as String? ?? '',
        chunkIndex: (map['chunkIndex'] as num?)?.toInt() ?? 0,
        totalChunks: (map['totalChunks'] as num?)?.toInt() ?? 1,
        dataBase64: map['dataBase64'] as String? ?? '',
      );

  String toJson() => jsonEncode(toMap());
  factory FileChunkPayload.fromJson(String str) =>
      FileChunkPayload.fromMap(jsonDecode(str) as Map<String, dynamic>);
}

class IncomingFileAssembly {
  final FileMetadataPayload metadata;
  final String targetPath;
  final Map<int, List<int>> receivedChunks = {};

  IncomingFileAssembly({
    required this.metadata,
    required this.targetPath,
  });
}

class FileTransferManager {
  final Map<String, IncomingFileAssembly> _activeIncoming = {};
  final Set<String> _cancelledTransfers = {};

  void cancelTransfer(String fileId) {
    _cancelledTransfers.add(fileId);
    final assembly = _activeIncoming.remove(fileId);
    if (assembly != null) {
      final f = File(assembly.targetPath);
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  bool isTransferCancelled(String fileId) => _cancelledTransfers.contains(fileId);

  Future<String> getAttachmentsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final attachDir = Directory(p.join(appDir.path, 'attachments'));
    if (!await attachDir.exists()) {
      await attachDir.create(recursive: true);
    }
    return attachDir.path;
  }

  // Prepares file metadata and yields chunks for sending
  Future<FileMetadataPayload> prepareFileForSend({
    required String fileId,
    required File file,
    required MessageType type,
  }) async {
    final bytes = await file.length();
    final totalChunks = (bytes / kChunkSizeBytes).ceil().clamp(1, 999999);
    final fileName = p.basename(file.path);
    final mime = _guessMimeType(fileName, type);

    return FileMetadataPayload(
      fileId: fileId,
      fileName: fileName,
      totalBytes: bytes,
      mimeType: mime,
      totalChunks: totalChunks,
      messageType: type.name,
    );
  }

  Stream<FileChunkPayload> streamFileChunks({
    required String fileId,
    required File file,
    required int totalChunks,
  }) async* {
    final reader = file.openRead();
    int chunkIndex = 0;
    List<int> buffer = [];

    await for (final chunk in reader) {
      buffer.addAll(chunk);
      while (buffer.length >= kChunkSizeBytes) {
        final slice = buffer.sublist(0, kChunkSizeBytes);
        buffer = buffer.sublist(kChunkSizeBytes);
        yield FileChunkPayload(
          fileId: fileId,
          chunkIndex: chunkIndex,
          totalChunks: totalChunks,
          dataBase64: base64Encode(slice),
        );
        chunkIndex++;
      }
    }

    if (buffer.isNotEmpty) {
      yield FileChunkPayload(
        fileId: fileId,
        chunkIndex: chunkIndex,
        totalChunks: totalChunks,
        dataBase64: base64Encode(buffer),
      );
    }
  }

  // Starts receiving a file upon receiving FILE_META
  Future<void> handleIncomingMeta(FileMetadataPayload meta) async {
    final attachDir = await getAttachmentsDirectory();
    final safeFileName = '${meta.fileId}_${meta.fileName}';
    final targetFile = File(p.join(attachDir, safeFileName));

    _activeIncoming[meta.fileId] = IncomingFileAssembly(
      metadata: meta,
      targetPath: targetFile.path,
    );
  }

  // Appends chunk data with index-based assembly to prevent out-of-order corruption
  Future<({double progress, bool isCompleted, String? localPath})?> handleIncomingChunk(
      FileChunkPayload chunk) async {
    final assembly = _activeIncoming[chunk.fileId];
    if (assembly == null) return null;

    final bytes = base64Decode(chunk.dataBase64);
    assembly.receivedChunks[chunk.chunkIndex] = bytes;

    final progress = (assembly.receivedChunks.length / assembly.metadata.totalChunks).clamp(0.0, 1.0);

    if (assembly.receivedChunks.length >= assembly.metadata.totalChunks) {
      // Reassemble all chunks in exact sequential order 0..totalChunks-1
      final targetFile = File(assembly.targetPath);
      final raf = await targetFile.open(mode: FileMode.write);
      for (int i = 0; i < assembly.metadata.totalChunks; i++) {
        final chunkData = assembly.receivedChunks[i];
        if (chunkData != null) {
          await raf.writeFrom(chunkData);
        }
      }
      await raf.flush();
      await raf.close();

      final finalPath = assembly.targetPath;
      _activeIncoming.remove(chunk.fileId);
      return (progress: 1.0, isCompleted: true, localPath: finalPath);
    }

    return (progress: progress, isCompleted: false, localPath: null);
  }

  String _guessMimeType(String filename, MessageType type) {
    final ext = p.extension(filename).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.pdf':
        return 'application/pdf';
      case '.apk':
        return 'application/vnd.android.package-archive';
      case '.zip':
      case '.rar':
      case '.7z':
        return 'application/zip';
      case '.doc':
      case '.docx':
        return 'application/msword';
      case '.xls':
      case '.xlsx':
        return 'application/vnd.ms-excel';
      case '.ppt':
      case '.pptx':
        return 'application/vnd.ms-powerpoint';
      case '.txt':
        return 'text/plain';
      case '.mp3':
      case '.wav':
      case '.m4a':
      case '.aac':
        return 'audio/mpeg';
      default:
        return type == MessageType.image
            ? 'image/jpeg'
            : (type == MessageType.video ? 'video/mp4' : 'application/octet-stream');
    }
  }
}
