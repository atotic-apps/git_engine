import 'git_object_reader.dart';
import 'git_object_writer.dart';

/// Read and write access to the objects of one repository.
///
/// This is the object storage capability contract: every read operation takes
/// a [GitObjectReader]-style object name and [writeObject] stores a serialized
/// object of any type. It neither interprets revision expressions nor touches
/// the index or the work tree.
///
/// Like its two halves it is a capability contract: a backend implements it
/// only when it can honour every operation.
/// {@category Getting started}
/// {@category Compatibility}
abstract interface class GitObjectStore
    implements GitObjectReader, GitObjectWriter {}
