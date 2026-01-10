/// Represents an eBook file (PDF or EPUB) associated with an audiobook.
class EBook {
  final String id;
  final String title;
  final String? author;
  final String filePath;
  final EBookType type;
  final String? associatedAudiobookId;
  DateTime? lastRead;
  int lastPage;
  String? lastCfi; // EPUB location (CFI = Canonical Fragment Identifier)

  EBook({
    required this.id,
    required this.title,
    this.author,
    required this.filePath,
    required this.type,
    this.associatedAudiobookId,
    this.lastRead,
    this.lastPage = 0,
    this.lastCfi,
  });

  /// Create from file path, auto-detecting type from extension.
  factory EBook.fromFile(String filePath, {String? audiobookId}) {
    final fileName = filePath.split('/').last.split('\\').last;
    final extension = fileName.split('.').last.toLowerCase();
    final title = fileName.replaceAll(RegExp(r'\.(pdf|epub)$', caseSensitive: false), '');
    
    return EBook(
      id: filePath.hashCode.toString(),
      title: title,
      filePath: filePath,
      type: extension == 'epub' ? EBookType.epub : EBookType.pdf,
      associatedAudiobookId: audiobookId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'filePath': filePath,
      'type': type.name,
      'associatedAudiobookId': associatedAudiobookId,
      'lastRead': lastRead?.toIso8601String(),
      'lastPage': lastPage,
      'lastCfi': lastCfi,
    };
  }

  factory EBook.fromJson(Map<String, dynamic> json) {
    return EBook(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      filePath: json['filePath'] as String,
      type: EBookType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => EBookType.pdf,
      ),
      associatedAudiobookId: json['associatedAudiobookId'] as String?,
      lastRead: json['lastRead'] != null 
          ? DateTime.tryParse(json['lastRead'] as String) 
          : null,
      lastPage: json['lastPage'] as int? ?? 0,
      lastCfi: json['lastCfi'] as String?,
    );
  }

  EBook copyWith({
    String? id,
    String? title,
    String? author,
    String? filePath,
    EBookType? type,
    String? associatedAudiobookId,
    DateTime? lastRead,
    int? lastPage,
    String? lastCfi,
  }) {
    return EBook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      type: type ?? this.type,
      associatedAudiobookId: associatedAudiobookId ?? this.associatedAudiobookId,
      lastRead: lastRead ?? this.lastRead,
      lastPage: lastPage ?? this.lastPage,
      lastCfi: lastCfi ?? this.lastCfi,
    );
  }
}

enum EBookType { pdf, epub }
